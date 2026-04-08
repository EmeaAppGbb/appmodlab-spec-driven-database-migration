-- Data validation queries to ensure migration completeness

-- 1. Row count validation
SELECT 
    'crop_types' AS table_name,
    COUNT(*) AS row_count
FROM crop_management.crop_types
UNION ALL
SELECT 'member_accounts', COUNT(*) FROM members.member_accounts
UNION ALL
SELECT 'fields', COUNT(*) FROM crop_management.fields
UNION ALL
SELECT 'harvests', COUNT(*) FROM crop_management.harvests;

-- 2. Computed column validation
-- Verify yield_bushels calculation matches source
SELECT 
    harvest_id,
    quantity,
    unit_type,
    yield_bushels,
    crop_management.calculate_yield_bushels(quantity, unit_type) AS calculated_yield,
    CASE 
        WHEN yield_bushels = crop_management.calculate_yield_bushels(quantity, unit_type) 
        THEN 'PASS' 
        ELSE 'FAIL' 
    END AS validation_status
FROM crop_management.harvests
LIMIT 100;

-- 3. Foreign key integrity validation
SELECT 
    'Orphaned fields (no member)' AS check_name,
    COUNT(*) AS issue_count
FROM crop_management.fields f
LEFT JOIN members.member_accounts m ON f.member_id = m.member_id
WHERE m.member_id IS NULL
UNION ALL
SELECT 
    'Orphaned harvests (no field)',
    COUNT(*)
FROM crop_management.harvests h
LEFT JOIN crop_management.fields f ON h.field_id = f.field_id
WHERE f.field_id IS NULL;

-- 4. Data type validation
SELECT 
    column_name,
    data_type,
    character_maximum_length,
    numeric_precision,
    numeric_scale
FROM information_schema.columns
WHERE table_schema = 'crop_management'
    AND table_name = 'harvests'
ORDER BY ordinal_position;

-- 5. View validation
-- Verify view returns expected results
SELECT * FROM crop_management.vw_field_productivity
LIMIT 10;
