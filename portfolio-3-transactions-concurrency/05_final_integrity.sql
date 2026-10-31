\set ON_ERROR_STOP on
SET search_path = vaxtrace, public;

SELECT count(*) AS transfers, count(*) FILTER (WHERE transfer_status = 'received') AS received,
       count(*) FILTER (WHERE transfer_status = 'cancelled') AS cancelled
FROM transfer;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM stock_balance AS b
        JOIN (SELECT facility_id, lot_id,
                     sum(on_hand_delta) AS on_hand_total,
                     sum(reserved_delta) AS reserved_total
              FROM stock_movement GROUP BY facility_id, lot_id) AS m
        USING (facility_id, lot_id)
        WHERE b.on_hand_vials <> m.on_hand_total
           OR b.reserved_vials <> m.reserved_total
    ) THEN RAISE EXCEPTION 'balance/ledger mismatch after concurrent work'; END IF;
    IF EXISTS (SELECT 1 FROM stock_balance
               WHERE on_hand_vials < 0 OR reserved_vials < 0
                  OR reserved_vials > on_hand_vials) THEN
        RAISE EXCEPTION 'invalid balance after concurrent work';
    END IF;
    IF (SELECT transfer_status FROM transfer
        WHERE request_key = 'demo-committed-transfer') <> 'received' THEN
        RAISE EXCEPTION 'committed demo transfer not received';
    END IF;
    IF (SELECT count(*) FROM transfer
        WHERE request_key IN ('race-a', 'race-b')
          AND transfer_status = 'cancelled') <> 1 THEN
        RAISE EXCEPTION 'race winner not cancelled';
    END IF;
    IF (SELECT reserved_vials FROM stock_balance
        WHERE facility_id = 1 AND lot_id = 41) <> 0 THEN
        RAISE EXCEPTION 'race lot still reserved';
    END IF;
    RAISE NOTICE 'PASS: final balances, ledger, transfer states and race cleanup';
END;
$$;
