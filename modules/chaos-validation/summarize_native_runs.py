import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path

from run_native_case import CASES, DEFAULT_CONFIG_DIR, healthy


def summarize(path):
    content = path.read_bytes()
    record = json.loads(content)
    case = record["scenario"]
    if case not in CASES or record["case_id"] != CASES[case][0]:
        raise ValueError("Unknown/mismatched native execution journal")
    case_id, label, entity_key, _, _ = CASES[case]
    properties = record.get("final_run", {}).get("properties", {})
    actions = properties.get("scenarioRunSummary", [])
    targets = {value.lower() for value in record["definition"]["target_ids"]}
    action_targets = {value["id"].lower() for action in actions for value in action["resources"]}
    native_status = properties.get("status")
    action_status = actions[0]["state"] if len(actions) == 1 else None
    health = record.get("post_health", {}).get("properties", {}).get("availabilityState")
    restored = record.get("restored", {}).get("properties", {})
    recovered = bool(restored) and healthy(restored, label, entity_key)
    effect = record.get("effect_observed") is True
    qualified = (record.get("complete") is True and native_status == "Succeeded" and
                 action_status == "Succeeded" and action_targets == targets and
                 len(targets) == 1 and health == "Available" and recovered)
    result = ("Failed" if native_status in {"Failed", "Canceled"} or action_status == "Failed"
              else "Passed" if qualified and effect else "Inconclusive")
    local = timezone(timedelta(hours=8))
    start = datetime.fromisoformat(properties["startTime"]) if properties.get("startTime") else None
    end = datetime.fromisoformat(properties["endTime"]) if properties.get("endTime") else None
    return {
        "case_id": case_id, "native_status": native_status, "action_status": action_status,
        "target_count": len(action_targets),
        "start_local": start.astimezone(local).isoformat() if start else None,
        "end_local": end.astimezone(local).isoformat() if end else None,
        "run_seconds": round((end - start).total_seconds()) if start and end else None,
        "management_result": result, "effect_observed": effect,
        "observation_gap": bool(record.get("observation_gap")),
        "health_final": health, "infra_business_result": "Inconclusive",
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description="Offline sanitized journal summary; no Azure calls or source journal changes.")
    parser.add_argument("--config-dir", type=Path, default=DEFAULT_CONFIG_DIR)
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args()
    paths = sorted((args.config_dir / "native-test-runs").glob("*.private.json"))
    if not paths:
        raise ValueError("No native execution journals found")
    rows = [summarize(path) for path in paths]
    if len({row["case_id"] for row in rows}) != len(rows):
        raise ValueError("Duplicate case journals; select one explicit cohort")
    if args.markdown:
        print("# Native run journal summary\n")
        print("仅复核历史管理面证据；未查询云端当前状态，完整 infra/business 验收未验证。\n")
        print("| Case | Run | Action | 管理面 | 完整验收 | 实际秒数 | SHA256 |")
        print("| --- | --- | --- | --- | --- | --- | --- |")
        for row in rows:
            print(f"| {row['case_id']} | {row['native_status']} | {row['action_status']} | "
                  f"{row['management_result']} | {row['infra_business_result']} | "
                  f"{row['run_seconds']} | `{row['sha256']}` |")
    else:
        print(json.dumps({"live_cloud_checked": False, "evidence_scope": "Historical native management-plane journals only",
                          "cases": rows}, indent=2))


if __name__ == "__main__":
    main()
