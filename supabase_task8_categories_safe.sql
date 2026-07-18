-- ══════════════════════════════════════════════════════════════
-- Task 8 (SAFE v2): sub_category column with additive-only updates.
-- Run once in the Supabase SQL editor. Idempotent.
--
-- SAFETY GUARANTEES:
--   * NO DELETE, NO TRUNCATE, NO INSERT — cannot remove or add rows.
--   * UPDATE only sets sub_category, and only WHERE sub_category IS NULL,
--     so already-populated values are preserved.
--   * If a SKU listed here isn't in the DB, the UPDATE silently no-ops.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE products ADD COLUMN IF NOT EXISTS sub_category text;
CREATE INDEX IF NOT EXISTS products_sub_category_idx ON products (sub_category);

-- Baskets & Organizers (10)
UPDATE products SET sub_category='Baskets & Organizers'
WHERE sku IN ('BBSHP93-095H', 'TVBAG472819', 'TV165-480-5', 'LR/481-1', 'LR/298-3', 'TSAD19210', 'TSAD19210B', 'SHELFHP25-764', '11-4849', 'HD6198')
  AND (sub_category IS NULL OR sub_category = '');

-- Bowls (6)
UPDATE products SET sub_category='Bowls'
WHERE sku IN ('GDF/TB/S11CM', 'GDF/TB/OD30.5', 'CSG/PTK/22R070', 'RST-3/4', 'MM 8538 / cs0008538', 'ZN-CASS-01')
  AND (sub_category IS NULL OR sub_category = '');

-- Coffee & Tea Sets (8)
UPDATE products SET sub_category='Coffee & Tea Sets'
WHERE sku IN ('B-25093HY', '250897N-RX', 'D11866', 'YCS 755-3S / CS0011968', 'YCS 776-12 / CS0012051', 'YCS 776-8 / CS0012048', 'S-18G2912LEX', 'ZN-TEAPOT-01')
  AND (sub_category IS NULL OR sub_category = '');

-- Cutlery (9)
UPDATE products SET sub_category='Cutlery'
WHERE sku IN ('TSG/MK', 'TSG/MF', 'TSG/MS', 'LEX-6970837083788', 'TSG/TS', 'LEX-6910231330057', 'LEX-6988110070820', 'LEX-6970817081780', 'ZN-KNIFE-05')
  AND (sub_category IS NULL OR sub_category = '');

-- Drinkware (1)
UPDATE products SET sub_category='Drinkware'
WHERE sku IN ('CGT/T/BL/DG06-500')
  AND (sub_category IS NULL OR sub_category = '');

-- Fridge Organizers (7)
UPDATE products SET sub_category='Fridge Organizers'
WHERE sku IN ('TEM/EP-610', 'TEM/EP-611', 'TEM/EP-612', 'TEM/EP-615', 'TEM/EP-616', 'TEM/EP-617', 'TEM/EP-632')
  AND (sub_category IS NULL OR sub_category = '');

-- Glassware (8)
UPDATE products SET sub_category='Glassware'
WHERE sku IN ('GCM6', 'GTM250-9', 'GTM350-12', 'GTMCCBW3', 'GTMCCBW7', 'GTMCF05-250', '5313G', '11969')
  AND (sub_category IS NULL OR sub_category = '');

-- Jugs & Bottles (6)
UPDATE products SET sub_category='Jugs & Bottles'
WHERE sku IN ('GTBC1000', 'GTK10', 'GTK11', 'THP/CAPDP', '475-2PN', '475-1PN')
  AND (sub_category IS NULL OR sub_category = '');

-- Kitchen Tools (10)
UPDATE products SET sub_category='Kitchen Tools'
WHERE sku IN ('THM/LFX042', 'TVRBPW', 'CZJ/18000', 'TFL/SB/2777', 'YCS 721-7B / CS0011893', 'HD-6958000171534', '6-284', 'ZN-SPICE-12', 'ZN-SPICE-09', 'ZN-SOAP-01')
  AND (sub_category IS NULL OR sub_category = '');

-- Lamps (1)
UPDATE products SET sub_category='Lamps'
WHERE sku IN ('Nordic table lamp')
  AND (sub_category IS NULL OR sub_category = '');

-- Mirrors (1)
UPDATE products SET sub_category='Mirrors'
WHERE sku IN ('HD1662')
  AND (sub_category IS NULL OR sub_category = '');

-- Mugs (11)
UPDATE products SET sub_category='Mugs'
WHERE sku IN ('MUGSDM-1753', 'MUGSY9057', 'MUGTX5683', 'MUGSY8081', 'MUGSDM001-1802', 'GDF/TB/M37CL', 'GDF/TCG/M500', 'GDF/TEXTRA/M16OZ', 'GDF/TG/M37CL', 'ABC11839', '420-23KX')
  AND (sub_category IS NULL OR sub_category = '');

-- Plates & Dinnerware (6)
UPDATE products SET sub_category='Plates & Dinnerware'
WHERE sku IN ('GDF/TCG/P27', 'GDF/TCG/P23', 'YCS 776-4 / CS0012045', '027iwz', 'HD3123', 'YCS 721-1A / CS0011880')
  AND (sub_category IS NULL OR sub_category = '');

-- Storage & Jars (34)
UPDATE products SET sub_category='Storage & Jars'
WHERE sku IN ('TAK/511', 'TAK/509', 'GDF/VIN/SM550', 'GDF/VIN/SM850', 'GDF/VIN/SM1800C', 'WRB/498-6', 'GTGCSQ200', 'TDN/30111', 'TDN/30113', 'TDN/30114', 'TDN/30115', 'TDN/32007', 'TDN/32008', 'TDN/32009', 'TEM/EP-145', 'TEM/EP-146', 'TEM/EP-147', 'TEM/EP-148', 'TEM/EP-155', 'TEM/EP-156', 'TEM/EP-157', 'TEM/EP-160', 'TEM/EP-161', 'TEM/EP-163', 'CZJ/TS78', 'AP760767', 'TFL/SB/6898', 'TFL/SB/6911', 'TFL/SB/3699', 'TFL/SB/3712', 'TFL/FSQ/0698', 'TFL/FSQ/0711', 'TFL/FSQ/0735', 'TFL/FSQ/9936')
  AND (sub_category IS NULL OR sub_category = '');

-- Tissue Boxes (7)
UPDATE products SET sub_category='Tissue Boxes'
WHERE sku IN ('HD71640', '10442', 'HD-6958000171355', 'YCS 759-4 / CS0012192', '11541', '11540', 'tukomaz')
  AND (sub_category IS NULL OR sub_category = '');

-- Trays (6)
UPDATE products SET sub_category='Trays'
WHERE sku IN ('YCS 730-1A / CS0011896', 'YCS 664-3G / CS0011151', 'DH-03234', 'DH-03238', 'DH-03229', 'DH-03214')
  AND (sub_category IS NULL OR sub_category = '');

-- Vases & Decor (6)
UPDATE products SET sub_category='Vases & Decor'
WHERE sku IN ('11721', 'G-200', '21058MIX', '11862', '31-1516', '11743')
  AND (sub_category IS NULL OR sub_category = '');

-- Verification: real category names + counts
SELECT sub_category, count(*) AS product_count
FROM products
GROUP BY sub_category
ORDER BY product_count DESC, sub_category;

-- Full row count sanity check
SELECT count(*) AS total_products FROM products;

