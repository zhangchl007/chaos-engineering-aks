import hashlib
import math
import os
from pathlib import Path
import re
import sqlite3
import threading
import uuid


class LedgerConflict(ValueError):
    pass


class Ledger:
    def __init__(self, path, read_only=False):
        self.read_only = read_only
        self.lock = threading.RLock()
        path = Path(path)
        if path.is_symlink():
            raise OSError("Ledger symlinks are not supported.")
        if read_only:
            if not path.is_file():
                raise OSError("Existing durable ledger required.")
        else:
            descriptor = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            os.close(descriptor)
        mode = "ro" if read_only else "rw"
        self.connection = sqlite3.connect(path.resolve().as_uri() + "?mode=" + mode,
                                          uri=True, timeout=2, check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        version = self.connection.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1) or (read_only and version != 1):
            self.connection.close()
            raise LedgerConflict("Unsupported ledger schema.")
        if not read_only:
            self.connection.execute("PRAGMA journal_mode=WAL")
            self.connection.execute("PRAGMA synchronous=FULL")
            self.connection.execute("PRAGMA foreign_keys=ON")
            self.connection.executescript("""
                CREATE TABLE IF NOT EXISTS runs (
                    run_id TEXT PRIMARY KEY, case_id TEXT NOT NULL, phase TEXT NOT NULL,
                    planned INTEGER NOT NULL, kind TEXT NOT NULL, finished INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS operations (
                    operation_id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES runs(run_id),
                    stream TEXT NOT NULL, sequence INTEGER NOT NULL, payload_hash TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT 'pending', latency REAL,
                    error_type TEXT, conflict INTEGER NOT NULL DEFAULT 0,
                    UNIQUE(run_id, stream, sequence)
                );
                CREATE TABLE IF NOT EXISTS effects (
                    operation_id TEXT PRIMARY KEY REFERENCES operations(operation_id),
                    payload_hash TEXT NOT NULL, delivery_attempts INTEGER NOT NULL DEFAULT 1,
                    settled INTEGER NOT NULL DEFAULT 0
                );
                PRAGMA user_version=1;
            """)

    def close(self):
        self.connection.close()

    def _write(self, sql, parameters=()):
        if self.read_only:
            raise LedgerConflict("Read-only reconciliation cannot change the ledger.")
        with self.lock, self.connection:
            try:
                return self.connection.execute(sql, parameters).rowcount
            except sqlite3.IntegrityError as error:
                raise LedgerConflict("Ledger identity or state conflict.") from error

    def _run(self, run_id):
        with self.lock:
            row = self.connection.execute("SELECT * FROM runs WHERE run_id=?", (run_id,)).fetchone()
        if row is None:
            raise LedgerConflict("Unknown run.")
        return dict(row)

    def start_run(self, run_id, case_id, phase, planned, kind):
        if (not isinstance(run_id, str) or not re.fullmatch("[a-f0-9]{32}", run_id) or
                phase not in ("baseline", "exposure", "recovery") or kind not in ("blob", "servicebus") or
                type(planned) is not int or not 1 <= planned <= 1000):
            raise LedgerConflict("Invalid run identity or operation budget.")
        self._write("INSERT INTO runs(run_id,case_id,phase,planned,kind) VALUES(?,?,?,?,?)",
                    (run_id, case_id, phase, planned, kind))

    def intent(self, run_id, stream, sequence, payload):
        run = self._run(run_id)
        if (run["finished"] or stream not in ("control", "canary") or type(sequence) is not int or
                not 0 <= sequence < run["planned"] or not isinstance(payload, bytes) or not 1 <= len(payload) <= 4096):
            raise LedgerConflict("Invalid operation intent.")
        operation_id = uuid.uuid4().hex
        self._write("INSERT INTO operations(operation_id,run_id,stream,sequence,payload_hash) VALUES(?,?,?,?,?)",
                    (operation_id, run_id, stream, sequence, hashlib.sha256(payload).hexdigest()))
        return operation_id

    def outcome(self, operation_id, state, latency, error_type=None):
        if (state not in ("acknowledged", "unknown") or type(latency) not in (int, float) or
                not 0 <= latency <= 3600 or not math.isfinite(latency)):
            raise LedgerConflict("Invalid operation outcome.")
        changed = self._write("UPDATE operations SET state=?,latency=?,error_type=? "
                              "WHERE operation_id=? AND state='pending'",
                              (state, latency, error_type, operation_id))
        if changed != 1:
            raise LedgerConflict("Operation outcome already recorded or unknown.")

    def effect(self, operation_id, payload, settled=False):
        if not isinstance(payload, bytes) or len(payload) > 4097 or type(settled) is not bool:
            raise LedgerConflict("Invalid effect evidence.")
        actual_hash = hashlib.sha256(payload).hexdigest()
        with self.lock:
            row = self.connection.execute("SELECT payload_hash FROM operations WHERE operation_id=?",
                                          (operation_id,)).fetchone()
            if row is None:
                raise LedgerConflict("Unexpected operation; do not settle unrelated messages.")
            if row["payload_hash"] != actual_hash:
                self._write("UPDATE operations SET conflict=1 WHERE operation_id=?", (operation_id,))
                return False
            self._write(
                "INSERT INTO effects(operation_id,payload_hash,settled) VALUES(?,?,?) "
                "ON CONFLICT(operation_id) DO UPDATE SET delivery_attempts=delivery_attempts+1,"
                "settled=max(effects.settled,excluded.settled)", (operation_id, actual_hash, int(settled)))
        return True

    def settle(self, operation_id):
        if self._write("UPDATE effects SET settled=1 WHERE operation_id=?", (operation_id,)) != 1:
            raise LedgerConflict("Effect must be committed before message settlement.")

    def finish_run(self, run_id):
        if self._write("UPDATE runs SET finished=1 WHERE run_id=? AND finished=0", (run_id,)) != 1:
            raise LedgerConflict("Run is unknown or already finished.")

    def operations(self, run_id, stream):
        self._run(run_id)
        with self.lock:
            rows = self.connection.execute(
                "SELECT o.*,CASE WHEN e.operation_id IS NULL THEN 0 ELSE 1 END AS effect_count,"
                "coalesce(e.delivery_attempts,0) AS delivery_attempts,coalesce(e.settled,0) AS settled "
                "FROM operations o LEFT JOIN effects e ON e.operation_id=o.operation_id "
                "WHERE o.run_id=? AND o.stream=? ORDER BY sequence", (run_id, stream)).fetchall()
        return [dict(row) for row in rows]

    def evaluate(self, run_id, minimum_success, request_timeout):
        run = self._run(run_id)
        if (type(minimum_success) not in (int, float) or not 0 <= minimum_success <= 1 or
                type(request_timeout) not in (int, float) or not 0 < request_timeout <= 10):
            raise LedgerConflict("Invalid reconciliation thresholds.")
        incomplete = not run["finished"]
        conflicts = 0
        streams = {}
        for stream in ("canary", "control"):
            rows = self.operations(run_id, stream)
            conflicts += sum(row["conflict"] for row in rows)
            incomplete |= (len(rows) != run["planned"] or any(
                row["state"] == "pending" or not row["effect_count"] or
                (run["kind"] == "servicebus" and not row["settled"]) for row in rows))
            successful = sum(row["state"] == "acknowledged" and row["latency"] <= request_timeout for row in rows)
            latencies = sorted(row["latency"] for row in rows if row["latency"] is not None)
            streams[stream] = {
                "operations": len(rows),
                "acknowledged": sum(row["state"] == "acknowledged" for row in rows),
                "unknown": sum(row["state"] == "unknown" for row in rows),
                "resolved_unknown": sum(row["state"] == "unknown" and row["effect_count"] == 1 for row in rows),
                "verified_effects": sum(row["effect_count"] for row in rows),
                "delivery_attempts": sum(row["delivery_attempts"] for row in rows),
                "success_rate": successful / run["planned"],
                "p95_seconds": latencies[math.ceil(len(latencies) * 0.95) - 1] if latencies else None,
                "p99_seconds": latencies[math.ceil(len(latencies) * 0.99) - 1] if latencies else None,
            }
        below_threshold = any(stream["success_rate"] < minimum_success for stream in streams.values())
        result = "Failed" if conflicts else "Inconclusive" if incomplete else "Failed" if below_threshold else "Passed"
        return {
            "result": result, "run_id": run_id, "case_id": run["case_id"], "phase": run["phase"], "kind": run["kind"],
            "streams": streams, "conflicting_effects": conflicts, "stop_recommended": result != "Passed",
            "fault_actions_executed": False,
            "evidence_scope": "Synthetic reference protocol acceptance and ledger reconciliation; not full application or fault qualification",
            "explanation_zh": {
                "Passed": "仅合成协议参考流及独立账本对账通过；不代表完整业务或故障测试通过。",
                "Failed": "数据内容冲突或请求成功率未达到约定阈值，应停止并检查。",
                "Inconclusive": "运行、操作结果、数据效果或消息确认不完整，不能判定通过。",
            }[result],
        }
