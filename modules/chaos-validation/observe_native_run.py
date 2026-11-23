import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import time

from run_native_case import (
    API, CASES, DEFAULT_CONFIG_DIR, TERMINAL, Client, finish_run, load_inputs, utc,
)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Observe the existing owned run; never Execute, cancel or mutate a service.")
    parser.add_argument("case", choices=CASES)
    parser.add_argument("--config-dir", type=Path, default=DEFAULT_CONFIG_DIR)
    args = parser.parse_args()
    stage = args.config_dir.resolve()
    variables, workspace = load_inputs(stage)
    path = stage / "native-test-runs" / (args.case + ".private.json")
    record = json.loads(path.read_text())
    if record["complete"]:
        print("Existing journal is already complete; retained evidence unchanged; no Azure calls")
        return
    case_id, label, entity_key, desired, _ = CASES[args.case]
    target = variables["permissions"][label]["target_id"]
    if (record["case_id"] != case_id or record["scenario"] != args.case or
            record["definition"] != variables["scenarios"][args.case] or
            record["baseline"]["id"].lower() != (
                target + "/" + entity_key + "/" + json.loads(record["definition"]["parameters"][entity_key])[0]
                if entity_key else target).lower()):
        raise ValueError("Existing journal does not match the approved inputs/baseline")
    run_id = record.get("run_id")
    if not run_id or not run_id.lower().startswith((workspace + "/scenarios/" + args.case + "/runs/").lower()):
        raise ValueError("Run identity absent or ambiguous; inspect Run history, never replay Execute")
    entity = json.loads(record["definition"]["parameters"][entity_key])[0] if entity_key else None
    observed_id = target + "/" + entity_key + "/" + entity if entity else target
    client = Client(variables)
    record["observation_gap"] = {
        "reason": "Operator resumed existing run observation",
        "resumed_at": utc(), "execute_repeated": False,
    }

    def save():
        path.write_text(json.dumps(record, indent=2))

    save()
    started = datetime.fromisoformat(record["request_started_at"])
    while True:
        run = client.get(run_id + API)
        properties = run["properties"]
        record["run_snapshots"].append({"observed_at": utc(), "run": run})
        selected = {x["id"].lower() for x in properties["resources"]} - {
            x["id"].lower() for x in properties.get("excludedResources", [])
        }
        if selected and selected != {target.lower()}:
            raise ValueError("Existing run resolved outside the approved target")
        record["samples"].append({"observed_at": utc(), "resource": client.resource(observed_id)})
        save()
        if properties["status"] in TERMINAL:
            record["final_run"] = run
            save()
            break
        if (datetime.now(timezone.utc) - started).total_seconds() > 900:
            raise TimeoutError("Existing run exceeded stop threshold; use authorized native cancellation/recovery, not replay")
        time.sleep(5)
    finish_run(client, record, target, observed_id, label, entity, desired, save)


if __name__ == "__main__":
    main()
