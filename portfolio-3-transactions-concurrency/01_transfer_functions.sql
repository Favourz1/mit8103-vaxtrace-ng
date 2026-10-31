SET search_path = vaxtrace, public;

-- Every function is one atomic database statement. The caller controls COMMIT/ROLLBACK.
CREATE OR REPLACE FUNCTION vaxtrace.request_transfer(
    p_source_code text, p_destination_code text,
    p_product_sku text, p_lot_code text,
    p_quantity_vials integer, p_request_key text
) RETURNS bigint
LANGUAGE plpgsql SET search_path = vaxtrace, pg_temp AS $$
DECLARE
    v_source_id bigint;
    v_destination_id bigint;
    v_lot_id bigint;
    v_expiry date;
    v_status text;
    v_transfer_id bigint;
BEGIN
    IF p_quantity_vials IS NULL OR p_quantity_vials <= 0 THEN
        RAISE EXCEPTION 'quantity must be positive';
    END IF;
    IF p_request_key IS NULL OR btrim(p_request_key) = '' THEN
        RAISE EXCEPTION 'request key is required';
    END IF;
    IF EXISTS (SELECT 1 FROM transfer WHERE request_key = p_request_key) THEN
        RAISE EXCEPTION 'duplicate request key: %', p_request_key;
    END IF;

    SELECT facility_id INTO v_source_id FROM facility WHERE code = p_source_code;
    SELECT facility_id INTO v_destination_id FROM facility WHERE code = p_destination_code;
    IF v_source_id IS NULL OR v_destination_id IS NULL THEN
        RAISE EXCEPTION 'unknown source or destination facility';
    END IF;
    IF v_source_id = v_destination_id THEN
        RAISE EXCEPTION 'source and destination must differ';
    END IF;

    -- A quality-status change cannot race past this reservation transaction.
    SELECT l.lot_id, l.expires_on, l.quality_status
    INTO v_lot_id, v_expiry, v_status
    FROM lot AS l JOIN product AS p USING (product_id)
    WHERE p.sku = p_product_sku AND l.lot_code = p_lot_code
    FOR SHARE OF l;
    IF v_lot_id IS NULL THEN RAISE EXCEPTION 'unknown product/lot'; END IF;
    IF v_status <> 'released' OR v_expiry <= CURRENT_DATE THEN
        RAISE EXCEPTION 'lot % is not eligible for allocation', p_lot_code;
    END IF;

    -- The conditional UPDATE takes a row lock and rechecks the available quantity.
    UPDATE stock_balance
    SET reserved_vials = reserved_vials + p_quantity_vials
    WHERE facility_id = v_source_id AND lot_id = v_lot_id
      AND on_hand_vials - reserved_vials >= p_quantity_vials;
    IF NOT FOUND THEN RAISE EXCEPTION 'insufficient available stock'; END IF;

    INSERT INTO transfer (request_key, source_facility_id, destination_facility_id)
    VALUES (p_request_key, v_source_id, v_destination_id)
    RETURNING transfer_id INTO v_transfer_id;
    INSERT INTO transfer_line (transfer_id, lot_id, quantity_vials)
    VALUES (v_transfer_id, v_lot_id, p_quantity_vials);
    INSERT INTO stock_movement
        (facility_id, lot_id, transfer_id, movement_kind, reserved_delta, note)
    VALUES (v_source_id, v_lot_id, v_transfer_id, 'reservation', p_quantity_vials,
            'Reserved for transfer');
    RETURN v_transfer_id;
END;
$$;

CREATE OR REPLACE FUNCTION vaxtrace.dispatch_transfer(p_transfer_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path = vaxtrace, pg_temp AS $$
DECLARE
    v_transfer transfer%ROWTYPE;
    v_line record;
    v_status text;
    v_expiry date;
BEGIN
    SELECT * INTO v_transfer FROM transfer
    WHERE transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown transfer'; END IF;
    IF v_transfer.transfer_status <> 'reserved' THEN
        RAISE EXCEPTION 'transfer must be reserved before dispatch';
    END IF;

    FOR v_line IN SELECT * FROM transfer_line
                  WHERE transfer_id = p_transfer_id ORDER BY lot_id LOOP
        SELECT quality_status, expires_on INTO v_status, v_expiry
        FROM lot WHERE lot_id = v_line.lot_id FOR SHARE;
        IF v_status <> 'released' OR v_expiry <= CURRENT_DATE THEN
            RAISE EXCEPTION 'lot % is not eligible for dispatch', v_line.lot_id;
        END IF;
        UPDATE stock_balance
        SET on_hand_vials = on_hand_vials - v_line.quantity_vials,
            reserved_vials = reserved_vials - v_line.quantity_vials
        WHERE facility_id = v_transfer.source_facility_id
          AND lot_id = v_line.lot_id
          AND on_hand_vials >= v_line.quantity_vials
          AND reserved_vials >= v_line.quantity_vials;
        IF NOT FOUND THEN RAISE EXCEPTION 'reserved stock is missing'; END IF;
        INSERT INTO stock_movement
            (facility_id, lot_id, transfer_id, movement_kind,
             on_hand_delta, reserved_delta, note)
        VALUES (v_transfer.source_facility_id, v_line.lot_id, p_transfer_id,
                'dispatch', -v_line.quantity_vials, -v_line.quantity_vials,
                'Dispatched to destination');
    END LOOP;
    UPDATE transfer SET transfer_status = 'in_transit',
        dispatched_at = clock_timestamp()
    WHERE transfer_id = p_transfer_id;
END;
$$;

CREATE OR REPLACE FUNCTION vaxtrace.receive_transfer(p_transfer_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path = vaxtrace, pg_temp AS $$
DECLARE
    v_transfer transfer%ROWTYPE;
    v_line record;
BEGIN
    SELECT * INTO v_transfer FROM transfer
    WHERE transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown transfer'; END IF;
    IF v_transfer.transfer_status <> 'in_transit' THEN
        RAISE EXCEPTION 'transfer must be in transit before receipt';
    END IF;
    FOR v_line IN SELECT * FROM transfer_line
                  WHERE transfer_id = p_transfer_id ORDER BY lot_id LOOP
        INSERT INTO stock_balance (facility_id, lot_id, on_hand_vials)
        VALUES (v_transfer.destination_facility_id, v_line.lot_id,
                v_line.quantity_vials)
        ON CONFLICT (facility_id, lot_id) DO UPDATE
        SET on_hand_vials = stock_balance.on_hand_vials + EXCLUDED.on_hand_vials;
        INSERT INTO stock_movement
            (facility_id, lot_id, transfer_id, movement_kind,
             on_hand_delta, note)
        VALUES (v_transfer.destination_facility_id, v_line.lot_id,
                p_transfer_id, 'receipt', v_line.quantity_vials,
                'Received from source');
    END LOOP;
    UPDATE transfer SET transfer_status = 'received',
        received_at = clock_timestamp()
    WHERE transfer_id = p_transfer_id;
END;
$$;

CREATE OR REPLACE FUNCTION vaxtrace.cancel_transfer(p_transfer_id bigint)
RETURNS void LANGUAGE plpgsql SET search_path = vaxtrace, pg_temp AS $$
DECLARE
    v_transfer transfer%ROWTYPE;
    v_line record;
BEGIN
    SELECT * INTO v_transfer FROM transfer
    WHERE transfer_id = p_transfer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown transfer'; END IF;
    IF v_transfer.transfer_status <> 'reserved' THEN
        RAISE EXCEPTION 'only a reserved transfer can be cancelled';
    END IF;
    FOR v_line IN SELECT * FROM transfer_line
                  WHERE transfer_id = p_transfer_id ORDER BY lot_id LOOP
        UPDATE stock_balance
        SET reserved_vials = reserved_vials - v_line.quantity_vials
        WHERE facility_id = v_transfer.source_facility_id
          AND lot_id = v_line.lot_id
          AND reserved_vials >= v_line.quantity_vials;
        IF NOT FOUND THEN RAISE EXCEPTION 'reserved stock is missing'; END IF;
        INSERT INTO stock_movement
            (facility_id, lot_id, transfer_id, movement_kind,
             reserved_delta, note)
        VALUES (v_transfer.source_facility_id, v_line.lot_id,
                p_transfer_id, 'cancellation', -v_line.quantity_vials,
                'Reservation released');
    END LOOP;
    UPDATE transfer SET transfer_status = 'cancelled'
    WHERE transfer_id = p_transfer_id;
END;
$$;
