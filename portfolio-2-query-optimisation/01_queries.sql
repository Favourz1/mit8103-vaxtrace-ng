\set ON_ERROR_STOP on
\pset pager off
SET search_path = vaxtrace, public;

\echo Q1: eligible lots for product VX-001 at the depot, as of 2026-10-31
SELECT l.lot_code, l.expires_on,
       b.on_hand_vials - b.reserved_vials AS available_vials
FROM stock_balance AS b
JOIN facility AS f USING (facility_id)
JOIN lot AS l USING (lot_id)
JOIN product AS p USING (product_id)
WHERE f.code = 'DEPOT' AND p.sku = 'VX-001'
  AND l.quality_status = 'released'
  AND l.expires_on > DATE '2026-10-31'
  AND b.on_hand_vials > b.reserved_vials
ORDER BY l.expires_on, l.lot_code
LIMIT 10;

\echo Q2: available stock by clinic for product VX-001
SELECT f.code AS clinic, sum(b.on_hand_vials - b.reserved_vials) AS available_vials
FROM stock_balance AS b
JOIN facility AS f USING (facility_id)
JOIN lot AS l USING (lot_id)
JOIN product AS p USING (product_id)
WHERE f.facility_type = 'clinic' AND p.sku = 'VX-001'
  AND l.quality_status = 'released'
  AND l.expires_on > DATE '2026-10-31'
GROUP BY f.code ORDER BY f.code;

\echo Q3: latest 50 movements for a named lot
SELECT m.movement_id, m.movement_kind, m.on_hand_delta, m.occurred_at
FROM stock_movement AS m
WHERE m.lot_id = (
    SELECT l.lot_id FROM lot AS l
    JOIN product AS p USING (product_id)
    WHERE p.sku = 'VX-017' AND l.lot_code = 'LOT-000777'
)
ORDER BY m.occurred_at DESC, m.movement_id DESC
LIMIT 50;

\echo Q4: latest 50 movements at a named clinic
SELECT m.movement_id, m.lot_id, m.movement_kind, m.occurred_at
FROM stock_movement AS m
WHERE m.facility_id = (
    SELECT facility_id FROM facility WHERE code = 'CLINIC07'
)
ORDER BY m.occurred_at DESC, m.movement_id DESC
LIMIT 50;

\echo Q5: transfer state counts
SELECT transfer_status, count(*) AS transfer_count
FROM transfer GROUP BY transfer_status ORDER BY transfer_status;
