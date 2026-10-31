\set ON_ERROR_STOP on
SET search_path = vaxtrace, public;
BEGIN;

DO $$
DECLARE
    rejected boolean;
    v_transfer_id bigint;
    v_completed_id bigint;
BEGIN
    SELECT transfer_id INTO v_completed_id FROM transfer
    WHERE request_key = 'demo-committed-transfer';
    IF v_completed_id IS NULL THEN RAISE EXCEPTION 'run transaction demo first'; END IF;
    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'CLINIC02', 'VX-001', 'LOT-000001',
                                 999, 'test-insufficient');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected OR EXISTS (SELECT 1 FROM transfer
        WHERE request_key = 'test-insufficient') THEN
        RAISE EXCEPTION 'insufficient stock was not atomic';
    END IF;

    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'CLINIC02', 'VX-001', 'LOT-000001',
                                 -1, 'test-negative');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'negative quantity was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'CLINIC02', 'VX-001', 'LOT-000001',
                                 1, 'demo-committed-transfer');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'duplicate request was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'CLINIC02', 'VX-019', 'LOT-000019',
                                 1, 'test-expired');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'expired lot was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'CLINIC02', 'VX-017', 'LOT-000037',
                                 1, 'test-quarantined');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'quarantined lot was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM request_transfer('DEPOT', 'DEPOT', 'VX-001', 'LOT-000001',
                                 1, 'test-same-facility');
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'same-endpoint transfer was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM dispatch_transfer(v_completed_id);
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'completed transfer was dispatched twice'; END IF;

    rejected := false;
    BEGIN
        PERFORM receive_transfer(v_completed_id);
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'completed transfer was received twice'; END IF;

    -- Quality status changes after reservation must block dispatch.
    v_transfer_id := request_transfer('DEPOT', 'CLINIC02', 'VX-001',
                                      'LOT-000001', 5, 'test-late-quarantine');
    UPDATE lot SET quality_status = 'quarantined',
        quality_note = 'Synthetic post-reservation hold' WHERE lot_id = 1;
    rejected := false;
    BEGIN
        PERFORM dispatch_transfer(v_transfer_id);
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected OR (SELECT transfer_status FROM transfer
        WHERE transfer_id = v_transfer_id) <> 'reserved' THEN
        RAISE EXCEPTION 'late quarantine did not block dispatch atomically';
    END IF;
    UPDATE lot SET quality_status = 'released', quality_note = NULL
    WHERE lot_id = 1;
    PERFORM cancel_transfer(v_transfer_id);

    IF EXISTS (
        SELECT 1 FROM stock_balance AS b
        JOIN (SELECT facility_id, lot_id,
                     sum(on_hand_delta) AS on_hand_total,
                     sum(reserved_delta) AS reserved_total
              FROM stock_movement GROUP BY facility_id, lot_id) AS m
        USING (facility_id, lot_id)
        WHERE b.on_hand_vials <> m.on_hand_total
           OR b.reserved_vials <> m.reserved_total
    ) THEN RAISE EXCEPTION 'ledger mismatch after adversarial cases'; END IF;
    RAISE NOTICE 'PASS: nine transfer validation, state and atomicity cases';
END;
$$;
ROLLBACK;
