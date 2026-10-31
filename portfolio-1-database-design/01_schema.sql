-- PostgreSQL 18. VaxTrace NG uses sealed vials as its stock unit.
-- Run in a disposable portfolio database: this script replaces the vaxtrace schema.
DROP SCHEMA IF EXISTS vaxtrace CASCADE;
CREATE SCHEMA vaxtrace;
SET search_path = vaxtrace, public;

CREATE TABLE facility (
    facility_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE CHECK (code ~ '^[A-Z0-9_-]{3,20}$'),
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    facility_type text NOT NULL CHECK (facility_type IN ('depot', 'clinic'))
);

CREATE TABLE product (
    product_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku text NOT NULL UNIQUE CHECK (sku ~ '^[A-Z0-9_-]{3,30}$'),
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    doses_per_vial integer NOT NULL CHECK (doses_per_vial > 0),
    min_storage_c numeric(5,2) NOT NULL,
    max_storage_c numeric(5,2) NOT NULL,
    CHECK (min_storage_c < max_storage_c)
);

CREATE TABLE lot (
    lot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES product(product_id),
    lot_code text NOT NULL CHECK (length(btrim(lot_code)) > 0),
    expires_on date NOT NULL,
    quality_status text NOT NULL DEFAULT 'released'
        CHECK (quality_status IN ('released', 'quarantined', 'disposed')),
    quality_note text,
    UNIQUE (product_id, lot_code),
    CHECK (quality_status = 'released' OR quality_note IS NOT NULL)
);

CREATE TABLE stock_balance (
    facility_id bigint NOT NULL REFERENCES facility(facility_id),
    lot_id bigint NOT NULL REFERENCES lot(lot_id),
    on_hand_vials integer NOT NULL DEFAULT 0 CHECK (on_hand_vials >= 0),
    reserved_vials integer NOT NULL DEFAULT 0 CHECK (reserved_vials >= 0),
    PRIMARY KEY (facility_id, lot_id),
    CHECK (reserved_vials <= on_hand_vials)
);

CREATE TABLE transfer (
    transfer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_key text NOT NULL UNIQUE CHECK (length(btrim(request_key)) > 0),
    source_facility_id bigint NOT NULL REFERENCES facility(facility_id),
    destination_facility_id bigint NOT NULL REFERENCES facility(facility_id),
    transfer_status text NOT NULL DEFAULT 'reserved'
        CHECK (transfer_status IN ('reserved', 'in_transit', 'received', 'cancelled')),
    requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    dispatched_at timestamptz,
    received_at timestamptz,
    CHECK (source_facility_id <> destination_facility_id),
    CHECK (
        (transfer_status = 'reserved' AND dispatched_at IS NULL AND received_at IS NULL)
        OR (transfer_status = 'cancelled' AND dispatched_at IS NULL AND received_at IS NULL)
        OR (transfer_status = 'in_transit' AND dispatched_at IS NOT NULL AND received_at IS NULL)
        OR (transfer_status = 'received' AND dispatched_at IS NOT NULL AND received_at IS NOT NULL)
    ),
    CHECK (dispatched_at IS NULL OR dispatched_at >= requested_at),
    CHECK (received_at IS NULL OR received_at >= dispatched_at)
);

CREATE TABLE transfer_line (
    transfer_id bigint NOT NULL REFERENCES transfer(transfer_id),
    lot_id bigint NOT NULL REFERENCES lot(lot_id),
    quantity_vials integer NOT NULL CHECK (quantity_vials > 0),
    PRIMARY KEY (transfer_id, lot_id)
);

CREATE TABLE stock_movement (
    movement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facility_id bigint NOT NULL REFERENCES facility(facility_id),
    lot_id bigint NOT NULL REFERENCES lot(lot_id),
    transfer_id bigint REFERENCES transfer(transfer_id),
    movement_kind text NOT NULL CHECK (movement_kind IN (
        'opening_receipt', 'historical_receipt', 'historical_issue',
        'reservation', 'dispatch', 'receipt', 'cancellation'
    )),
    on_hand_delta integer NOT NULL DEFAULT 0,
    reserved_delta integer NOT NULL DEFAULT 0,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    note text,
    CHECK (
        (movement_kind IN ('opening_receipt', 'historical_receipt', 'receipt')
            AND on_hand_delta > 0 AND reserved_delta = 0)
        OR (movement_kind = 'historical_issue'
            AND on_hand_delta < 0 AND reserved_delta = 0)
        OR (movement_kind = 'reservation'
            AND on_hand_delta = 0 AND reserved_delta > 0)
        OR (movement_kind = 'dispatch'
            AND on_hand_delta < 0 AND reserved_delta = on_hand_delta)
        OR (movement_kind = 'cancellation'
            AND on_hand_delta = 0 AND reserved_delta < 0)
    ),
    CHECK ((movement_kind IN ('reservation', 'dispatch', 'receipt', 'cancellation'))
        = (transfer_id IS NOT NULL))
);

-- The application records corrections through new movements, never by rewriting history.
CREATE FUNCTION reject_movement_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'stock_movement is append-only';
END;
$$;
CREATE TRIGGER stock_movement_append_only
BEFORE UPDATE OR DELETE ON stock_movement
FOR EACH ROW EXECUTE FUNCTION reject_movement_mutation();
