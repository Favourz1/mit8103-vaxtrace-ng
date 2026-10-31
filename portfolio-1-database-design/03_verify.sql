\set ON_ERROR_STOP on
SET search_path = vaxtrace, public;

-- Expected: 13 facilities, 20 products, 1000 lots, 3000 balances,
-- 203000 movements (3000 opening receipts plus 100000 historical pairs).
SELECT 'facility' AS entity, count(*) AS actual FROM facility
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'lot', count(*) FROM lot
UNION ALL SELECT 'stock_balance', count(*) FROM stock_balance
UNION ALL SELECT 'stock_movement', count(*) FROM stock_movement;

-- Expected: zero rows. The materialised balance must equal the movement ledger.
SELECT b.facility_id, b.lot_id, b.on_hand_vials, b.reserved_vials,
       m.on_hand_total, m.reserved_total
FROM stock_balance AS b
JOIN (
    SELECT facility_id, lot_id,
           sum(on_hand_delta) AS on_hand_total,
           sum(reserved_delta) AS reserved_total
    FROM stock_movement GROUP BY facility_id, lot_id
) AS m USING (facility_id, lot_id)
WHERE b.on_hand_vials <> m.on_hand_total
   OR b.reserved_vials <> m.reserved_total;

-- Expected: zero rows. No stock balance exists without a movement history.
SELECT b.facility_id, b.lot_id
FROM stock_balance AS b
WHERE NOT EXISTS (
    SELECT 1 FROM stock_movement AS m
    WHERE m.facility_id = b.facility_id AND m.lot_id = b.lot_id
);
