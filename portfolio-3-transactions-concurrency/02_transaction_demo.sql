\set ON_ERROR_STOP on
\pset pager off
SET search_path = vaxtrace, public;

\echo BEFORE: depot and CLINIC01 balances for LOT-000001
SELECT f.code, b.on_hand_vials, b.reserved_vials
FROM stock_balance AS b JOIN facility AS f USING (facility_id)
WHERE b.lot_id = 1 AND f.code IN ('DEPOT', 'CLINIC01') ORDER BY f.code;

\echo COMMIT 1: reserve 10 vials atomically
BEGIN;
SELECT request_transfer('DEPOT', 'CLINIC01', 'VX-001', 'LOT-000001',
                        10, 'demo-committed-transfer') AS demo_transfer_id \gset
COMMIT;
SELECT transfer_id, request_key, transfer_status FROM transfer
WHERE transfer_id = :demo_transfer_id;

\echo COMMIT 2: dispatch; source on-hand and reservation fall together
BEGIN;
SELECT dispatch_transfer(:demo_transfer_id);
COMMIT;

\echo COMMIT 3: receive; destination on-hand rises
BEGIN;
SELECT receive_transfer(:demo_transfer_id);
COMMIT;

\echo AFTER: transfer and stock movement evidence
SELECT transfer_id, transfer_status,
       dispatched_at IS NOT NULL AS was_dispatched,
       received_at IS NOT NULL AS was_received
FROM transfer WHERE transfer_id = :demo_transfer_id;
SELECT f.code, b.on_hand_vials, b.reserved_vials
FROM stock_balance AS b JOIN facility AS f USING (facility_id)
WHERE b.lot_id = 1 AND f.code IN ('DEPOT', 'CLINIC01') ORDER BY f.code;
SELECT movement_kind, on_hand_delta, reserved_delta
FROM stock_movement WHERE transfer_id = :demo_transfer_id
ORDER BY movement_id;

\echo ROLLBACK: a reservation is explicitly undone
BEGIN;
SELECT request_transfer('DEPOT', 'CLINIC01', 'VX-001', 'LOT-000001',
                        30, 'demo-rolled-back-transfer');
ROLLBACK;
SELECT count(*) AS rolled_back_transfers FROM transfer
WHERE request_key = 'demo-rolled-back-transfer';

DO $$
BEGIN
    IF (SELECT on_hand_vials FROM stock_balance
        WHERE facility_id = 1 AND lot_id = 1) <> 90 THEN
        RAISE EXCEPTION 'source balance after commit/rollback is wrong';
    END IF;
    IF (SELECT on_hand_vials FROM stock_balance
        WHERE facility_id = 2 AND lot_id = 1) <> 35 THEN
        RAISE EXCEPTION 'destination balance after receipt is wrong';
    END IF;
    IF (SELECT count(*) FROM transfer
        WHERE request_key = 'demo-rolled-back-transfer') <> 0 THEN
        RAISE EXCEPTION 'rolled-back transfer persisted';
    END IF;
    IF EXISTS (
        SELECT 1 FROM stock_balance AS b
        JOIN (SELECT facility_id, lot_id,
                     sum(on_hand_delta) AS on_hand_total,
                     sum(reserved_delta) AS reserved_total
              FROM stock_movement GROUP BY facility_id, lot_id) AS m
        USING (facility_id, lot_id)
        WHERE b.on_hand_vials <> m.on_hand_total
           OR b.reserved_vials <> m.reserved_total
    ) THEN RAISE EXCEPTION 'ledger does not reconcile'; END IF;
    RAISE NOTICE 'PASS: commit, rollback, receipt and ledger reconciliation';
END;
$$;
