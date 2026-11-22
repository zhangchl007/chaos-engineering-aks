import json
import math
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "Redirects are not approved targets", headers, fp)


def measure(url, operations, timeout, interval_seconds=0):
    latencies = []
    samples = []
    failures = 0
    context = ssl.create_default_context()
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context), NoRedirect())
    started_at = time.time()
    observation_started = time.monotonic()
    completed = observation_started
    for sequence in range(operations):
        delay = observation_started + sequence * interval_seconds - completed
        if delay > 0:
            time.sleep(delay)
        started = time.monotonic()
        success = True
        try:
            with opener.open(url, timeout=timeout) as response:
                response.read(1024)
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            success = False
            print(json.dumps({"event": "request_failed", "error_type": type(error).__name__}))
        completed = time.monotonic()
        latency = completed - started
        if success and latency > timeout:
            success = False
            print(json.dumps({"event": "request_failed", "error_type": "RequestDeadlineExceeded"}))
        failures += int(not success)
        latencies.append(latency)
        samples.append({
            "sequence": sequence,
            "elapsed_seconds": started - observation_started,
            "latency_seconds": latency,
            "success": success,
        })
    latencies.sort()
    return {
        "operations": operations,
        "failures": failures,
        "success_rate": (operations - failures) / operations,
        "p95_seconds": latencies[math.ceil(len(latencies) * 0.95) - 1],
        "p99_seconds": latencies[math.ceil(len(latencies) * 0.99) - 1],
        "started_at_unix_seconds": started_at,
        "elapsed_seconds": completed - observation_started,
        "samples": samples,
    }


def main():
    flow = json.loads(os.environ["FLOW"])
    with ThreadPoolExecutor(max_workers=2) as executor:
        pending = {
            name: executor.submit(measure, flow[name + "_url"], flow["operations"],
                                  flow["request_timeout"], flow.get("interval_seconds", 0))
            for name in ("control", "canary")
        }
        results = {name: future.result() for name, future in pending.items()}
    passed = all(
        result["success_rate"] >= flow["minimum_success"] and
        (flow.get("maximum_p95_seconds") is None or result["p95_seconds"] <= flow["maximum_p95_seconds"]) and
        (flow.get("maximum_p99_seconds") is None or result["p99_seconds"] <= flow["maximum_p99_seconds"])
        for result in results.values()
    )
    enough_observation = all(
        flow.get("minimum_observation_seconds", 0) == 0 or
        result["elapsed_seconds"] >= flow["minimum_observation_seconds"]
        for result in results.values()
    )
    verdict = "Failed" if not passed else "Passed" if enough_observation else "Inconclusive"
    print(json.dumps({
        "result": verdict,
        "phase": flow.get("phase", "baseline"),
        "evidence_scope": "HTTPS availability only; not data integrity or fault containment",
        "explanation_zh": (
            "可用性或延迟阈值未满足。" if not passed else
            "观察时长不足，不能判定通过。" if not enough_observation else
            "仅应用路径可用性检查通过；完整韧性仍需故障命中、数据对账和持续恢复证据。"
        ),
        "measurements": results,
    }))
    return 1 if not passed else 0 if enough_observation else 2


if __name__ == "__main__":
    sys.exit(main())
