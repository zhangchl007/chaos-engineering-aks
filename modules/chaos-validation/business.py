import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import logging
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import threading
import time
from typing import Protocol

from ledger import Ledger, LedgerConflict
from campaign import GUID


class TrafficFailure(Exception):
    pass


class Workload(Protocol):
    def send(self, operation_id: str, payload: bytes) -> None: ...
    def verify(self, store: Ledger, run_id: str, stream: str, timeout: float, remaining_seconds: float) -> None: ...
    def close(self) -> None: ...


def validate_config(config):
    required = {"run_id", "case_id", "phase", "kind", "operations", "interval_seconds", "request_timeout",
                "maximum_run_seconds", "minimum_success", "streams"}
    if not isinstance(config, dict) or config.keys() != required:
        raise ValueError("Invalid configuration fields; never include credentials.")
    cases = {"blob": {"S-01"}, "servicebus": {"B-01", "B-02", "B-04"}}
    if (not isinstance(config["kind"], str) or config["kind"] not in cases or
            not isinstance(config["case_id"], str) or config["case_id"] not in cases[config["kind"]] or
            not isinstance(config["run_id"], str) or not re.fullmatch("[a-f0-9]{32}", config["run_id"]) or
            config["phase"] not in ("baseline", "exposure", "recovery") or
            type(config["operations"]) is not int or not 1 <= config["operations"] <= 1000):
        raise ValueError("Invalid reference case, phase or operation budget.")
    for key, lower, upper in (("interval_seconds", 0, 60), ("request_timeout", 0.1, 10),
                              ("maximum_run_seconds", 60, 3600), ("minimum_success", 0, 1)):
        value = config[key]
        if type(value) not in (int, float) or not lower <= value <= upper or not math.isfinite(value):
            raise ValueError("Invalid finite budget or success threshold.")
    if config["operations"] * max(2 * config["request_timeout"], config["interval_seconds"]) > config["maximum_run_seconds"] - 60:
        raise ValueError("Traffic and verification must fit the finite budget with headroom.")
    streams = config["streams"]
    if not isinstance(streams, dict) or streams.keys() != {"control", "canary"}:
        raise ValueError("Independent control and canary required.")
    pattern = (r"https://[a-z0-9]{3,24}\.blob\.core\.windows\.net" if config["kind"] == "blob"
               else r"[a-z][a-z0-9-]{4,48}[a-z0-9]\.servicebus\.windows\.net")
    for target in streams.values():
        if (not isinstance(target, dict) or target.keys() != {"endpoint", "entity", "resource_id"} or
                not isinstance(target["endpoint"], str) or not re.fullmatch(pattern, target["endpoint"]) or
                not isinstance(target["entity"], str) or not re.fullmatch(r"chaos-[a-z0-9]+(?:-[a-z0-9]+)*", target["entity"]) or
                len(target["entity"]) > 63):
            raise ValueError("Use exact token-free public-cloud service names and dedicated chaos-prefixed entities.")
        provider = "Microsoft.Storage/storageAccounts" if config["kind"] == "blob" else "Microsoft.ServiceBus/namespaces"
        resource_id = target["resource_id"]
        if (not isinstance(resource_id, str) or not re.fullmatch(
                r"/subscriptions/" + GUID + r"/resourceGroups/[^/*?#\s]+/providers/" + provider + r"/[^/*?#\s]+",
                resource_id)):
            raise ValueError("Explicit service resource IDs required.")
        resource_name = resource_id.rsplit("/", 1)[1]
        expected_endpoint = ("https://" + resource_name + ".blob.core.windows.net" if config["kind"] == "blob"
                             else resource_name + ".servicebus.windows.net")
        if target["endpoint"] != expected_endpoint:
            raise ValueError("Resource identity must match the service endpoint.")
    if streams["canary"]["endpoint"] == streams["control"]["endpoint"]:
        raise ValueError("Control must not share the faulted account or namespace.")
    return config


class BlobWorkload:
    def __init__(self, container, timeout, errors):
        self.container, self.timeout, self.errors = container, timeout, errors

    def send(self, operation_id, payload):
        try:
            self.container.upload_blob("chaos/" + operation_id, payload, overwrite=False,
                                       timeout=self.timeout)
        except self.errors as error:
            raise TrafficFailure(type(error).__name__) from error

    def verify(self, store, run_id, stream, timeout, remaining_seconds):
        deadline = time.monotonic() + remaining_seconds
        for operation in store.operations(run_id, stream):
            if time.monotonic() >= deadline:
                raise TrafficFailure("VerificationBudgetExceeded")
            try:
                downloader = self.container.download_blob("chaos/" + operation["operation_id"],
                                                           offset=0, length=4097, timeout=timeout)
                payload = downloader.readall()
            except self.errors as error:
                raise TrafficFailure(type(error).__name__) from error
            if not store.effect(operation["operation_id"], payload, settled=True):
                raise TrafficFailure("PayloadConflict")

    def close(self):
        self.container.close()


class ServiceBusWorkload:
    def __init__(self, client, queue, timeout, message_type, receive_mode, errors):
        self.client, self.queue, self.timeout = client, queue, timeout
        self.message_type, self.receive_mode, self.errors = message_type, receive_mode, errors
        self.sender = None

    def send(self, operation_id, payload):
        try:
            if self.sender is None:
                self.sender = self.client.get_queue_sender(queue_name=self.queue)
            self.sender.send_messages(self.message_type(payload, message_id=operation_id), timeout=self.timeout)
        except self.errors as error:
            raise TrafficFailure(type(error).__name__) from error

    def verify(self, store, run_id, stream, timeout, remaining_seconds):
        expected = {row["operation_id"] for row in store.operations(run_id, stream)}
        completed = set()
        deadline = time.monotonic() + remaining_seconds
        try:
            with self.client.get_queue_receiver(queue_name=self.queue, receive_mode=self.receive_mode,
                                                prefetch_count=0, max_wait_time=timeout) as receiver:
                deliveries = 0
                while completed != expected and time.monotonic() < deadline and deliveries < len(expected) * 4:
                    wait = min(timeout, deadline - time.monotonic())
                    if wait <= 0:
                        break
                    messages = receiver.receive_messages(max_message_count=1, max_wait_time=wait)
                    for message in messages:
                        deliveries += 1
                        operation_id = message.message_id
                        if operation_id not in expected:
                            receiver.abandon_message(message)
                            raise TrafficFailure("UnexpectedMessage")
                        payload = bytearray()
                        for section in message.body:
                            payload.extend(section[:4097 - len(payload)])
                            if len(payload) > 4096:
                                break
                        if not store.effect(operation_id, bytes(payload)):
                            receiver.abandon_message(message)
                            raise TrafficFailure("PayloadConflict")
                        receiver.complete_message(message)
                        store.settle(operation_id)
                        completed.add(operation_id)
        except self.errors as error:
            raise TrafficFailure(type(error).__name__) from error
        if completed != expected:
            raise TrafficFailure("IncompleteMessageCohort")

    def close(self):
        self.client.close()


def make_client(kind, target, timeout, credential):
    from azure.core.exceptions import AzureError
    if kind == "blob":
        from azure.storage.blob import BlobServiceClient, ExponentialRetry
        client = BlobServiceClient(target["endpoint"], credential=credential,
                                   retry_policy=ExponentialRetry(retry_total=0),
                                   connection_timeout=timeout, read_timeout=timeout, logging_enable=False)
        return BlobWorkload(client.get_container_client(target["entity"]), timeout, (AzureError,))
    from azure.servicebus import ServiceBusClient, ServiceBusMessage, ServiceBusReceiveMode
    client = ServiceBusClient(target["endpoint"], credential, retry_total=0, logging_enable=False)
    return ServiceBusWorkload(client, target["entity"], timeout, ServiceBusMessage,
                              ServiceBusReceiveMode.PEEK_LOCK, (AzureError,))


def execute(config, path, clients: dict[str, Workload], emit):
    validate_config(config)
    if clients.keys() != {"canary", "control"}:
        raise ValueError("Two explicit independent clients required.")
    store = Ledger(path)
    output_lock = threading.Lock()
    identity = {"schema_version": 1, "observation_id": config["run_id"], "phase": config["phase"]}
    started = time.monotonic()
    deadline = started + config["maximum_run_seconds"]

    def publish(record):
        with output_lock:
            emit(record)

    def worker(stream):
        client = clients[stream]
        for sequence in range(config["operations"]):
            delay = started + sequence * config["interval_seconds"] - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            if time.monotonic() >= deadline:
                publish({"event": "request_failed", "error_type": "RunBudgetExceeded"})
                return
            payload = json.dumps({"run_id": config["run_id"], "stream": stream, "sequence": sequence},
                                 sort_keys=True).encode()
            operation_id = store.intent(config["run_id"], stream, sequence, payload)
            request_started = time.monotonic()
            state = "acknowledged"
            error_type = None
            try:
                client.send(operation_id, payload)
            except TrafficFailure as error:
                state, error_type = "unknown", str(error)
                publish({"event": "request_failed", "error_type": error_type})
            latency = time.monotonic() - request_started
            store.outcome(operation_id, state, latency, error_type)
            publish({**identity, "event": "measurement", "stream": stream, "sequence": sequence,
                     "elapsed_seconds": request_started - started, "latency_seconds": latency,
                     "success": state == "acknowledged" and latency <= config["request_timeout"]})
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        try:
            client.verify(store, config["run_id"], stream, config["request_timeout"], remaining)
        except TrafficFailure as error:
            publish({"event": "request_failed", "error_type": str(error)})

    try:
        store.start_run(config["run_id"], config["case_id"], config["phase"], config["operations"], config["kind"])
        publish({**identity, "event": "observation_started", "streams": ["canary", "control"],
                 "operations": config["operations"]})
        with ThreadPoolExecutor(max_workers=2) as executor:
            pending = [executor.submit(worker, stream) for stream in ("canary", "control")]
            for future in pending:
                future.result()
        store.finish_run(config["run_id"])
        result = store.evaluate(config["run_id"], config["minimum_success"], config["request_timeout"])
        result["elapsed_seconds"] = time.monotonic() - started
        publish({**identity, "event": "observation_completed", **result, "measurements": result["streams"]})
        return result
    finally:
        store.close()


def verify_existing(config, path, clients: dict[str, Workload], emit):
    validate_config(config)
    if not Path(path).is_file():
        raise OSError("Existing ledger required; verification does not create a new cohort.")
    store = Ledger(path)
    try:
        before = store.evaluate(config["run_id"], config["minimum_success"], config["request_timeout"])
        if before["case_id"] != config["case_id"] or before["kind"] != config["kind"]:
            raise LedgerConflict("Stored run does not match the selected protocol/case.")
        deadline = time.monotonic() + config["maximum_run_seconds"]
        for stream in ("canary", "control"):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                clients[stream].verify(store, config["run_id"], stream, config["request_timeout"], remaining)
            except TrafficFailure as error:
                emit({"event": "request_failed", "error_type": str(error)})
        result = store.evaluate(config["run_id"], config["minimum_success"], config["request_timeout"])
        emit(result)
        return result
    finally:
        store.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Offline validation by default; opt-in synthetic protocol traffic.")
    parser.add_argument("--config", required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--ledger")
    parser.add_argument("--manifest")
    parser.add_argument("--reconcile", action="store_true")
    parser.add_argument("--verify-existing", action="store_true")
    args = parser.parse_args(argv)
    clients = {}
    credential = None
    traffic_started = False
    try:
        config_path = Path(args.config)
        if config_path.stat().st_size > 65536:
            raise ValueError("Configuration exceeds the input budget.")
        config = validate_config(json.loads(config_path.read_text()))
        if sum((args.execute, args.reconcile, args.verify_existing)) > 1:
            raise ValueError("Choose new traffic, existing-cohort verification or read-only reconciliation.")
        if args.reconcile:
            if not args.ledger:
                raise ValueError("Existing ledger required.")
            store = Ledger(args.ledger, read_only=True)
            try:
                result = store.evaluate(config["run_id"], config["minimum_success"], config["request_timeout"])
            finally:
                store.close()
            print(json.dumps(result), flush=True)
            return {"Passed": 0, "Failed": 1, "Inconclusive": 2}[result["result"]]
        if not args.execute and not args.verify_existing:
            print(json.dumps({"result": "Passed", "evidence_scope": "configuration validation only",
                              "fault_actions_executed": False,
                              "explanation_zh": "仅配置格式检查通过；未连接服务、创建账本或运行测试。"}), flush=True)
            return 0
        if os.environ.get("ALLOW_REFERENCE_TRAFFIC") != "true" or not args.ledger or not args.manifest:
            raise ValueError("Explicit traffic opt-in, approved manifest and qualified durable ledger path required.")
        from campaign import load_json, authorize_traffic
        authorize_traffic(load_json(args.manifest), config, args.ledger)
        # Emit sanitized outcome errors instead of SDK traces containing private targets.
        for logger in ("azure", "msal"):
            logging.getLogger(logger).setLevel(logging.CRITICAL + 1)
        from azure.identity import WorkloadIdentityCredential
        credential = WorkloadIdentityCredential()
        for stream, target in config["streams"].items():
            clients[stream] = make_client(config["kind"], target, config["request_timeout"], credential)
        traffic_started = True
        runner = verify_existing if args.verify_existing else execute
        result = runner(config, args.ledger, clients, emit=lambda record: print(json.dumps(record), flush=True))
        return {"Passed": 0, "Failed": 1, "Inconclusive": 2}[result["result"]]
    except (ValueError, OSError, sqlite3.Error, ImportError) as error:
        verdict = "Inconclusive" if traffic_started else "Blocked"
        print(json.dumps({"result": verdict, "error_type": type(error).__name__, "stop_recommended": True,
                          "fault_actions_executed": False,
                          "explanation_zh": "配置、依赖或账本不可用；不重试写入，需检查并对账。"}), flush=True)
        return 2 if traffic_started else 3
    finally:
        for client in clients.values():
            client.close()
        if credential is not None:
            credential.close()


if __name__ == "__main__":
    sys.exit(main())
