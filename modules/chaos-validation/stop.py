from collections import deque
import json
import math
import os
import re
import select
import sys
import time


class IncompleteEvidence(ValueError):
    pass


def report(result, reason, **details):
    return {
        "result": result,
        "reason": reason,
        "stop_recommended": result != "Passed",
        "fault_actions_executed": False,
        "evidence_scope": "Availability stop signal only; not cancellation, recovery or data integrity",
        "explanation_zh": {
            "Passed": "完整可用性窗口满足停止策略；不代表业务韧性或数据完整性通过。",
            "Failed": "达到停止阈值或监测期限；操作员应停止或升级处理，脚本不执行故障操作。",
            "Inconclusive": "证据不完整或窗口不足；应停止或升级处理，不能判定通过。",
            "Blocked": "策略或证据无效；应停止或升级处理，不能判定通过。",
        }[result],
        **details,
    }


def finite_number(value):
    return (type(value) is int and value >= 0) or (type(value) is float and math.isfinite(value) and value >= 0)


def validate_policy(policy):
    required = {"window_operations", "minimum_success", "maximum_silence_seconds", "maximum_monitor_seconds"}
    optional = {"streams", "maximum_p95_seconds", "maximum_p99_seconds", "stop_after_consecutive_failures"}
    if not isinstance(policy, dict) or not required <= policy.keys() or policy.keys() - required - optional:
        raise ValueError("Invalid policy fields.")
    streams = policy.get("streams", ["control"])
    if (not isinstance(streams, list) or not streams or
            any(stream not in ("control", "canary") for stream in streams) or len(set(streams)) != len(streams)):
        raise ValueError("Invalid monitored streams.")
    window = policy["window_operations"]
    if type(window) is not int or not 1 <= window <= 1000:
        raise ValueError("Invalid observation window.")
    if not finite_number(policy["minimum_success"]) or not 0 < policy["minimum_success"] <= 1:
        raise ValueError("Invalid success threshold.")
    silence, duration = policy["maximum_silence_seconds"], policy["maximum_monitor_seconds"]
    if not finite_number(silence) or not finite_number(duration) or not 0 < silence <= duration <= 3600:
        raise ValueError("Invalid monitoring budget.")
    for key in ("maximum_p95_seconds", "maximum_p99_seconds"):
        value = policy.get(key)
        if value is not None and (not finite_number(value) or value <= 0):
            raise ValueError("Invalid latency threshold.")
    consecutive = policy.get("stop_after_consecutive_failures")
    if consecutive is not None and (type(consecutive) is not int or not 1 <= consecutive <= 1000):
        raise ValueError("Invalid consecutive-failure threshold.")
    return {**policy, "streams": streams}


class Evaluator:
    def __init__(self, policy):
        self.policy = validate_policy(policy)
        self.identity = None
        self.operations = 0
        self.counts = {}
        self.last_elapsed = {}
        self.windows = {stream: deque(maxlen=self.policy["window_operations"]) for stream in self.policy["streams"]}
        self.consecutive = {stream: 0 for stream in self.policy["streams"]}
        self.completed = False
        self.observation_result = None

    def feed(self, record):
        if not isinstance(record, dict) or self.completed:
            raise ValueError("Invalid evidence record.")
        event = record.get("event")
        if event == "request_failed":
            return None
        if event not in ("observation_started", "measurement", "observation_completed"):
            raise ValueError("Unknown evidence event.")
        identity = {key: record.get(key) for key in ("schema_version", "observation_id", "phase")}
        if (type(identity["schema_version"]) is not int or identity["schema_version"] != 1 or
                not isinstance(identity["observation_id"], str) or
                not re.fullmatch("[a-f0-9]{32}", identity["observation_id"]) or
                identity["phase"] not in ("baseline", "exposure", "recovery")):
            raise ValueError("Invalid evidence identity.")
        if event == "observation_started":
            if self.identity is not None:
                raise ValueError("Multiple observations must not be combined.")
            streams, operations = record.get("streams"), record.get("operations")
            if (not isinstance(streams, list) or not streams or
                    any(stream not in ("control", "canary") for stream in streams) or
                    len(set(streams)) != len(streams) or not set(self.policy["streams"]) <= set(streams) or
                    type(operations) is not int or not 1 <= operations <= 1000):
                raise ValueError("Invalid observation declaration.")
            self.identity, self.operations = identity, operations
            self.counts = {stream: 0 for stream in streams}
            self.last_elapsed = {stream: 0 for stream in streams}
            return None
        if self.identity is None:
            raise IncompleteEvidence("Start evidence is missing.")
        if identity != self.identity:
            raise ValueError("Mixed observations or phases.")
        if event == "observation_completed":
            if record.get("result") not in ("Passed", "Failed", "Inconclusive"):
                raise ValueError("Invalid observation result.")
            self.completed = True
            self.observation_result = record["result"]
            return None
        stream = record.get("stream")
        if not isinstance(stream, str) or stream not in self.counts:
            raise ValueError("Unexpected measurement stream.")
        sequence = record.get("sequence")
        if type(sequence) is not int or not 0 <= sequence < self.operations:
            raise ValueError("Invalid sample sequence.")
        if sequence != self.counts[stream]:
            raise IncompleteEvidence("Sample evidence is missing or repeated.")
        latency, elapsed, success = record.get("latency_seconds"), record.get("elapsed_seconds"), record.get("success")
        if (not finite_number(latency) or not finite_number(elapsed) or
                elapsed < self.last_elapsed[stream] or type(success) is not bool):
            raise ValueError("Invalid sample values.")
        self.counts[stream] += 1
        self.last_elapsed[stream] = elapsed
        if stream not in self.windows:
            return None
        self.windows[stream].append((success, latency))
        self.consecutive[stream] = 0 if success else self.consecutive[stream] + 1
        limit = self.policy.get("stop_after_consecutive_failures")
        if limit is not None and self.consecutive[stream] >= limit:
            return report("Failed", "consecutive_failures", **self.identity, stream=stream, sequence=sequence)
        window = self.windows[stream]
        if len(window) < self.policy["window_operations"]:
            return None
        latencies = sorted(latency for _, latency in window)
        metrics = {
            "operations": len(window),
            "success_rate": sum(success for success, _ in window) / len(window),
            "p95_seconds": latencies[math.ceil(len(window) * 0.95) - 1],
            "p99_seconds": latencies[math.ceil(len(window) * 0.99) - 1],
        }
        if metrics["success_rate"] < self.policy["minimum_success"]:
            return report("Failed", "success_rate", **self.identity, stream=stream, sequence=sequence, metrics=metrics)
        for name in ("p95", "p99"):
            maximum = self.policy.get("maximum_" + name + "_seconds")
            if maximum is not None and metrics[name + "_seconds"] > maximum:
                return report("Failed", name + "_seconds", **self.identity, stream=stream, sequence=sequence, metrics=metrics)
        return None

    def finish(self):
        if (not self.completed or self.observation_result == "Inconclusive" or
                any(count != self.operations for count in self.counts.values()) or
                any(len(window) < self.policy["window_operations"] for window in self.windows.values())):
            return report("Inconclusive", "incomplete_observation")
        return report("Passed", "monitored_windows_healthy", **self.identity)


def monitor(fd, policy):
    evaluator = Evaluator(policy)
    started = time.monotonic()
    last_seen = {stream: started for stream in evaluator.policy["streams"]}
    buffer = b""
    while True:
        now = time.monotonic()
        remaining = evaluator.policy["maximum_monitor_seconds"] - (now - started)
        silence = evaluator.policy["maximum_silence_seconds"] - (now - min(last_seen.values()))
        if remaining <= 0:
            return report("Failed", "monitor_deadline", **(evaluator.identity or {}))
        if silence <= 0:
            return report("Inconclusive", "evidence_silence", **(evaluator.identity or {}),
                          stream=min(last_seen, key=lambda stream: last_seen[stream]))
        try:
            readable, _, _ = select.select([fd], [], [], min(remaining, silence))
            if not readable:
                continue
            chunk = os.read(fd, 8192)
            buffer += chunk
            lines = buffer.split(b"\n")
            buffer = lines.pop()
            if not chunk and buffer:
                lines.append(buffer)
                buffer = b""
            if len(buffer) > 65536:
                return report("Blocked", "oversized_evidence")
            for line in lines:
                if len(line) > 65536:
                    return report("Blocked", "oversized_evidence")
                record = json.loads(line)
                signal = evaluator.feed(record)
                if signal is not None:
                    return signal
                if record.get("event") == "observation_started":
                    last_seen = {stream: time.monotonic() for stream in last_seen}
                elif record.get("event") == "measurement" and record.get("stream") in last_seen:
                    last_seen[record["stream"]] = time.monotonic()
                if evaluator.completed:
                    return evaluator.finish()
            if not chunk:
                return evaluator.finish()
        except IncompleteEvidence:
            return report("Inconclusive", "missing_measurements")
        except (ValueError, OSError):
            return report("Blocked", "invalid_or_unreadable_evidence")


def main():
    try:
        policy = json.loads(os.environ["STOP_POLICY"])
        result = monitor(sys.stdin.fileno(), policy)
    except (KeyError, ValueError, OSError):
        result = report("Blocked", "invalid_policy_or_input")
    print(json.dumps(result), flush=True)
    return {"Passed": 0, "Failed": 1, "Inconclusive": 2, "Blocked": 3}[result["result"]]


if __name__ == "__main__":
    sys.exit(main())
