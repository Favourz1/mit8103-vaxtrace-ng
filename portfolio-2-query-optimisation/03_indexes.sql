SET search_path = vaxtrace, public;
-- These indexes support the named-lot and named-facility recency queries.
-- movement_id breaks ties when an event has the same timestamp.
CREATE INDEX stock_movement_lot_recent_idx
    ON stock_movement (lot_id, occurred_at DESC, movement_id DESC);
CREATE INDEX stock_movement_facility_recent_idx
    ON stock_movement (facility_id, occurred_at DESC, movement_id DESC);
ANALYZE stock_movement;
