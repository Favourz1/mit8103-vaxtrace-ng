\set ON_ERROR_STOP on
SET search_path = vaxtrace, public;

DO $$
DECLARE rejected boolean;
BEGIN
    rejected := false;
    BEGIN
        INSERT INTO lot (product_id, lot_code, expires_on)
        VALUES (1, 'LOT-000001', DATE '2027-12-31');
    EXCEPTION WHEN unique_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'duplicate lot was accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO stock_balance (facility_id, lot_id, on_hand_vials)
        VALUES (999999, 1, 1);
    EXCEPTION WHEN foreign_key_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'missing facility was accepted'; END IF;

    rejected := false;
    BEGIN
        UPDATE stock_balance SET on_hand_vials = -1
        WHERE facility_id = 1 AND lot_id = 1;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'negative stock was accepted'; END IF;

    rejected := false;
    BEGIN
        UPDATE stock_balance SET reserved_vials = on_hand_vials + 1
        WHERE facility_id = 1 AND lot_id = 1;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'over-reservation was accepted'; END IF;

    rejected := false;
    BEGIN
        UPDATE lot SET quality_status = 'quarantined', quality_note = NULL
        WHERE lot_id = 1;
    EXCEPTION WHEN check_violation THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'undocumented quarantine was accepted'; END IF;

    rejected := false;
    BEGIN
        DELETE FROM stock_movement WHERE movement_id = 1;
    EXCEPTION WHEN raise_exception THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'movement deletion was accepted'; END IF;

    RAISE NOTICE 'PASS: six duplicate, reference, quantity, status and audit tests';
END;
$$;
