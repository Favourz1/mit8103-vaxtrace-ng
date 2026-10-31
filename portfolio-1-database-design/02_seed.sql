-- Deterministic synthetic dataset. All identities, lot codes and dates are fictional.
-- Run once after 01_schema.sql. Reference date: 2026-10-31.
BEGIN;
SET LOCAL search_path = vaxtrace, public;

INSERT INTO facility (code, name, facility_type)
VALUES ('DEPOT', 'VaxTrace regional depot', 'depot');

INSERT INTO facility (code, name, facility_type)
SELECT 'CLINIC' || lpad(n::text, 2, '0'),
       'Fictional clinic ' || lpad(n::text, 2, '0'), 'clinic'
FROM generate_series(1, 12) AS n
ORDER BY n;

INSERT INTO product (sku, name, doses_per_vial, min_storage_c, max_storage_c)
SELECT 'VX-' || lpad(n::text, 3, '0'),
       'Fictional vaccine product ' || lpad(n::text, 3, '0'),
       CASE WHEN n % 3 = 0 THEN 5 ELSE 10 END,
       CASE WHEN n % 5 = 0 THEN -25.00 ELSE 2.00 END,
       CASE WHEN n % 5 = 0 THEN -15.00 ELSE 8.00 END
FROM generate_series(1, 20) AS n
ORDER BY n;

INSERT INTO lot (product_id, lot_code, expires_on, quality_status, quality_note)
SELECT ((n - 1) % 20) + 1,
       'LOT-' || lpad(n::text, 6, '0'),
       CASE WHEN n % 19 = 0 THEN DATE '2026-10-15'
            ELSE DATE '2027-01-01' + (n % 300) END,
       CASE WHEN n % 101 = 0 THEN 'disposed'
            WHEN n % 37 = 0 THEN 'quarantined'
            ELSE 'released' END,
       CASE WHEN n % 101 = 0 THEN 'Synthetic disposal case'
            WHEN n % 37 = 0 THEN 'Synthetic excursion review pending'
            ELSE NULL END
FROM generate_series(1, 1000) AS n
ORDER BY n;

-- Every lot has depot stock and stock at two distinct fictional clinics.
INSERT INTO stock_balance (facility_id, lot_id, on_hand_vials, reserved_vials)
SELECT f.facility_id, l.lot_id,
       CASE WHEN f.facility_type = 'depot' THEN 100 ELSE 25 END, 0
FROM lot AS l
JOIN facility AS f ON f.code = 'DEPOT'
    OR f.code IN (
        'CLINIC' || lpad((((l.lot_id - 1) % 12) + 1)::text, 2, '0'),
        'CLINIC' || lpad((((l.lot_id + 4) % 12) + 1)::text, 2, '0')
    );

INSERT INTO stock_movement
    (facility_id, lot_id, movement_kind, on_hand_delta, reserved_delta, occurred_at, note)
SELECT facility_id, lot_id, 'opening_receipt', on_hand_vials, 0,
       TIMESTAMPTZ '2026-01-01 00:00:00+01', 'Synthetic opening stock'
FROM stock_balance;

-- Historical receipt/issue pairs net to zero and preserve the current balance.
-- They provide a realistic-sized append-only audit workload for query analysis.
WITH pairs AS (
    SELECT n,
           (((n - 1) % 3000) / 3)::bigint + 1 AS lot_id,
           CASE ((n - 1) % 3)
               WHEN 0 THEN 'DEPOT'
               WHEN 1 THEN 'CLINIC' || lpad((((((n - 1) % 3000) / 3) % 12) + 1)::text, 2, '0')
               ELSE 'CLINIC' || lpad((((((n - 1) % 3000) / 3) + 5) % 12 + 1)::text, 2, '0')
           END AS facility_code
    FROM generate_series(1, 100000) AS n
)
INSERT INTO stock_movement
    (facility_id, lot_id, movement_kind, on_hand_delta, reserved_delta, occurred_at, note)
SELECT f.facility_id, p.lot_id,
       v.kind, v.delta, 0,
       TIMESTAMPTZ '2026-02-01 00:00:00+01'
           + p.n * INTERVAL '30 seconds' + v.offset_time,
       'Synthetic historical cycle ' || p.n
FROM pairs AS p
JOIN facility AS f ON f.code = p.facility_code
CROSS JOIN LATERAL (VALUES
    ('historical_receipt', 1, INTERVAL '0 seconds'),
    ('historical_issue', -1, INTERVAL '1 second')
) AS v(kind, delta, offset_time);

COMMIT;
