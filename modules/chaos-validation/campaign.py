import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import sys

from stop import validate_policy


CASE_IDS = {f"{family}-{number:02d}" for family, count in
            {"C": 5, "M": 4, "P": 3, "R": 4, "A": 4, "S": 4, "B": 5,
             "E": 3, "H": 6, "D": 2, "K": 6, "N": 7, "V": 10,
             "I": 1, "L": 3, "G": 3}.items()
            for number in range(1, count + 1)}
GUID = r"[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
ARM_ID = (r"/subscriptions/(" + GUID + r")/resourceGroups/[^/*?#\s]+/providers/"
          r"[^/*?#\s]+/[^/*?#\s]+/[^/*?#\s]+(?:/[^/*?#\s]+/[^/*?#\s]+)*")


def load_json(path):
    path = Path(path)
    if path.stat().st_size > 65536:
        raise ValueError("Input exceeds the private configuration budget.")
    return json.loads(path.read_text())


def fields(value, expected):
    if not isinstance(value, dict) or value.keys() != set(expected):
        raise ValueError("Missing or unknown contract fields.")


def number(value, lower, upper, integer=False):
    if (type(value) not in ((int,) if integer else (int, float)) or
            not lower <= value <= upper or not math.isfinite(value)):
        raise ValueError("Invalid finite contract threshold.")


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("Explicit timezone-aware maintenance timestamps required.")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("Explicit timezone required.")
    return result


def validate_manifest(value):
    fields(value, ("campaign_id", "case_id", "environment", "subscription_id", "tenant_id", "owner",
                   "targets", "fault_target_ids", "ledger", "criteria", "stop_policy",
                   "authorizations", "qualification", "recovery", "window"))
    if (not isinstance(value["campaign_id"], str) or not re.fullmatch("[a-f0-9]{32}", value["campaign_id"]) or
            not isinstance(value["case_id"], str) or value["case_id"] not in CASE_IDS or
            value["environment"] not in ("dev", "test")):
        raise ValueError("Explicit non-production case and campaign identity required.")
    for key in ("subscription_id", "tenant_id"):
        if not isinstance(value[key], str) or not re.fullmatch(GUID, value[key]):
            raise ValueError("Explicit subscription and tenant required.")
    if not isinstance(value["owner"], str) or not value["owner"].strip():
        raise ValueError("Operator owner required.")
    targets = value["targets"]
    if not isinstance(targets, list) or not 2 <= len(targets) <= 12:
        raise ValueError("Bounded canary/control target list required.")
    roles = {}
    for target in targets:
        fields(target, ("resource_id", "role", "test_owned"))
        if not isinstance(target["resource_id"], str):
            raise ValueError("Exact resource ID required.")
        match = re.fullmatch(ARM_ID, target["resource_id"])
        if (not match or match.group(1) != value["subscription_id"] or
                target["role"] not in ("canary", "control", "ledger", "recovery") or
                target["test_owned"] is not True):
            raise ValueError("Only explicitly owned in-subscription resources may be selected.")
        key = target["resource_id"].lower()
        if key in roles:
            raise ValueError("Duplicate target ID.")
        roles[key] = target["role"]
    if list(roles.values()).count("canary") != 1 or list(roles.values()).count("control") != 1:
        raise ValueError("One independent canary/control resource pair required.")
    faults = value["fault_target_ids"]
    if (not isinstance(faults, list) or not faults or
            any(not isinstance(resource, str) or roles.get(resource.lower()) != "canary" for resource in faults) or
            len({resource.lower() for resource in faults}) != len(faults)):
        raise ValueError("Faults must exclude control, ledger and recovery resources.")
    fields(value["ledger"], ("path", "durability_qualified", "outside_fault_scope"))
    if not isinstance(value["ledger"]["path"], str) or not Path(value["ledger"]["path"]).is_absolute():
        raise ValueError("Explicit mounted durable ledger path required.")
    for key in ("durability_qualified", "outside_fault_scope"):
        if type(value["ledger"][key]) is not bool:
            raise ValueError("Ledger qualification must be explicit.")
    criteria = value["criteria"]
    fields(criteria, ("baseline_seconds", "baseline_operations", "minimum_success", "request_deadline_seconds",
                      "maximum_p95_seconds", "rto_seconds", "rpo_operations", "recovery_window_seconds",
                      "recovery_windows", "recovery_minimum_operations"))
    for key, lower, upper, integer in (
        ("baseline_seconds", 1, 3600, False), ("baseline_operations", 1, 1000, True),
        ("minimum_success", 0.001, 1, False), ("request_deadline_seconds", 0.1, 10, False),
        ("maximum_p95_seconds", 0.001, 10, False), ("rto_seconds", 1, 10800, False),
        ("rpo_operations", 0, 1000000, True), ("recovery_window_seconds", 1, 300, True),
        ("recovery_windows", 1, 60, True), ("recovery_minimum_operations", 1, 1000, True),
    ):
        number(criteria[key], lower, upper, integer)
    if (criteria["maximum_p95_seconds"] > criteria["request_deadline_seconds"] or
            criteria["recovery_window_seconds"] * criteria["recovery_windows"] > 3600):
        raise ValueError("Infeasible recovery/latency contract.")
    validate_policy(value["stop_policy"])
    for section, keys in (("authorizations", ("traffic", "fault", "recovery", "expanded_scope")),
                          ("qualification", ("support", "permissions", "resolved_targets",
                                             "monitor_handoff", "recovery_access"))):
        fields(value[section], keys)
        if any(type(flag) is not bool for flag in value[section].values()):
            raise ValueError("Authorization and qualification flags must be explicit booleans.")
    recovery = value["recovery"]
    fields(recovery, ("owner", "steps"))
    if (not isinstance(recovery["owner"], str) or not recovery["owner"].strip() or
            not isinstance(recovery["steps"], list) or not recovery["steps"] or
            any(not isinstance(step, str) or not step.strip() for step in recovery["steps"])):
        raise ValueError("Recovery owner and actual steps required.")
    window = value["window"]
    fields(window, ("start_at", "end_at", "maximum_run_seconds", "cost_ceiling"))
    if not 0 < (timestamp(window["end_at"]) - timestamp(window["start_at"])).total_seconds() <= 86400:
        raise ValueError("Finite maintenance window required.")
    number(window["maximum_run_seconds"], 60, 3600)
    number(window["cost_ceiling"], 0, 1000000)
    return value


def readiness_gaps(value, now=None):
    validate_manifest(value)
    now = now or datetime.now(timezone.utc)
    gaps = [name for name, qualified in value["qualification"].items() if not qualified]
    gaps.extend("authorization_" + name for name in ("traffic", "recovery") if not value["authorizations"][name])
    if not value["ledger"]["durability_qualified"]:
        gaps.append("ledger_durability")
    if not value["ledger"]["outside_fault_scope"]:
        gaps.append("ledger_containment")
    if not timestamp(value["window"]["start_at"]) <= now < timestamp(value["window"]["end_at"]):
        gaps.append("maintenance_window")
    return gaps


def authorize_traffic(value, config, ledger_path):
    gaps = readiness_gaps(value)
    if gaps:
        raise ValueError("Traffic prerequisites are incomplete.")
    if value["case_id"] != config["case_id"]:
        raise ValueError("Manifest/configuration case mismatch.")
    targets = {target["role"]: target["resource_id"].lower() for target in value["targets"]}
    if any(config["streams"][stream]["resource_id"].lower() != targets[stream] for stream in ("canary", "control")):
        raise ValueError("Traffic target not in the approved role-specific manifest.")
    if Path(ledger_path).absolute() != Path(value["ledger"]["path"]).absolute():
        raise ValueError("Traffic must use the qualified durable ledger path.")
    criteria = value["criteria"]
    if (config["minimum_success"] < criteria["minimum_success"] or
            config["request_timeout"] > criteria["request_deadline_seconds"] or
            config["maximum_run_seconds"] > value["window"]["maximum_run_seconds"] or
            datetime.now(timezone.utc).timestamp() + config["maximum_run_seconds"] >
            timestamp(value["window"]["end_at"]).timestamp()):
        raise ValueError("Traffic exceeds approved criteria or maintenance window.")
    if config["phase"] == "baseline" and (
            config["operations"] < criteria["baseline_operations"] or
            (config["operations"] - 1) * config["interval_seconds"] < criteria["baseline_seconds"]):
        raise ValueError("Baseline traffic does not meet the approved count/duration.")
    if config["phase"] == "exposure" and not value["authorizations"]["fault"]:
        raise ValueError("Exposure phase requires the existing fault authorization.")


def recovery_result(result, reason, **details):
    return {
        "result": result, "reason": reason, "case_certified": False, "fault_actions_executed": False,
        "evidence_scope": "Recorded sustained availability recovery windows only; not business integrity, RTO or fault qualification",
        "explanation_zh": {
            "Passed": "所选恢复观察窗口的可用性和延迟符合阈值；不代表完整业务或故障测试通过。",
            "Failed": "恢复窗口的可用性或延迟未达到约定阈值。",
            "Inconclusive": "恢复记录、时长或逐窗口样本不足，不能判定通过。",
        }[result],
        **details,
    }


def assess_recovery(records, criteria):
    if not records or records[0].get("event") != "observation_started":
        return recovery_result("Inconclusive", "missing_observation_start")
    start = records[0]
    identity = {key: start.get(key) for key in ("schema_version", "observation_id", "phase")}
    if (type(identity["schema_version"]) is not int or identity["schema_version"] != 1 or
            not isinstance(identity["observation_id"], str) or
            not re.fullmatch("[a-f0-9]{32}", identity["observation_id"]) or identity["phase"] != "recovery" or
            start.get("streams") not in (["control", "canary"], ["canary", "control"])):
        raise ValueError("One identified recovery observation with both streams required.")
    number(start.get("operations"), 1, 1000, True)
    samples = {"canary": [], "control": []}
    completion = None
    for record in records[1:]:
        if completion is not None:
            raise ValueError("Evidence after completion.")
        if record.get("event") == "request_failed":
            continue
        if {key: record.get(key) for key in identity} != identity:
            raise ValueError("Mixed recovery identity.")
        if record.get("event") == "observation_completed":
            completion = record
        elif record.get("event") == "measurement":
            stream = record.get("stream")
            if stream not in samples or type(record.get("sequence")) is not int or record["sequence"] != len(samples[stream]):
                raise ValueError("Missing, duplicate or unordered stream sequence.")
            number(record.get("elapsed_seconds"), 0, 3600)
            number(record.get("latency_seconds"), 0, 3600)
            if (type(record.get("success")) is not bool or
                    (samples[stream] and record["elapsed_seconds"] < samples[stream][-1]["elapsed_seconds"])):
                raise ValueError("Invalid recovery measurement.")
            samples[stream].append(record)
        else:
            raise ValueError("Unknown recovery event.")
    if completion is None or any(len(stream) != start["operations"] for stream in samples.values()):
        return recovery_result("Inconclusive", "incomplete_observation")
    if completion.get("result") not in ("Passed", "Failed", "Inconclusive"):
        raise ValueError("Invalid completion verdict.")
    elapsed = completion.get("elapsed_seconds")
    if elapsed is None:
        measurements = completion.get("measurements")
        if not isinstance(measurements, dict) or not all(stream in measurements for stream in samples):
            raise ValueError("Observation duration required.")
        elapsed = min(measurements[stream]["elapsed_seconds"] for stream in samples)
    number(elapsed, 0, 3600)
    horizon = criteria["recovery_windows"] * criteria["recovery_window_seconds"]
    if elapsed < horizon or completion["result"] == "Inconclusive":
        return recovery_result("Inconclusive", "short_recovery_observation")
    window_results = []
    for stream, stream_samples in samples.items():
        for index in range(criteria["recovery_windows"]):
            lower = index * criteria["recovery_window_seconds"]
            upper = lower + criteria["recovery_window_seconds"]
            window = [sample for sample in stream_samples if lower <= sample["elapsed_seconds"] < upper]
            if len(window) < criteria["recovery_minimum_operations"]:
                return recovery_result("Inconclusive", "missing_window_samples", stream=stream, window=index)
            latencies = sorted(sample["latency_seconds"] for sample in window)
            success = sum(sample["success"] and sample["latency_seconds"] <= criteria["request_deadline_seconds"]
                          for sample in window) / len(window)
            p95 = latencies[math.ceil(len(latencies) * 0.95) - 1]
            window_results.append({"stream": stream, "window": index, "operations": len(window),
                                   "success_rate": success, "p95_seconds": p95})
    failed = completion["result"] == "Failed" or any(
        window["success_rate"] < criteria["minimum_success"] or
        window["p95_seconds"] > criteria["maximum_p95_seconds"] for window in window_results)
    return recovery_result("Failed" if failed else "Passed", "window_thresholds", windows=window_results)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Read-only manifest and recorded recovery-window assessment.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--recovery-jsonl")
    args = parser.parse_args(argv)
    try:
        value = validate_manifest(load_json(args.manifest))
        if args.recovery_jsonl:
            path = Path(args.recovery_jsonl)
            if path.stat().st_size > 16 * 1024 * 1024:
                raise ValueError("Evidence file exceeds the input budget.")
            with path.open() as evidence:
                records = []
                for line in evidence:
                    if len(line) > 65536 or len(records) >= 4096:
                        raise ValueError("Evidence record budget exceeded.")
                    record = json.loads(line)
                    if not isinstance(record, dict):
                        raise ValueError("Object evidence records required.")
                    records.append(record)
            result = assess_recovery(records, value["criteria"])
        else:
            gaps = readiness_gaps(value)
            result = {"result": "Blocked" if gaps else "Inconclusive", "readiness_gaps": gaps,
                      "case_certified": False, "fault_actions_executed": False,
                      "evidence_scope": "Manifest structure and supplied qualifications only; not live cloud verification",
                      "explanation_zh": "仍需核对实际云端支持、目标、业务基线及故障恢复证据；格式或标志不能替代验证。"}
        print(json.dumps(result), flush=True)
        return {"Passed": 0, "Failed": 1, "Inconclusive": 2, "Blocked": 3}[result["result"]]
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(json.dumps({"result": "Blocked", "error_type": type(error).__name__, "case_certified": False,
                          "fault_actions_executed": False,
                          "explanation_zh": "清单或证据格式无效；不会运行测试或故障。"}), flush=True)
        return 3


if __name__ == "__main__":
    sys.exit(main())
