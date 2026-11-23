import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location("business", Path(__file__).resolve().parents[1] / "business.py")
business = importlib.util.module_from_spec(spec)
spec.loader.exec_module(business)


def configuration():
    return {
        "run_id": "a" * 32,
        "case_id": "S-01",
        "phase": "baseline",
        "kind": "blob",
        "operations": 1,
        "interval_seconds": 0,
        "request_timeout": 1,
        "maximum_run_seconds": 120,
        "minimum_success": 1,
        "streams": {
            "canary": {"endpoint": "https://canary.blob.core.windows.net", "entity": "chaos-test",
                       "resource_id": "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Storage/storageAccounts/canary"},
            "control": {"endpoint": "https://control.blob.core.windows.net", "entity": "chaos-test",
                        "resource_id": "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/fixture/providers/Microsoft.Storage/storageAccounts/control"},
        },
    }


class FakeBlob:
    def __init__(self, uncertain=False, corrupt=False):
        self.values = {}
        self.uncertain = uncertain
        self.corrupt = corrupt
        self.sends = 0

    def send(self, operation_id, payload):
        self.sends += 1
        self.values[operation_id] = payload
        if self.uncertain:
            raise business.TrafficFailure("TimeoutError")

    def verify(self, store, run_id, stream, timeout, remaining_seconds):
        for operation in store.operations(run_id, stream):
            payload = self.values.get(operation["operation_id"])
            if payload is not None:
                store.effect(operation["operation_id"], b"wrong" if self.corrupt else payload, settled=True)

    def close(self):
        pass


class BusinessTests(unittest.TestCase):
    def test_default_cli_validates_without_creating_clients_or_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "flow.json"
            config.write_text(json.dumps(configuration()))
            output = io.StringIO()
            with patch.object(business, "make_client") as factory, contextlib.redirect_stdout(output):
                self.assertEqual(business.main(["--config", str(config)]), 0)
            factory.assert_not_called()
            self.assertEqual(json.loads(output.getvalue())["evidence_scope"], "configuration validation only")
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_execute_requires_explicit_traffic_opt_in_and_durable_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "flow.json"
            config.write_text(json.dumps(configuration()))
            with patch.object(business, "make_client") as factory, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(business.main(["--config", str(config), "--execute"]), 3)
            factory.assert_not_called()

    def test_same_dependency_and_token_urls_are_rejected(self):
        for mutate in (
            lambda config: config["streams"].update(control=config["streams"]["canary"].copy()),
            lambda config: config["streams"]["canary"].update(endpoint="https://canary.blob.core.windows.net?sig=secret"),
            lambda config: config["streams"]["canary"].update(entity="*"),
            lambda config: config.update(operations=True),
            lambda config: config.update(request_timeout=float("nan")),
        ):
            config = configuration()
            mutate(config)
            with self.assertRaises(ValueError):
                business.validate_config(config)

    def test_unknown_config_fields_and_unsupported_cases_are_rejected(self):
        for extra in ({"password": "must-not-be-used"}, {"case_id": "V-02"}, {"phase": "production"}):
            with self.assertRaises(ValueError):
                business.validate_config({**configuration(), **extra})

    def test_successful_reference_work_requires_two_independent_streams(self):
        with tempfile.TemporaryDirectory() as directory:
            result = business.execute(configuration(), Path(directory) / "ledger.sqlite",
                                      {"canary": FakeBlob(), "control": FakeBlob()}, emit=lambda record: None)
        self.assertEqual(result["result"], "Passed")
        self.assertEqual(set(result["streams"]), {"canary", "control"})
        self.assertFalse(result["fault_actions_executed"])

    def test_lost_send_ack_is_persisted_and_not_blindly_retried(self):
        canary = FakeBlob(uncertain=True)
        with tempfile.TemporaryDirectory() as directory:
            result = business.execute(configuration(), Path(directory) / "ledger.sqlite",
                                      {"canary": canary, "control": FakeBlob()}, emit=lambda record: None)
        self.assertEqual(canary.sends, 1)
        self.assertEqual(result["streams"]["canary"]["unknown"], 1)
        self.assertEqual(result["streams"]["canary"]["resolved_unknown"], 1)
        self.assertEqual(result["result"], "Failed")

    def test_payload_conflict_fails_and_stops_reference_work(self):
        with tempfile.TemporaryDirectory() as directory:
            result = business.execute(configuration(), Path(directory) / "ledger.sqlite",
                                      {"canary": FakeBlob(corrupt=True), "control": FakeBlob()}, emit=lambda record: None)
        self.assertEqual(result["result"], "Failed")
        self.assertTrue(result["stop_recommended"])

    def test_live_records_match_existing_availability_evaluator_schema(self):
        import stop
        records = []
        with tempfile.TemporaryDirectory() as directory:
            business.execute(configuration(), Path(directory) / "ledger.sqlite",
                             {"canary": FakeBlob(), "control": FakeBlob()}, emit=records.append)
        evaluator = stop.Evaluator({"streams": ["control"], "window_operations": 1, "minimum_success": 1,
                                   "maximum_silence_seconds": 5, "maximum_monitor_seconds": 120})
        for record in records:
            evaluator.feed(record)
        self.assertEqual(evaluator.finish()["result"], "Passed")
        self.assertNotIn("blob.core.windows.net", json.dumps(records))

    def test_reference_run_is_not_automatically_resumed_after_a_crash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.sqlite"
            business.execute(configuration(), path, {"canary": FakeBlob(), "control": FakeBlob()},
                             emit=lambda record: None)

    def test_service_bus_commits_effect_before_settlement_and_handles_redelivery(self):
        with tempfile.TemporaryDirectory() as directory:
            store = business.Ledger(Path(directory) / "ledger.sqlite")
            self.addCleanup(store.close)
            store.start_run("a" * 32, "B-01", "exposure", 1, "servicebus")
            operation_id = store.intent("a" * 32, "canary", 0, b"synthetic")
            message = MagicMock(message_id=operation_id, body=[b"synthetic"])
            client = MagicMock()
            receiver = client.get_queue_receiver.return_value.__enter__.return_value
            receiver.receive_messages.return_value = [message]
            receiver.complete_message.side_effect = TimeoutError
            workload = business.ServiceBusWorkload(client, "chaos-test", 1, MagicMock(), "peeklock", (TimeoutError,))
            with self.assertRaises(business.TrafficFailure):
                workload.verify(store, "a" * 32, "canary", 1, 2)
            effect = store.operations("a" * 32, "canary")[0]
            self.assertEqual((effect["effect_count"], effect["settled"]), (1, 0))
            receiver.complete_message.side_effect = None
            workload.verify(store, "a" * 32, "canary", 1, 2)
            effect = store.operations("a" * 32, "canary")[0]
            self.assertEqual((effect["effect_count"], effect["delivery_attempts"], effect["settled"]), (1, 2, 1))

    def test_unrelated_service_bus_message_is_not_committed_or_completed(self):
        with tempfile.TemporaryDirectory() as directory:
            store = business.Ledger(Path(directory) / "ledger.sqlite")
            self.addCleanup(store.close)
            store.start_run("a" * 32, "B-01", "exposure", 1, "servicebus")
            store.intent("a" * 32, "canary", 0, b"synthetic")
            message = MagicMock(message_id="f" * 32, body=[b"unrelated"])
            client = MagicMock()
            receiver = client.get_queue_receiver.return_value.__enter__.return_value
            receiver.receive_messages.return_value = [message]
            workload = business.ServiceBusWorkload(client, "chaos-test", 1, MagicMock(), "peeklock", (TimeoutError,))
            with self.assertRaises(business.TrafficFailure):
                workload.verify(store, "a" * 32, "canary", 1, 2)
            receiver.abandon_message.assert_called_once_with(message)
            receiver.complete_message.assert_not_called()
            self.assertEqual(store.operations("a" * 32, "canary")[0]["effect_count"], 0)

    def test_blob_read_is_bounded_and_corrupt_content_is_a_failed_integrity_check(self):
        with tempfile.TemporaryDirectory() as directory:
            store = business.Ledger(Path(directory) / "ledger.sqlite")
            self.addCleanup(store.close)
            store.start_run("a" * 32, "S-01", "exposure", 1, "blob")
            operation_id = store.intent("a" * 32, "canary", 0, b"synthetic")
            container = MagicMock()
            container.download_blob.return_value.readall.return_value = b"x" * 4097
            workload = business.BlobWorkload(container, 1, (TimeoutError,))
            with self.assertRaises(business.TrafficFailure):
                workload.verify(store, "a" * 32, "canary", 1, 2)
            container.download_blob.assert_called_once_with("chaos/" + operation_id, offset=0, length=4097, timeout=1)
            self.assertEqual(store.evaluate("a" * 32, 0, 1)["result"], "Failed")

    def test_recovery_verifies_original_unknown_cohort_without_resending(self):
        class TemporarilyUnavailable(FakeBlob):
            def verify(self, *args):
                raise business.TrafficFailure("ServiceUnavailable")

        canary = TemporarilyUnavailable(uncertain=True)
        control = FakeBlob()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ledger.sqlite"
            first = business.execute(configuration(), path, {"canary": canary, "control": control},
                                     emit=lambda record: None)
            self.assertEqual(first["result"], "Inconclusive")
            recovered = FakeBlob()
            recovered.values = canary.values
            result = business.verify_existing(configuration(), path, {"canary": recovered, "control": control},
                                              emit=lambda record: None)
            self.assertEqual(result["streams"]["canary"]["resolved_unknown"], 1)
            self.assertEqual(recovered.sends, 0)
            self.assertEqual(canary.sends, 1)
            self.assertEqual(result["result"], "Failed")
            with self.assertRaises(business.LedgerConflict):
                business.execute(configuration(), path, {"canary": FakeBlob(), "control": FakeBlob()},
                                 emit=lambda record: None)


if __name__ == "__main__":
    unittest.main()
