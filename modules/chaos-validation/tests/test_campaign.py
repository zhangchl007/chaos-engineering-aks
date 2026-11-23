from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import sys
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location("campaign", Path(__file__).resolve().parents[1] / "campaign.py")
campaign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(campaign)


def manifest():
    now = datetime.now(timezone.utc)
    subscription = "00000000-0000-0000-0000-000000000001"
    prefix = f"/subscriptions/{subscription}/resourceGroups/fixture/providers/Microsoft.Storage/storageAccounts/"
    return {
        "campaign_id": "b" * 32, "case_id": "S-01", "environment": "test",
        "subscription_id": subscription, "tenant_id": "00000000-0000-0000-0000-000000000002",
        "owner": "test-operator",
        "targets": [{"resource_id": prefix + name, "role": role, "test_owned": True}
                    for name, role in (("canary", "canary"), ("control", "control"))],
        "fault_target_ids": [prefix + "canary"],
        "ledger": {"path": "/evidence/operations.sqlite", "durability_qualified": True, "outside_fault_scope": True},
        "criteria": {"baseline_seconds": 900, "baseline_operations": 1000, "minimum_success": 0.999,
                     "request_deadline_seconds": 1, "maximum_p95_seconds": 0.5,
                     "rto_seconds": 120, "rpo_operations": 0, "recovery_window_seconds": 60,
                     "recovery_windows": 10, "recovery_minimum_operations": 1},
        "stop_policy": {"streams": ["control"], "window_operations": 60, "minimum_success": 0.99,
                        "maximum_silence_seconds": 15, "maximum_monitor_seconds": 1200},
        "authorizations": {"traffic": True, "fault": True, "recovery": True, "expanded_scope": False},
        "qualification": {"support": True, "permissions": True, "resolved_targets": True,
                          "monitor_handoff": True, "recovery_access": True},
        "recovery": {"owner": "test-operator", "steps": ["Remove only approved test effects and reconcile IDs."]},
        "window": {"start_at": (now - timedelta(minutes=1)).isoformat(),
                   "end_at": (now + timedelta(hours=1)).isoformat(),
                   "maximum_run_seconds": 1200, "cost_ceiling": 1},
    }


def records():
    identity = {"schema_version": 1, "observation_id": "a" * 32, "phase": "recovery"}
    samples = [{**identity, "event": "observation_started", "streams": ["canary", "control"], "operations": 10}]
    for stream in ("canary", "control"):
        samples.extend({**identity, "event": "measurement", "stream": stream, "sequence": i,
                        "elapsed_seconds": i * 60, "latency_seconds": 0.1, "success": True} for i in range(10))
    return samples + [{**identity, "event": "observation_completed", "result": "Passed", "elapsed_seconds": 600}]


class CampaignTests(unittest.TestCase):
    def test_new_catalog_cases_are_parseable_but_not_cloud_qualified(self):
        for case_id in ("V-03", "V-10", "N-07", "H-06", "K-06", "I-01", "L-03", "G-03"):
            with self.subTest(case_id=case_id):
                value = manifest()
                value["case_id"] = case_id
                value["qualification"]["support"] = False
                self.assertEqual(campaign.validate_manifest(value), value)
                self.assertIn("support", campaign.readiness_gaps(value))

    def test_undefined_extended_cases_are_rejected(self):
        for case_id in ("V-11", "N-08", "X-01"):
            value = manifest()
            value["case_id"] = case_id
            with self.assertRaises(ValueError):
                campaign.validate_manifest(value)

    def test_manifest_structure_is_not_cloud_readiness_or_case_pass(self):
        value = manifest()
        value["qualification"]["support"] = False
        self.assertEqual(campaign.validate_manifest(value), value)
        self.assertIn("support", campaign.readiness_gaps(value))

    def test_subscription_scope_control_and_non_owned_targets_are_rejected(self):
        for mutate in (
            lambda value: value.update(environment="production"),
            lambda value: value["targets"][0].update(test_owned=False),
            lambda value: value.update(fault_target_ids=[value["targets"][1]["resource_id"]]),
            lambda value: value["targets"][0].update(resource_id="/subscriptions/" + "0" * 36),
            lambda value: value["targets"][0].update(resource_id=value["targets"][0]["resource_id"] + "/*"),
        ):
            value = manifest()
            mutate(value)
            with self.assertRaises(ValueError):
                campaign.validate_manifest(value)

    def test_unknown_fields_and_string_authorizations_are_rejected(self):
        for mutate in (
            lambda value: value.update(secret="not-accepted"),
            lambda value: value["authorizations"].update(traffic="true"),
            lambda value: value["criteria"].update(minimum_success=float("nan")),
        ):
            value = manifest()
            mutate(value)
            with self.assertRaises(ValueError):
                campaign.validate_manifest(value)

    def test_traffic_requires_matching_case_targets_ledger_and_baseline_contract(self):
        from test_business import configuration
        value = manifest()
        config = configuration()
        for change in (
            lambda flow: flow.update(case_id="B-01"),
            lambda flow: flow["streams"]["canary"].update(resource_id=value["targets"][1]["resource_id"]),
        ):
            flow = json.loads(json.dumps(config))
            change(flow)
            with self.assertRaises(ValueError):
                campaign.authorize_traffic(value, flow, value["ledger"]["path"])
        with self.assertRaises(ValueError):
            campaign.authorize_traffic(value, config, "/temporary/ledger.sqlite")
        with self.assertRaises(ValueError):
            campaign.authorize_traffic(value, config, value["ledger"]["path"])

    def test_expired_window_and_unqualified_durability_block_traffic(self):
        value = manifest()
        value["window"]["end_at"] = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()
        self.assertIn("maintenance_window", campaign.readiness_gaps(value))
        value = manifest()
        value["ledger"]["durability_qualified"] = False
        self.assertIn("ledger_durability", campaign.readiness_gaps(value))

    def test_real_window_minimums_not_aggregate_percentile_determine_recovery(self):
        evidence = records()
        for record in evidence:
            if record["event"] == "measurement":
                record["elapsed_seconds"] = record["sequence"] * 0.01
        result = campaign.assess_recovery(evidence, manifest()["criteria"])
        self.assertEqual(result["result"], "Inconclusive")

    def test_ten_complete_windows_pass_only_availability_recovery_scope(self):
        result = campaign.assess_recovery(records(), manifest()["criteria"])
        self.assertEqual(result["result"], "Passed")
        self.assertFalse(result["case_certified"])
        self.assertFalse(result["fault_actions_executed"])

    def test_one_bad_recovery_window_is_failed_even_if_aggregate_is_healthy(self):
        evidence = records()
        evidence[5]["success"] = False
        self.assertEqual(campaign.assess_recovery(evidence, manifest()["criteria"])["result"], "Failed")

    def test_missing_completion_and_missing_stream_are_inconclusive(self):
        for evidence in (records()[:-1], [record for record in records() if record.get("stream") != "control"]):
            self.assertEqual(campaign.assess_recovery(evidence, manifest()["criteria"])["result"], "Inconclusive")

    def test_duplicate_sequence_or_mixed_observation_is_invalid(self):
        for mutate in (
            lambda evidence: evidence[2].update(sequence=0),
            lambda evidence: evidence[2].update(observation_id="c" * 32),
            lambda evidence: evidence[2].update(latency_seconds=float("nan")),
        ):
            evidence = records()
            mutate(evidence)
            with self.assertRaises(ValueError):
                campaign.assess_recovery(evidence, manifest()["criteria"])


if __name__ == "__main__":
    unittest.main()
