import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("stop", Path(__file__).resolve().parents[1] / "stop.py")
stop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stop)


POLICY = {
    "window_operations": 2,
    "minimum_success": 1,
    "maximum_silence_seconds": 1,
    "maximum_monitor_seconds": 5,
}
IDENTITY = {"schema_version": 1, "observation_id": "a" * 32, "phase": "exposure"}


def start(operations=2):
    return {**IDENTITY, "event": "observation_started",
            "streams": ["control", "canary"], "operations": operations}


def sample(sequence, stream="control", success=True, latency=0.1):
    return {**IDENTITY, "event": "measurement", "stream": stream, "sequence": sequence,
            "success": success, "latency_seconds": latency, "elapsed_seconds": sequence}


def completed():
    return {**IDENTITY, "event": "observation_completed", "result": "Passed"}


class StopTests(unittest.TestCase):
    def test_complete_healthy_windows_are_only_an_availability_signal(self):
        evaluator = stop.Evaluator(POLICY)
        for record in [start(), sample(0), sample(0, "canary"), sample(1), sample(1, "canary"), completed()]:
            self.assertIsNone(evaluator.feed(record))
        report = evaluator.finish()
        self.assertEqual(report["result"], "Passed")
        self.assertFalse(report["stop_recommended"])
        self.assertFalse(report["fault_actions_executed"])
        self.assertIn("not cancellation", report["evidence_scope"])
        self.assertIn("explanation_zh", report)

    def test_breach_is_reported_before_observation_completion(self):
        evaluator = stop.Evaluator(POLICY)
        evaluator.feed(start())
        evaluator.feed(sample(0))
        report = evaluator.feed(sample(1, success=False))
        self.assertEqual(report["result"], "Failed")
        self.assertEqual(report["reason"], "success_rate")
        self.assertTrue(report["stop_recommended"])

    def test_expected_canary_failure_does_not_abort_a_control_only_policy(self):
        evaluator = stop.Evaluator(POLICY)
        for record in [start(), sample(0), sample(0, "canary", success=False),
                       sample(1), sample(1, "canary", success=False),
                       {**completed(), "result": "Failed"}]:
            self.assertIsNone(evaluator.feed(record))
        self.assertEqual(evaluator.finish()["result"], "Passed")

    def test_insufficient_observation_duration_is_not_passed(self):
        evaluator = stop.Evaluator(POLICY)
        for record in [start(), sample(0), sample(0, "canary"), sample(1), sample(1, "canary"),
                       {**completed(), "result": "Inconclusive"}]:
            evaluator.feed(record)
        self.assertEqual(evaluator.finish()["result"], "Inconclusive")

    def test_consecutive_failure_can_stop_before_a_full_window(self):
        evaluator = stop.Evaluator({**POLICY, "stop_after_consecutive_failures": 1})
        evaluator.feed(start())
        report = evaluator.feed(sample(0, success=False))
        self.assertEqual(report["reason"], "consecutive_failures")

    def test_latency_limit_is_inclusive_and_excess_stops(self):
        for latency, expected in [(0.5, None), (0.51, "p95_seconds")]:
            evaluator = stop.Evaluator({**POLICY, "maximum_p95_seconds": 0.5})
            evaluator.feed(start())
            evaluator.feed(sample(0, latency=latency))
            report = evaluator.feed(sample(1, latency=latency))
            self.assertEqual(None if report is None else report["reason"], expected)

    def test_missing_or_short_evidence_is_not_passed(self):
        for records in [[], [start()], [start(), sample(0), completed()]]:
            evaluator = stop.Evaluator(POLICY)
            for record in records:
                evaluator.feed(record)
            self.assertEqual(evaluator.finish()["result"], "Inconclusive")

    def test_corrupt_or_mixed_measurements_are_rejected(self):
        for record in [sample(1), {**sample(0), "success": 1},
                       {**sample(0), "latency_seconds": float("nan")},
                       {**sample(0), "observation_id": "b" * 32}]:
            with self.subTest(record=record):
                evaluator = stop.Evaluator(POLICY)
                evaluator.feed(start())
                with self.assertRaises(ValueError):
                    evaluator.feed(record)

    def test_invalid_policy_cannot_be_a_successful_default(self):
        for changes in [{"minimum_success": 0}, {"window_operations": True},
                        {"maximum_silence_seconds": float("nan")}, {"streams": []},
                        {"maximum_monitor_seconds": 4000}, {"maximum_monitor_seconds": 10 ** 400},
                        {"unexpected": 1}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                stop.Evaluator({**POLICY, **changes})

    def test_canary_messages_do_not_hide_silent_control(self):
        clock = [0]
        chunks = [json.dumps(start()).encode() + b"\n",
                  json.dumps(sample(0, "canary")).encode() + b"\n"]

        def ready(*args):
            if chunks:
                clock[0] = 0 if len(chunks) == 2 else 0.04
                return [123], [], []
            clock[0] = 0.06
            return [], [], []

        with patch.object(stop.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(stop.select, "select", side_effect=ready), \
                patch.object(stop.os, "read", side_effect=lambda *args: chunks.pop(0)):
            report = stop.monitor(123, {**POLICY, "maximum_silence_seconds": 0.05})
        self.assertEqual(report["result"], "Inconclusive")
        self.assertEqual(report["reason"], "evidence_silence")

    def test_monitor_has_a_finite_budget(self):
        clock = [0]

        def timeout(*args):
            clock[0] = 0.06
            return [], [], []

        with patch.object(stop.time, "monotonic", side_effect=lambda: clock[0]), \
                patch.object(stop.select, "select", side_effect=timeout):
            report = stop.monitor(123, {**POLICY, "maximum_silence_seconds": 0.05,
                                       "maximum_monitor_seconds": 0.05})
        self.assertEqual(report["reason"], "monitor_deadline")
        self.assertTrue(report["stop_recommended"])

    def test_live_cli_detects_silence_without_waiting_for_eof(self):
        process = subprocess.Popen(
            [sys.executable, str(Path(stop.__file__))],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            env={**os.environ, "STOP_POLICY": json.dumps({**POLICY, "maximum_silence_seconds": 0.05})},
        )
        try:
            process.wait(timeout=2)
            output, errors = process.communicate()
            self.assertEqual(process.returncode, 2, errors)
            self.assertEqual(json.loads(output)["reason"], "evidence_silence")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_cli_healthy_and_invalid_evidence_have_explicit_exit_codes(self):
        records = [start(), sample(0), sample(0, "canary"), sample(1), sample(1, "canary"), completed()]
        cases = [("\n".join(json.dumps(r) for r in records) + "\n", 0, "Passed"),
                 ("private-token-is-not-json\n", 3, "Blocked"), ("", 2, "Inconclusive")]
        for evidence, code, result in cases:
            with self.subTest(result=result):
                process = subprocess.run(
                    [sys.executable, str(Path(stop.__file__))], input=evidence,
                    capture_output=True, text=True, timeout=2,
                    env={**os.environ, "STOP_POLICY": json.dumps(POLICY)},
                )
                self.assertEqual(process.returncode, code, process.stderr)
                report = json.loads(process.stdout)
                self.assertEqual(report["result"], result)
                self.assertNotIn("private-token", process.stdout)
