import contextlib
import importlib.util
import io
import json
from pathlib import Path
import threading
import unittest
from unittest.mock import MagicMock, patch
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location("probe", Path(__file__).resolve().parents[1] / "probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def test_p95_uses_nearest_rank_at_exact_boundary(self):
        times = [0] + [value for duration in range(1, 21) for value in (0, duration)]
        with patch.object(probe.urllib.request, "build_opener"), \
                patch.object(probe.time, "monotonic", side_effect=times), \
                contextlib.redirect_stdout(io.StringIO()):
            result = probe.measure("https://example.invalid", 20, 1)
        self.assertEqual(result["p95_seconds"], 19)

    def test_failure_changes_success_rate_without_leaking_url(self):
        opener = MagicMock()
        opener.open.side_effect = [MagicMock(), urllib.error.URLError("https://private.invalid/secret")]
        output = io.StringIO()
        with patch.object(probe.urllib.request, "build_opener", return_value=opener), contextlib.redirect_stdout(output):
            result = probe.measure("https://private.invalid/secret", 2, 1)
        self.assertEqual(result["success_rate"], 0.5)
        self.assertEqual(result["failures"], 1)
        self.assertNotIn("private.invalid", output.getvalue())

    def test_redirects_rejected_before_unapproved_request(self):
        for destination in ["http://example.invalid", "https://other.invalid"]:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                probe.NoRedirect().redirect_request(
                    urllib.request.Request("https://example.invalid"), None, 302, "Found", {}, destination
                )
            caught.exception.close()

    def test_threshold_failure_is_nonzero_and_report_is_scoped(self):
        flow = {"canary_url": "https://canary.invalid", "control_url": "https://control.invalid",
                "operations": 2, "request_timeout": 1, "minimum_success": 0.99}
        output = io.StringIO()
        with patch.dict(probe.os.environ, {"FLOW": json.dumps(flow)}), \
                patch.object(probe, "measure", side_effect=[{"success_rate": 1}, {"success_rate": 0.5}]), \
                contextlib.redirect_stdout(output):
            exit_code = probe.main()
        report = json.loads(output.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertEqual(report["result"], "Failed")
        self.assertIn("HTTPS availability only", report["evidence_scope"])

    def test_control_and_canary_are_measured_concurrently(self):
        both_started = threading.Barrier(2)
        flow = {"canary_url": "https://canary.invalid", "control_url": "https://control.invalid",
                "operations": 2, "request_timeout": 1, "minimum_success": 0.99}

        def measured(*args):
            both_started.wait(timeout=2)
            return {"success_rate": 1}

        with patch.dict(probe.os.environ, {"FLOW": json.dumps(flow)}), \
                patch.object(probe, "measure", side_effect=measured), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(probe.main(), 0)

    def test_successful_but_slow_requests_fail_latency_gate(self):
        flow = {"canary_url": "https://canary.invalid", "control_url": "https://control.invalid",
                "operations": 2, "request_timeout": 1, "minimum_success": 0.99,
                "maximum_p95_seconds": 0.5, "maximum_p99_seconds": 1}
        for p95, p99 in [(0.8, 0.9), (0.4, 1.1)]:
            with self.subTest(p95=p95, p99=p99):
                output = io.StringIO()
                with patch.dict(probe.os.environ, {"FLOW": json.dumps(flow)}), \
                        patch.object(probe, "measure", return_value={"success_rate": 1, "p95_seconds": p95, "p99_seconds": p99}), \
                        contextlib.redirect_stdout(output):
                    self.assertEqual(probe.main(), 1)
                self.assertEqual(json.loads(output.getvalue())["result"], "Failed")

    def test_short_observation_is_inconclusive_not_passed(self):
        flow = {"canary_url": "https://canary.invalid", "control_url": "https://control.invalid",
                "operations": 2, "request_timeout": 1, "minimum_success": 0.99,
                "phase": "recovery", "minimum_observation_seconds": 600}
        output = io.StringIO()
        with patch.dict(probe.os.environ, {"FLOW": json.dumps(flow)}), \
                patch.object(probe, "measure", return_value={"success_rate": 1, "elapsed_seconds": 2}), \
                contextlib.redirect_stdout(output):
            self.assertEqual(probe.main(), 2)
        self.assertEqual(json.loads(output.getvalue())["result"], "Inconclusive")

    def test_interval_sampling_and_timing_evidence(self):
        with patch.object(probe.urllib.request, "build_opener"), \
                patch.object(probe.time, "monotonic", side_effect=[0, 0, 0.1, 1, 1.1]), \
                patch.object(probe.time, "sleep") as sleep:
            result = probe.measure("https://example.invalid", 2, 1, 1)
        sleep.assert_called_once_with(0.9)
        self.assertEqual(result["elapsed_seconds"], 1.1)
        self.assertEqual(len(result["samples"]), 2)
        self.assertAlmostEqual(result["p99_seconds"], 0.1)

    def test_response_after_request_deadline_is_not_false_success(self):
        output = io.StringIO()
        with patch.object(probe.urllib.request, "build_opener"), \
                patch.object(probe.time, "monotonic", side_effect=[0, 0, 2]), \
                contextlib.redirect_stdout(output):
            result = probe.measure("https://example.invalid", 1, 1)
        self.assertEqual(result["failures"], 1)
        self.assertFalse(result["samples"][0]["success"])
        self.assertIn("RequestDeadlineExceeded", output.getvalue())


if __name__ == "__main__":
    unittest.main()
