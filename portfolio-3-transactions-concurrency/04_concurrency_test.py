"""Reproduce two concurrent reservations for one 100-vial depot lot.

Uses separate psql processes, so each contender has an independent database
session and transaction. The successful transaction holds its lock for 1.5 s
to force overlap. Run only after a clean rebuild and transaction demo.
"""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
import argparse
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--psql", default=r"C:\Program Files\PostgreSQL\18\bin\psql.exe")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default="55432")
    parser.add_argument("--database", default="vaxtrace_dev")
    parser.add_argument("--user", default="vaxtrace")
    args = parser.parse_args()
    if not Path(args.psql).is_file():
        raise SystemExit(f"psql not found: {args.psql}")

    base = [args.psql, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
            "-h", args.host, "-p", args.port, "-U", args.user,
            "-d", args.database]

    def sql(query: str) -> str:
        result = subprocess.run(base + ["-c", query], capture_output=True,
                                text=True, encoding="utf-8")
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout.strip()

    before = sql("SELECT on_hand_vials || '|' || reserved_vials "
                 "FROM vaxtrace.stock_balance WHERE facility_id=1 AND lot_id=41")
    assert before == "100|0", f"expected clean lot 41, got {before}"
    print(f"Before race, depot lot 41: {before}")

    barrier = Barrier(2)

    def contender(key: str) -> tuple[str, int, str, str]:
        statement = (
            "BEGIN; SELECT vaxtrace.request_transfer('DEPOT','CLINIC03',"
            "'VX-001','LOT-000041',70,'" + key + "'); "
            "SELECT pg_sleep(1.5); COMMIT;"
        )
        barrier.wait()
        result = subprocess.run(base + ["-c", statement], capture_output=True,
                                text=True, encoding="utf-8")
        return key, result.returncode, result.stdout.strip(), result.stderr.strip()

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(contender, key) for key in ("race-a", "race-b")]
        results = [future.result() for future in futures]

    for key, code, stdout, stderr in results:
        print(f"{key}: exit={code}; stdout={stdout!r}; stderr={stderr!r}")
    winners = [key for key, code, _, _ in results if code == 0]
    assert len(winners) == 1, f"expected one winner, got {winners}"
    assert any("insufficient available stock" in stderr for _, code, _, stderr
               in results if code != 0), "loser did not fail on stock limit"

    during = sql("SELECT on_hand_vials || '|' || reserved_vials "
                 "FROM vaxtrace.stock_balance WHERE facility_id=1 AND lot_id=41")
    assert during == "100|70", f"oversell or missing reservation: {during}"
    count = sql("SELECT count(*) FROM vaxtrace.transfer "
                "WHERE request_key IN ('race-a','race-b')")
    assert count == "1", f"expected one committed transfer, got {count}"
    print(f"After race, depot lot 41: {during}; committed transfers: {count}")

    winner = winners[0]
    sql("SELECT vaxtrace.cancel_transfer(transfer_id) FROM vaxtrace.transfer "
        f"WHERE request_key = '{winner}'")
    after = sql("SELECT on_hand_vials || '|' || reserved_vials "
                "FROM vaxtrace.stock_balance WHERE facility_id=1 AND lot_id=41")
    assert after == "100|0", f"cancellation did not restore availability: {after}"
    print(f"After cancellation, depot lot 41: {after}")
    print("PASS: concurrent sessions cannot reserve 140 vials from 100")


if __name__ == "__main__":
    main()
