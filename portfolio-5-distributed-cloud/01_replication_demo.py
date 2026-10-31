"""Prove local PostgreSQL streaming replication and controlled replica lag."""

from __future__ import annotations

import argparse
import subprocess
import time
from pathlib import Path
from uuid import uuid4


REPO = Path(__file__).resolve().parents[1]
WORK = (REPO / "work").resolve()
DATABASE = "vaxtrace_verify"


def run(binary: Path, *args: str, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, timeout=180)
    if ok and result.returncode:
        raise RuntimeError(f"{binary.name} failed: {result.stderr.strip()}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, default=Path(r"C:\Program Files\PostgreSQL\18\bin"))
    parser.add_argument("--primary-port", type=int, default=55432)
    parser.add_argument("--standby-port", type=int, default=55433)
    parser.add_argument("--user", default="vaxtrace")
    parser.add_argument("--data-dir", type=Path, required=True,
                        help="new empty subdirectory of repository work/")
    args = parser.parse_args()
    data_dir = args.data_dir.resolve()
    if not data_dir.is_relative_to(WORK) or data_dir == WORK:
        raise ValueError("standby data must be in this repository's ignored work/ directory")
    if data_dir.exists() and any(data_dir.iterdir()):
        raise ValueError("standby data directory must not already contain files")
    if args.primary_port == args.standby_port:
        raise ValueError("primary and standby ports must differ")
    WORK.mkdir(exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)
    psql = args.pg_bin / "psql.exe"
    pg_basebackup = args.pg_bin / "pg_basebackup.exe"
    pg_ctl = args.pg_bin / "pg_ctl.exe"
    pg_isready = args.pg_bin / "pg_isready.exe"
    for binary in (psql, pg_basebackup, pg_ctl, pg_isready):
        if not binary.is_file():
            raise FileNotFoundError(binary)

    def sql(port: int, statement: str, *, check: bool = True) -> str:
        result = run(psql, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
                     "-p", str(port), "-U", args.user, "-d", DATABASE, "-c", statement,
                     ok=check)
        if not check:
            return f"exit={result.returncode}; error={result.stderr.strip()}"
        return result.stdout.strip()

    ready = run(pg_isready, "-h", "127.0.0.1", "-p", str(args.standby_port), ok=False)
    if ready.returncode == 0:
        raise RuntimeError("standby port is already occupied")
    assert sql(args.primary_port, "SHOW wal_level") in {"replica", "logical"}
    assert sql(args.primary_port, "SELECT count(*) FROM vaxtrace.stock_balance") == "3000"
    sql(args.primary_port, "CREATE TABLE IF NOT EXISTS vaxtrace.replication_probe "
        "(probe_id text PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT clock_timestamp())")

    print("PRIMARY stock balance rows: 3000")
    run(pg_basebackup, "-h", "127.0.0.1", "-p", str(args.primary_port), "-U", args.user,
        "-D", str(data_dir), "-X", "stream", "-R", "--checkpoint=fast")
    print("PASS base backup created with standby signal and primary connection settings")
    with (data_dir / "postgresql.auto.conf").open("a", encoding="utf-8") as config:
        config.write(f"\nport = {args.standby_port}\nlisten_addresses = '127.0.0.1'\n")
    started = False
    paused = False
    try:
        # A server started by pg_ctl can retain its parent's output handles on Windows.
        # DEVNULL lets pg_ctl return without waiting for the server process to exit.
        subprocess.run([str(pg_ctl), "-D", str(data_dir), "-l", str(WORK / "standby.log"),
                        "-w", "start"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       check=True, timeout=60)
        started = True
        for _ in range(30):
            if sql(args.primary_port, "SELECT count(*) FROM pg_stat_replication "
                   "WHERE state='streaming'") == "1":
                break
            time.sleep(0.5)
        else:
            raise AssertionError("primary did not report a streaming standby")
        print("PASS primary reports one streaming standby")
        assert sql(args.standby_port, "SELECT pg_is_in_recovery()") == "t"
        assert sql(args.standby_port, "SHOW transaction_read_only") == "on"
        assert sql(args.standby_port, "SELECT count(*) FROM vaxtrace.stock_balance") == "3000"
        print("PASS standby is read-only and contains 3000 stock balances")
        write_attempt = sql(args.standby_port,
            "INSERT INTO vaxtrace.replication_probe(probe_id) VALUES ('standby-write-must-fail')",
            check=False)
        assert not write_attempt.startswith("exit=0") and "read-only transaction" in write_attempt, write_attempt
        print("PASS standby rejected a write: read-only transaction")

        sql(args.standby_port, "SELECT pg_wal_replay_pause()")
        paused = True
        for _ in range(20):
            if sql(args.standby_port, "SELECT pg_get_wal_replay_pause_state()") == "paused":
                break
            time.sleep(0.2)
        else:
            raise AssertionError("standby replay did not pause")
        probe = f"probe-{uuid4()}"
        sql(args.primary_port, f"INSERT INTO vaxtrace.replication_probe(probe_id) VALUES ('{probe}')")
        assert sql(args.primary_port, f"SELECT count(*) FROM vaxtrace.replication_probe "
                   f"WHERE probe_id='{probe}'") == "1"
        assert sql(args.standby_port, f"SELECT count(*) FROM vaxtrace.replication_probe "
                   f"WHERE probe_id='{probe}'") == "0"
        print("PASS controlled lag: committed probe visible on primary, absent on paused standby")
        print("PRIMARY LSN", sql(args.primary_port, "SELECT pg_current_wal_lsn()"))
        print("STANDBY replay LSN while paused", sql(args.standby_port, "SELECT pg_last_wal_replay_lsn()"))
        sql(args.standby_port, "SELECT pg_wal_replay_resume()")
        paused = False
        for _ in range(60):
            if sql(args.standby_port, f"SELECT count(*) FROM vaxtrace.replication_probe "
                   f"WHERE probe_id='{probe}'") == "1":
                break
            time.sleep(0.5)
        else:
            raise AssertionError("standby did not replay committed probe")
        print("PASS standby caught up and returned the committed probe")
        print("STANDBY replay LSN after resume", sql(args.standby_port, "SELECT pg_last_wal_replay_lsn()"))
        print("PASS replication verification")
    finally:
        if started:
            if paused:
                sql(args.standby_port, "SELECT pg_wal_replay_resume()")
            run(pg_ctl, "-D", str(data_dir), "-m", "fast", "-w", "stop")


if __name__ == "__main__":
    main()
