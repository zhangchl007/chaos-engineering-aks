import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("ledger", Path(__file__).resolve().parents[1] / "ledger.py")
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "operations.sqlite"
        self.store = ledger.Ledger(self.path)
        self.run_id = "a" * 32
        self.store.start_run(self.run_id, "S-01", "baseline", 1, "blob")

    def tearDown(self):
        self.store.close()
        self.directory.cleanup()

    def planned(self, stream="canary"):
        return self.store.intent(self.run_id, stream, 0, b"synthetic")

    def test_intent_survives_process_restart_before_acknowledgment(self):
        operation_id = self.planned()
        self.store.close()
        self.store = ledger.Ledger(self.path, read_only=True)
        self.assertEqual(self.store.operations(self.run_id, "canary")[0]["operation_id"], operation_id)
        self.assertEqual(self.store.evaluate(self.run_id, 0, 1)["result"], "Inconclusive")

    def test_unknown_outcome_is_not_silently_retried_or_counted_as_ack(self):
        operation_id = self.planned()
        self.store.outcome(operation_id, "unknown", 0.1, "TimeoutError")
        self.store.effect(operation_id, b"synthetic")
        result = self.store.evaluate(self.run_id, 0, 1)
        self.assertEqual(result["streams"]["canary"]["acknowledged"], 0)
        self.assertEqual(result["streams"]["canary"]["resolved_unknown"], 1)
        self.assertEqual(result["result"], "Inconclusive")

    def test_missing_acknowledged_effect_cannot_pass(self):
        for stream in ("canary", "control"):
            operation_id = self.planned(stream)
            self.store.outcome(operation_id, "acknowledged", 0.1)
        self.store.finish_run(self.run_id)
        self.assertEqual(self.store.evaluate(self.run_id, 1, 1)["result"], "Inconclusive")

    def test_matching_effects_and_complete_cohort_pass_reference_scope_only(self):
        for stream in ("canary", "control"):
            operation_id = self.planned(stream)
            self.store.outcome(operation_id, "acknowledged", 0.1)
            self.store.effect(operation_id, b"synthetic", settled=True)
        self.store.finish_run(self.run_id)
        result = self.store.evaluate(self.run_id, 1, 1)
        self.assertEqual(result["result"], "Passed")
        self.assertFalse(result["fault_actions_executed"])
        self.assertIn("reference", result["evidence_scope"])

    def test_payload_conflict_is_failed_even_with_successful_acks(self):
        operation_id = self.planned()
        self.store.outcome(operation_id, "acknowledged", 0.1)
        self.assertFalse(self.store.effect(operation_id, b"wrong"))
        self.assertEqual(self.store.evaluate(self.run_id, 0, 1)["result"], "Failed")

    def test_redelivery_creates_one_effect_before_settlement(self):
        operation_id = self.planned()
        self.store.effect(operation_id, b"synthetic")
        self.store.effect(operation_id, b"synthetic")
        operation = self.store.operations(self.run_id, "canary")[0]
        self.assertEqual(operation["effect_count"], 1)
        self.assertEqual(operation["delivery_attempts"], 2)
        self.assertEqual(operation["settled"], 0)
        self.store.settle(operation_id)
        self.assertEqual(self.store.operations(self.run_id, "canary")[0]["settled"], 1)

    def test_unconfirmed_settlement_cannot_pass_service_bus(self):
        self.store.start_run("b" * 32, "B-01", "baseline", 1, "servicebus")
        for stream in ("canary", "control"):
            operation_id = self.store.intent("b" * 32, stream, 0, b"synthetic")
            self.store.outcome(operation_id, "acknowledged", 0.1)
            self.store.effect(operation_id, b"synthetic")
        self.store.finish_run("b" * 32)
        self.assertEqual(self.store.evaluate("b" * 32, 1, 1)["result"], "Inconclusive")

    def test_duplicate_sequence_cannot_create_second_logical_operation(self):
        self.planned()
        with self.assertRaises(ledger.LedgerConflict):
            self.planned()
        self.assertEqual(len(self.store.operations(self.run_id, "canary")), 1)

    def test_unknown_message_is_rejected_without_creating_an_effect(self):
        with self.assertRaises(ledger.LedgerConflict):
            self.store.effect("f" * 32, b"synthetic")

    def test_run_identity_is_not_reused_for_new_traffic(self):
        with self.assertRaises(ledger.LedgerConflict):
            self.store.start_run(self.run_id, "S-01", "baseline", 1, "blob")

    def test_late_acknowledgments_are_not_successful_deadline_work(self):
        for stream in ("canary", "control"):
            operation_id = self.planned(stream)
            self.store.outcome(operation_id, "acknowledged", 2)
            self.store.effect(operation_id, b"synthetic", settled=True)
        self.store.finish_run(self.run_id)
        self.assertEqual(self.store.evaluate(self.run_id, 1, 1)["result"], "Failed")

    def test_read_only_reconciliation_cannot_initialize_or_modify_a_ledger(self):
        with self.assertRaises(OSError):
            ledger.Ledger(Path(self.directory.name) / "missing.sqlite", read_only=True)
        self.store.close()
        self.store = ledger.Ledger(self.path, read_only=True)
        with self.assertRaises(ledger.LedgerConflict):
            self.store.finish_run(self.run_id)


if __name__ == "__main__":
    unittest.main()
