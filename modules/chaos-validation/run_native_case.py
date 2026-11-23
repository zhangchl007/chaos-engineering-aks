import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.parse
import urllib.request
from urllib.error import HTTPError, URLError


DEFAULT_CONFIG_DIR = Path(__file__).resolve().parents[2] / "local-state/dev/chaos-testing"
API = "?api-version=2026-08-01-preview"
TERMINAL = {"Succeeded", "Failed", "Canceled"}
CASES = {
    "b01-servicebus-send-disabled": ("B-01", "service_bus", "queues", "SendDisabled", True),
    "b02-servicebus-receive-disabled": ("B-02", "service_bus", "queues", "ReceiveDisabled", True),
    "h01-eventhub-send-disabled": ("H-01", "event_hubs", "eventhubs", "SendDisabled", True),
    "h02-eventhub-disabled": ("H-02", "event_hubs", "eventhubs", "Disabled", True),
    "m02-mysql-restart": ("M-02", "mysql", None, None, False),
    "p01-postgresql-planned-failover": ("P-01", "postgresql", None, None, True),
    "m01-mysql-ha-failover": ("M-01", "mysql", None, None, True),
    "r02-legacy-redis-secondary-reboot": ("R-02", "legacy_redis", None, None, False),
    "r01-legacy-redis-primary-reboot": ("R-01", "legacy_redis", None, None, False),
}


def utc():
    return datetime.now(timezone.utc).isoformat()


def az(args):
    result = subprocess.run(
        ["az", *args, "-o", "json"], capture_output=True, text=True,
        timeout=60, check=True,
    )
    return json.loads(result.stdout)


def load_inputs(directory):
    variables = json.loads((directory / "native-chaos.private.tfvars.json").read_text())
    workspace = json.loads((directory / "native-workspace-current.private.json").read_text())["id"]
    if re.search(r"<[^>]+>", json.dumps(variables) + workspace):
        raise ValueError("Replace all example placeholders with approved private inputs")
    if not variables["enabled"] or not variables["scenarios"]:
        raise ValueError("An existing enabled Workspace and complete scenario map are required")
    expected = variables["resource_group_id"] + "/providers/Microsoft.Chaos/workspaces/" + variables["name"]
    if workspace.lower() != expected.lower():
        raise ValueError("Workspace does not match the configured owner")
    if variables["resource_group_id"].split("/")[2].lower() != variables["subscription_id"].lower():
        raise ValueError("Workspace subscription does not match the private inputs")
    for name, definition in variables["scenarios"].items():
        targets = definition["target_ids"]
        if len(targets) != 1 or definition["duration_minutes"] != 1:
            raise ValueError("Native tools require one explicit target and one-minute definitions")
        if not targets[0].startswith("/subscriptions/") or "*" in targets[0]:
            raise ValueError("An exact target ARM ID is required")
        if name in CASES:
            case_id, _, entity_key, desired, _ = CASES[name]
            expected = {"desiredState": desired} if entity_key else {}
            if case_id in {"R-01", "R-02"}:
                expected = {"RebootType": "PrimaryNode" if case_id == "R-01" else "SecondaryNode"}
            elif case_id == "M-01":
                expected = {"RestoreOnStop": "false"}
            elif case_id == "P-01":
                expected = {"FailoverMode": "PlannedFailover", "RestoreOnStop": "false",
                            "SkipIneligibleServers": "false"}
            parameters = {key: value for key, value in definition["parameters"].items()
                          if key not in {"queues", "eventhubs"}}
            if parameters != expected:
                raise ValueError("Case parameters changed; forced/all-node/alternate-state variants are not authorized by this runner")
    return variables, workspace


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Management redirects are not allowed")


class Client:
    def __init__(self, variables):
        account = az(["account", "show", "--subscription", variables["subscription_id"]])
        if (account["id"].lower() != variables["subscription_id"].lower() or
                account["tenantId"].lower() != variables["tenant_id"].lower()):
            raise ValueError("Azure account does not match the approved subscription/tenant")
        self.token = az([
            "account", "get-access-token", "--subscription", variables["subscription_id"],
            "--resource", "https://management.azure.com/",
        ])["accessToken"]
        self.subscription = variables["subscription_id"]
        self.versions = {}

    def request(self, url, method="GET"):
        url = urllib.parse.urljoin("https://management.azure.com", url)
        parsed = urllib.parse.urlsplit(url)
        if parsed.netloc != "management.azure.com" or parsed.scheme != "https":
            raise ValueError("Unexpected management endpoint")
        request = urllib.request.Request(
            url, method=method,
            headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"},
        )
        opener = urllib.request.build_opener(NoRedirect())
        for attempt in range(3):
            try:
                with opener.open(request, timeout=30) as response:
                    raw = response.read(5_000_001)
                    if len(raw) > 5_000_000:
                        raise ValueError("Oversized management response")
                    return response.status, dict(response.headers), json.loads(raw) if raw else None
            except (HTTPError, URLError, TimeoutError) as error:
                retryable = not isinstance(error, HTTPError) or error.code in {429, 500, 502, 503, 504}
                if method != "GET" or not retryable or attempt == 2:
                    raise
                print("Transient management GET failure; bounded read-only retry",
                      attempt + 1, type(error).__name__, flush=True)
                time.sleep(5)

    def get(self, url):
        return self.request(url)[2]

    def listing(self, url):
        rows = []
        while url:
            page = self.get(url)
            rows.extend(page["value"])
            url = page.get("nextLink")
        return rows

    def operation(self, url):
        status, headers, body = self.request(url, "POST")
        location = next((v for k, v in headers.items() if k.lower() == "location"), None)
        if status == 202 and not location:
            raise ValueError("Async operation has no polling location")
        deadline = time.monotonic() + 180
        while status == 202:
            if time.monotonic() >= deadline:
                raise TimeoutError("Native validation/cancellation timed out")
            time.sleep(5)
            status, headers, body = self.request(location)
        if status not in (200, 204):
            raise ValueError("Native operation did not complete")
        return body

    def resource(self, resource_id):
        parts = resource_id.split("/")
        namespace = parts[6]
        resource_type = "/".join(parts[7::2])
        key = (namespace, resource_type.lower())
        if key not in self.versions:
            provider = az(["provider", "show", "--namespace", namespace, "--subscription", self.subscription])
            entry = next(x for x in provider["resourceTypes"]
                         if x["resourceType"].lower() == resource_type.lower())
            self.versions[key] = next(x for x in entry["apiVersions"] if "preview" not in x.lower())
        return self.get(resource_id + "?api-version=" + self.versions[key])


def check_binding(client, variables, workspace, case):
    definition = variables["scenarios"][case]
    scenario_id = workspace + "/scenarios/" + case
    configuration_id = scenario_id + "/configurations/approved-targets"
    scenario = client.get(scenario_id + API)
    configuration = client.get(configuration_id + API)
    actions = scenario["properties"]["actions"]
    if len(actions) != 1 or actions[0]["actionId"] != definition["action_id"]:
        raise ValueError("Action binding changed")
    if (actions[0]["duration"] != "PT1M" or
            {p["key"]: p["value"] for p in actions[0]["parameters"]} != definition["parameters"]):
        raise ValueError("Action parameters changed")
    properties = configuration["properties"]
    if properties["provisioningState"] != "Succeeded":
        raise ValueError("Native configuration provisioning incomplete")
    if properties["scenarioId"].lower() not in {case.lower(), scenario_id.lower()}:
        raise ValueError("Configuration parent Scenario changed")
    targeting = properties["resourceTargeting"]
    include = targeting["include"]
    if include["resources"] != definition["target_ids"]:
        raise ValueError("Target binding changed")
    for key in ("locations", "zones"):
        if set(include.get(key, [])) != set(definition.get(key, [])):
            raise ValueError("Location/zone binding changed")
    if set(include) - {"resources", "locations", "zones"}:
        raise ValueError("Unexpected additional target filters")
    if set(targeting["exclude"]["resources"]) != set(variables["excluded_resource_ids"]):
        raise ValueError("Exclusion binding changed")
    required_tags = {("environment", "production"), ("environment", "prod"), ("chaos-excluded", "true")}
    if not required_tags.issubset({(tag["key"], tag["value"]) for tag in targeting["exclude"]["tags"]}):
        raise ValueError("Production/recovery tag exclusions changed")
    if properties["parameters"]:
        raise ValueError("Unexpected configuration overrides")
    return scenario_id, configuration_id


def healthy(properties, label, entity):
    if entity:
        return properties["status"] == "Active"
    if label in {"mysql", "postgresql"}:
        return properties["state"] == "Ready" and properties["highAvailability"]["state"] == "Healthy"
    return properties["provisioningState"] == "Succeeded"


def create_journal(path, record):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
        json.dump(record, stream, indent=2)


def finish_run(client, record, target, observed_id, label, entity, desired, save):
    properties = record["final_run"]["properties"]
    if properties["status"] != "Succeeded":
        raise RuntimeError("Native run did not succeed; stop the batch")
    summaries = properties["scenarioRunSummary"]
    if len(summaries) != 1 or summaries[0]["state"] != "Succeeded":
        raise RuntimeError("Action was skipped, failed or incompletely reported")
    if {x["id"].lower() for x in summaries[0]["resources"]} != {target.lower()}:
        raise ValueError("Completed action has no exact approved target")
    deadline = time.monotonic() + 600
    while True:
        restored = client.resource(observed_id)
        record["samples"].append({"observed_at": utc(), "resource": restored})
        save()
        if healthy(restored["properties"], label, entity):
            record["restored"] = restored
            break
        if time.monotonic() >= deadline:
            raise TimeoutError("Resource did not recover within ten minutes")
        time.sleep(10)
    record.setdefault("post_health_samples", [])
    while True:
        record["post_health"] = client.get(
            target + "/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2025-05-01")
        record["post_health_samples"].append({"observed_at": utc(), "health": record["post_health"]})
        save()
        if record["post_health"]["properties"]["availabilityState"] == "Available":
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("Post-run Resource Health did not recover within the recovery budget")
        time.sleep(10)
    record["effect_observed"] = (
        any(x["resource"]["properties"].get("status") == desired for x in record["samples"])
        if entity else any(not healthy(x["resource"]["properties"], label, entity) for x in record["samples"])
    )
    record["complete"] = True
    record["completed_at"] = utc()
    save()
    print(record["case_id"], "native run/action Succeeded; recovery verified; direct state transition observed:",
          record["effect_observed"], flush=True)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Bounded native PaaS preflight; Execute requires explicit authorization.")
    parser.add_argument("case", choices=CASES, nargs="?")
    parser.add_argument("--config-dir", type=Path, default=DEFAULT_CONFIG_DIR)
    parser.add_argument("--check-inputs", action="store_true", help="Offline input validation only; no Azure calls.")
    parser.add_argument("--execute", action="store_true", help="Execute one newly authorized native fault, never replay a journal.")
    args = parser.parse_args()
    if args.check_inputs and args.execute:
        parser.error("--check-inputs cannot authorize Execute")
    stage = args.config_dir.resolve()
    variables, workspace = load_inputs(stage)
    if args.check_inputs:
        print("Private project inputs verified;", len(variables["scenarios"]), "single-target definitions; no Azure calls")
        return
    if args.case is None:
        parser.error("Select one case, or use --check-inputs")
    case_id, label, entity_key, desired, cancelable = CASES[args.case]
    definition = variables["scenarios"][args.case]
    evidence_dir = stage / "native-test-runs"
    evidence_path = evidence_dir / (args.case + ".private.json")
    if args.execute and evidence_path.exists():
        raise RuntimeError("An execution journal already exists; observe the same run, never retry Execute blindly")
    catalog = json.loads((stage / "regional-catalog.private.json").read_text())["value"]
    action_type = next(x["properties"]["actionType"] for x in catalog
                       if x["name"].lower() == definition["action_id"].split("/")[0].lower())
    if cancelable != (action_type == "Cancelable"):
        raise ValueError("Cancellation policy does not match the verified native catalog")
    target = variables["permissions"][label]["target_id"]
    if definition["target_ids"] != [target]:
        raise ValueError("Unexpected target")
    if not target.lower().startswith((variables["resource_group_id"] + "/providers/").lower()):
        raise ValueError("PaaS execution must stay in the approved resource group")
    entities = json.loads(definition["parameters"][entity_key]) if entity_key else []
    if entity_key and (len(entities) != 1 or not isinstance(entities[0], str) or
                       not entities[0] or any(character in entities[0] for character in "/*")):
        raise ValueError("Select one exact existing queue/hub")
    entity = entities[0] if entity_key else None
    observed_id = target + "/" + entity_key + "/" + entity if entity else target
    client = Client(variables)
    scenario_id, configuration_id = check_binding(client, variables, workspace, args.case)
    validation = client.operation(configuration_id + "/validate" + API)
    if validation["properties"]["status"] != "Succeeded":
        raise RuntimeError("Latest native validation requires attention")
    if {x["id"].lower() for x in validation["properties"]["resources"]} != {target.lower()}:
        raise ValueError("Validation resolved outside the approved target")
    for item in client.listing(workspace + "/scenarios" + API):
        for run in client.listing(item["id"] + "/runs" + API):
            if run["properties"]["status"] not in TERMINAL:
                raise RuntimeError("Another native run is active; refusing overlap")
    baseline = client.resource(observed_id)
    if not healthy(baseline["properties"], label, entity):
        raise RuntimeError("Baseline state/HA is not eligible")
    health = client.get(target + "/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2025-05-01")
    if health["properties"]["availabilityState"] != "Available":
        raise RuntimeError("Resource Health is not Available")
    print(case_id, "preflight: target, parameters, exclusions, validation, baseline and Resource Health verified", flush=True)
    if not args.execute:
        return
    evidence_dir.mkdir(mode=0o700, exist_ok=True)
    record = {
        "case_id": case_id, "scenario": args.case, "definition": definition,
        "validation": validation, "baseline": baseline, "resource_health": health,
        "request_started_at": utc(), "samples": [], "run_snapshots": [],
        "execution_attempted": False, "complete": False,
    }
    create_journal(evidence_path, record)

    def save():
        evidence_path.write_text(json.dumps(record, indent=2))

    before_ids = {x["id"] for x in client.listing(scenario_id + "/runs" + API)}
    record["previous_run_ids"] = sorted(before_ids)
    save()
    run_id = None
    last_status = None
    run_deadline = time.monotonic() + 900
    try:
        record["execution_attempted"] = True
        save()
        status, headers, body = client.request(configuration_id + "/execute" + API, "POST")
        record["execute_response"] = {"status": status, "headers": headers, "body": body}
        save()
        if status != 202:
            raise RuntimeError("Execute did not return documented acceptance")
        deadline = time.monotonic() + 120
        while run_id is None:
            candidates = [x for x in client.listing(scenario_id + "/runs" + API) if x["id"] not in before_ids]
            if len(candidates) > 1:
                raise RuntimeError("Ambiguous concurrent run creation; refusing another Execute")
            if candidates:
                run_id = candidates[0]["id"]
                if not run_id.lower().startswith((scenario_id + "/runs/").lower()):
                    raise ValueError("Run is not owned by the approved Scenario")
                record["run_id"] = run_id
                save()
            elif time.monotonic() >= deadline:
                raise TimeoutError("Accepted run could not be identified; do not retry Execute")
            else:
                time.sleep(5)
        deadline = run_deadline
        while True:
            run = client.get(run_id + API)
            properties = run["properties"]
            last_status = properties["status"]
            record["run_snapshots"].append({"observed_at": utc(), "run": run})
            selected_ids = {x["id"].lower() for x in properties["resources"]} - {
                x["id"].lower() for x in properties.get("excludedResources", [])
            }
            if selected_ids and selected_ids != {target.lower()}:
                raise ValueError("Run resolved outside the explicit target")
            sample = client.resource(observed_id)
            record["samples"].append({"observed_at": utc(), "resource": sample})
            save()
            if last_status in TERMINAL:
                record["final_run"] = run
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Run exceeded 15-minute stop threshold")
            time.sleep(5)
        finish_run(client, record, target, observed_id, label, entity, desired, save)
    finally:
        if run_id and not record["complete"] and last_status not in TERMINAL and cancelable:
            record["cancel_result"] = client.operation(run_id + "/cancel" + API)
            deadline = time.monotonic() + 300
            while True:
                record["after_cancel"] = client.get(run_id + API)
                last_status = record["after_cancel"]["properties"]["status"]
                save()
                if last_status in TERMINAL:
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError("Cancellation did not reach terminal state; operator recovery required")
                time.sleep(5)
        if run_id and not record["complete"] and entity and last_status in TERMINAL:
            current = client.resource(observed_id)
            record["recovery_before"] = current
            save()
            if current["properties"]["status"] != baseline["properties"]["status"]:
                parts = target.split("/")
                command = (["servicebus", "queue", "update"] if label == "service_bus"
                           else ["eventhubs", "eventhub", "update"])
                record["recovery_update"] = az([
                    *command, "--subscription", variables["subscription_id"],
                    "--resource-group", parts[4], "--namespace-name", parts[-1],
                    "--name", entity, "--status", baseline["properties"]["status"],
                ])
                record["recovery_after"] = client.resource(observed_id)
                save()
                if record["recovery_after"]["properties"]["status"] != baseline["properties"]["status"]:
                    raise RuntimeError("Exact entity baseline state restoration failed")
        save()


if __name__ == "__main__":
    main()
