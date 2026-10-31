\set ON_ERROR_STOP on
\pset pager off
SET search_path = vaxtrace, public;
SELECT current_setting('server_version') AS postgres_version,
       (SELECT count(*) FROM stock_movement) AS movement_rows,
       (SELECT count(*) FROM stock_balance) AS balance_rows;

\echo PLAN A: latest movements for LOT-000777
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.movement_id, m.movement_kind, m.on_hand_delta, m.occurred_at
FROM stock_movement AS m
JOIN lot AS l USING (lot_id)
JOIN product AS p USING (product_id)
WHERE p.sku = 'VX-017' AND l.lot_code = 'LOT-000777'
ORDER BY m.occurred_at DESC, m.movement_id DESC
LIMIT 50;

\echo PLAN B: latest movements for CLINIC07
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.movement_id, m.lot_id, m.movement_kind, m.occurred_at
FROM stock_movement AS m
JOIN facility AS f USING (facility_id)
WHERE f.code = 'CLINIC07'
ORDER BY m.occurred_at DESC, m.movement_id DESC
LIMIT 50;
