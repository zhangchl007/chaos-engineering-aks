import argparse
import json
import os
from pathlib import Path

from run_native_case import API, DEFAULT_CONFIG_DIR, Client, check_binding, load_inputs


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Validate existing native configurations; never Execute or fix permissions.")
    parser.add_argument("cases", nargs="*")
    parser.add_argument("--config-dir", type=Path, default=DEFAULT_CONFIG_DIR)
    args = parser.parse_args()
    stage = args.config_dir.resolve()
    variables, workspace = load_inputs(stage)
    selected = args.cases or list(variables["scenarios"])
    if not all(case in variables["scenarios"] for case in selected):
        parser.error("Unknown native validation selection")
    client = Client(variables)
    report_path = stage / "native-validations.private.json"
    reports = json.loads(report_path.read_text()) if report_path.exists() else {}
    for case in selected:
        _, configuration_id = check_binding(client, variables, workspace, case)
        result = client.operation(configuration_id + "/validate" + API)
        if result["properties"]["status"] != "Succeeded":
            raise RuntimeError("Native validation requires attention; no automatic permission repair")
        resolved = {value["id"].lower() for value in result["properties"]["resources"]}
        if resolved != {value.lower() for value in variables["scenarios"][case]["target_ids"]}:
            raise ValueError("Native validation did not resolve exactly the approved target")
        reports[case] = {"configuration_id": configuration_id, "binding_verified": True, "result": result}
        report_path.write_text(json.dumps(reports, indent=2))
        print(case, "exact binding and native validation Succeeded", flush=True)
    print(len(selected), "selected configurations validated; no Execute or permission-fixing request sent")


if __name__ == "__main__":
    main()
