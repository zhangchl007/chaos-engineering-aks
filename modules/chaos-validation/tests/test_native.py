import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from urllib.error import URLError


DIRECTORY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("run_native_case", DIRECTORY / "run_native_case.py")
native = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = native
spec.loader.exec_module(native)
spec = importlib.util.spec_from_file_location("observe_native_run", DIRECTORY / "observe_native_run.py")
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)
spec = importlib.util.spec_from_file_location("summarize_native_runs", DIRECTORY / "summarize_native_runs.py")
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)

GROUP = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test"
WORKSPACE = GROUP + "/providers/Microsoft.Chaos/workspaces/test"
TARGET = GROUP + "/providers/Microsoft.ServiceBus/namespaces/test"
CASE = "b01-servicebus-send-disabled"
DEFINITION = {
    "action_id": "microsoft-servicebus-changequeuestate/1.0",
    "target_ids": [TARGET], "duration_minutes": 1,
    "parameters": {"queues": '["test"]', "desiredState": "SendDisabled"},
}
VARIABLES = {
    "enabled": True, "subscription_id": GROUP.split("/")[2], "tenant_id": "test",
    "resource_group_id": GROUP, "name": "test", "excluded_resource_ids": ["excluded"],
    "scenarios": {CASE: DEFINITION}, "permissions": {"service_bus": {"target_id": TARGET}},
}


def binding():
    scenario = {"properties": {"actions": [{
        "actionId": DEFINITION["action_id"], "duration": "PT1M",
        "parameters": [{"key": key, "value": value} for key, value in DEFINITION["parameters"].items()],
    }]}}
    configuration = {"properties": {
        "scenarioId": CASE, "provisioningState": "Succeeded", "parameters": [],
        "resourceTargeting": {
            "include": {"resources": [TARGET]},
            "exclude": {"resources": ["excluded"], "tags": [
                {"key": "environment", "value": "prod"},
                {"key": "environment", "value": "production"},
                {"key": "chaos-excluded", "value": "true"},
            ]},
        },
    }}
    return scenario, configuration


class NativeTests(unittest.TestCase):
    def client(self):
        client = native.Client.__new__(native.Client)
        client.token = "test-token"
        return client

    def test_get_retries_are_bounded_but_execute_is_never_retried(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status, response.headers = 200, {}
        response.read.return_value = b'{"ok":true}'
        for method, errors, expected in [
            ("GET", [URLError("timeout"), response], 2),
            ("GET", [URLError("timeout")] * 3, 3),
            ("POST", [URLError("timeout")], 1),
        ]:
            with self.subTest(method=method, attempts=expected):
                opener = MagicMock()
                opener.open.side_effect = errors
                with patch.object(native.urllib.request, "build_opener", return_value=opener), patch.object(native.time, "sleep"):
                    if errors[-1] is response:
                        self.assertEqual(self.client().request("/test", method)[2], {"ok": True})
                    else:
                        with self.assertRaises(URLError):
                            self.client().request("/test", method)
                self.assertEqual(opener.open.call_count, expected)

    def test_token_transport_rejects_other_origins_http_and_redirects(self):
        with patch.object(native.urllib.request, "build_opener") as opener:
            for url in ("http://management.azure.com/test", "https://other.example/test"):
                with self.assertRaises(ValueError):
                    self.client().request(url)
            opener.assert_not_called()
        with self.assertRaises(ValueError):
            native.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.example/")

    def test_action_target_zone_and_exclusion_drift_are_rejected(self):
        scenario, configuration = binding()
        native.check_binding(MagicMock(get=MagicMock(side_effect=[scenario, configuration])),
                             VARIABLES, WORKSPACE, CASE)
        for change in ("action", "parameters", "target", "zone", "exclusion", "tag", "parent"):
            with self.subTest(change=change):
                scenario, configuration = binding()
                properties = configuration["properties"]
                if change == "action":
                    scenario["properties"]["actions"][0]["actionId"] = "other/1.0"
                elif change == "parameters":
                    scenario["properties"]["actions"][0]["parameters"] = []
                elif change == "target":
                    properties["resourceTargeting"]["include"]["resources"] = ["other"]
                elif change == "zone":
                    properties["resourceTargeting"]["include"]["zones"] = ["2"]
                elif change == "exclusion":
                    properties["resourceTargeting"]["exclude"]["resources"] = []
                elif change == "tag":
                    properties["resourceTargeting"]["exclude"]["tags"] = []
                else:
                    properties["scenarioId"] = "other"
                with self.assertRaises(ValueError):
                    native.check_binding(MagicMock(get=MagicMock(side_effect=[scenario, configuration])),
                                         VARIABLES, WORKSPACE, CASE)

    def test_journal_creation_never_overwrites_an_existing_execute_intent(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.private.json"
            native.create_journal(path, {"execution_attempted": True})
            original = path.read_bytes()
            with self.assertRaises(FileExistsError):
                native.create_journal(path, {"execution_attempted": False})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_offline_inputs_reject_placeholders_and_expanded_target_maps(self):
        for change in (None, "placeholder", "targets", "alternate_state"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                variables = copy.deepcopy(VARIABLES)
                if change == "placeholder":
                    variables["tenant_id"] = "<tenant-id>"
                elif change == "targets":
                    variables["scenarios"][CASE]["target_ids"].append("other")
                elif change == "alternate_state":
                    variables["scenarios"][CASE]["parameters"]["desiredState"] = "ReceiveDisabled"
                path = Path(directory)
                (path / "native-chaos.private.tfvars.json").write_text(json.dumps(variables))
                (path / "native-workspace-current.private.json").write_text(json.dumps({"id": WORKSPACE}))
                with patch.object(native, "az") as cli:
                    if change is None:
                        self.assertEqual(native.load_inputs(path)[1], WORKSPACE)
                    else:
                        with self.assertRaises(ValueError):
                            native.load_inputs(path)
                    cli.assert_not_called()

    def test_ready_entity_does_not_pass_until_resource_health_recovers(self):
        client = MagicMock()
        client.resource.return_value = {"properties": {"status": "Active"}}
        client.get.side_effect = [
            {"properties": {"availabilityState": "Unavailable"}},
            {"properties": {"availabilityState": "Available"}},
        ]
        record = {
            "case_id": "B-01", "samples": [{"resource": {"properties": {"status": "SendDisabled"}}}],
            "complete": False, "final_run": {"properties": {
                "status": "Succeeded", "scenarioRunSummary": [
                    {"state": "Succeeded", "resources": [{"id": TARGET}]},
                ],
            }},
        }
        with patch.object(native.time, "sleep"):
            native.finish_run(client, record, TARGET, TARGET + "/queues/test",
                              "service_bus", "test", "SendDisabled", MagicMock())
        self.assertEqual([x["health"]["properties"]["availabilityState"]
                          for x in record["post_health_samples"]], ["Unavailable", "Available"])
        self.assertTrue(record["complete"])
        client.operation.assert_not_called()

    def test_skipped_action_is_not_success(self):
        client = MagicMock()
        record = {"final_run": {"properties": {
            "status": "Succeeded", "scenarioRunSummary": [{"state": "Skipped", "resources": [{"id": TARGET}]}],
        }}}
        with self.assertRaises(RuntimeError):
            native.finish_run(client, record, TARGET, TARGET + "/queues/test",
                              "service_bus", "test", "SendDisabled", MagicMock())
        client.resource.assert_not_called()

    def test_completed_observation_preserves_original_evidence_without_cloud_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "native-test-runs").mkdir()
            journal = path / "native-test-runs" / (CASE + ".private.json")
            journal.write_text('{"complete": true}')
            original = journal.read_bytes()
            with patch.object(observer, "load_inputs", return_value=(VARIABLES, WORKSPACE)), \
                    patch.object(observer, "Client") as client, \
                    patch.object(sys, "argv", ["observe_native_run.py", CASE, "--config-dir", directory]):
                observer.main()
            client.assert_not_called()
            self.assertEqual(journal.read_bytes(), original)

    def test_existing_execute_journal_is_rejected_before_any_cloud_call(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "native-test-runs").mkdir()
            (path / "native-test-runs" / (CASE + ".private.json")).write_text("{}")
            with patch.object(native, "load_inputs", return_value=(VARIABLES, WORKSPACE)), \
                    patch.object(native, "Client") as client, \
                    patch.object(sys, "argv", ["run_native_case.py", CASE, "--config-dir", directory, "--execute"]):
                with self.assertRaises(RuntimeError):
                    native.main()
            client.assert_not_called()

    def test_summary_does_not_turn_redis_no_effect_or_skipped_actions_into_passes(self):
        for action, effect, expected in [("Succeeded", False, "Inconclusive"),
                                         ("Skipped", True, "Inconclusive"),
                                         ("Succeeded", True, "Passed")]:
            record = {
                "scenario": CASE, "case_id": "B-01", "definition": DEFINITION,
                "complete": True, "effect_observed": effect,
                "post_health": {"properties": {"availabilityState": "Available"}},
                "restored": {"properties": {"status": "Active"}},
                "final_run": {"properties": {
                    "status": "Succeeded", "startTime": "2026-11-23T02:00:00+00:00",
                    "endTime": "2026-11-23T02:01:00+00:00",
                    "scenarioRunSummary": [{"state": action, "resources": [{"id": TARGET}]}],
                }},
            }
            with self.subTest(action=action, effect=effect), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "test.private.json"
                path.write_text(json.dumps(record))
                original = path.read_bytes()
                row = summary.summarize(path)
                self.assertEqual(row["management_result"], expected)
                self.assertEqual(row["infra_business_result"], "Inconclusive")
                self.assertEqual(row["run_seconds"], 60)
                self.assertNotIn(TARGET, json.dumps(row))
                self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
