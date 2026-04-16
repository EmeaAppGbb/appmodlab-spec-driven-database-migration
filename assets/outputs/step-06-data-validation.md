# Step 06 — Data Validation: GreenHarvest SQL Server → PostgreSQL Migration

This document provides comprehensive validation queries and procedures to verify data integrity, schema correctness, and functional equivalence after migrating the GreenHarvest Cooperative database from SQL Server to PostgreSQL (Azure Database for PostgreSQL – Flexible Server).

> **Convention**: Source queries use **SQL Server** syntax (T-SQL). Target queries use **PostgreSQL** syntax. Run each pair side-by-side and compare results.

---

## Table of Contents

1. [Row Count Validation](#1-row-count-validation)
2. [Schema Validation](#2-schema-validation)
3. [Computed Column Validation](#3-computed-column-validation)
4. [Foreign Key Integrity Checks](#4-foreign-key-integrity-checks)
5. [Index Existence Verification](#5-index-existence-verification)
6. [Constraint Validation](#6-constraint-validation)
7. [Data Type Fidelity](#7-data-type-fidelity)
8. [Stored Procedure Output Comparison](#8-stored-procedure-output-comparison)
9. [Trigger Behavior Validation](#9-trigger-behavior-validation)
10. [View Output Comparison](#10-view-output-comparison)
11. [Seed Data Verification](#11-seed-data-verification)
12. [Edge Case Tests](#12-edge-case-tests)
13. [Performance Baseline Queries](#13-performance-baseline-queries)

---

## 1. Row Count Validation

Verify every table migrated the correct number of rows.

### Source — SQL Server

```sql
SELECT 'CropManagement.CropTypes'     AS table_name, COUNT(*) AS row_count FROM CropManagement.CropTypes
UNION ALL
SELECT 'Members.MemberAccounts',       COUNT(*) FROM Members.MemberAccounts
UNION ALL
SELECT 'CropManagement.Fields',        COUNT(*) FROM CropManagement.Fields
UNION ALL
SELECT 'CropManagement.Harvests',      COUNT(*) FROM CropManagement.Harvests
UNION ALL
SELECT 'Trading.CommodityPrices',      COUNT(*) FROM Trading.CommodityPrices
UNION ALL
SELECT 'Inventory.FertilizerStock',    COUNT(*) FROM Inventory.FertilizerStock
ORDER BY table_name;
```

### Target — PostgreSQL

```sql
SELECT 'crop_management.crop_types'    AS table_name, COUNT(*) AS row_count FROM crop_management.crop_types
UNION ALL
SELECT 'members.member_accounts',      COUNT(*) FROM members.member_accounts
UNION ALL
SELECT 'crop_management.fields',       COUNT(*) FROM crop_management.fields
UNION ALL
SELECT 'crop_management.harvests',     COUNT(*) FROM crop_management.harvests
UNION ALL
SELECT 'trading.commodity_prices',     COUNT(*) FROM trading.commodity_prices
UNION ALL
SELECT 'inventory.fertilizer_stock',   COUNT(*) FROM inventory.fertilizer_stock
ORDER BY table_name;
```

### Expected Outcome

| Table | Expected Rows |
|---|---|
| crop_types | 5 (seed data) |
| member_accounts | 3 (sample data) |
| fields | *match source* |
| harvests | *match source* |
| commodity_prices | *match source* |
| fertilizer_stock | *match source* |

> **PASS criteria**: Every row count in the target must exactly match the source.

---

## 2. Schema Validation

Compare column names, data types, nullability, and defaults for every table.

### 2.1 Source — SQL Server (all tables)

```sql
SELECT
    TABLE_SCHEMA + '.' + TABLE_NAME          AS full_table,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('CropManagement', 'Members', 'Trading', 'Inventory')
ORDER BY full_table, ORDINAL_POSITION;
```

### 2.2 Target — PostgreSQL (all tables)

```sql
SELECT
    table_schema || '.' || table_name        AS full_table,
    column_name,
    data_type,
    character_maximum_length,
    numeric_precision,
    numeric_scale,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema IN ('crop_management', 'members', 'trading', 'inventory')
ORDER BY full_table, ordinal_position;
```

### 2.3 Expected Column-Level Mapping

| SQL Server Table | Column (Source) | Source Type | PostgreSQL Column | Target Type | Notes |
|---|---|---|---|---|---|
| CropManagement.CropTypes | CropTypeId | INT IDENTITY | crop_type_id | SERIAL | PK, auto-increment |
| | Name | NVARCHAR(100) | name | VARCHAR(100) | NOT NULL |
| | GrowingSeason | NVARCHAR(50) | growing_season | VARCHAR(50) | NOT NULL |
| | DaysToMaturity | INT | days_to_maturity | INT | NOT NULL |
| | MinTemperature | DECIMAL(5,2) | min_temperature | NUMERIC(5,2) | Nullable |
| | MaxTemperature | DECIMAL(5,2) | max_temperature | NUMERIC(5,2) | Nullable |
| | WaterRequirement | NVARCHAR(20) | water_requirement | VARCHAR(20) | Nullable |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| | ModifiedDate | DATETIME | modified_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| Members.MemberAccounts | MemberId | INT IDENTITY | member_id | SERIAL | PK |
| | MemberNumber | NVARCHAR(20) | member_number | VARCHAR(20) | UNIQUE NOT NULL |
| | FirstName | NVARCHAR(50) | first_name | VARCHAR(50) | NOT NULL |
| | LastName | NVARCHAR(50) | last_name | VARCHAR(50) | NOT NULL |
| | Email | NVARCHAR(100) | email | VARCHAR(100) | Nullable |
| | PhoneNumber | NVARCHAR(20) | phone_number | VARCHAR(20) | Nullable |
| | Address | NVARCHAR(200) | address | VARCHAR(200) | Nullable |
| | City | NVARCHAR(50) | city | VARCHAR(50) | Nullable |
| | State | NVARCHAR(2) | state | VARCHAR(2) | Nullable |
| | ZipCode | NVARCHAR(10) | zip_code | VARCHAR(10) | Nullable |
| | MembershipDate | DATE | membership_date | DATE | NOT NULL |
| | Status | NVARCHAR(20) | status | VARCHAR(20) | DEFAULT 'Active' |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| | ModifiedDate | DATETIME | modified_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| CropManagement.Fields | FieldId | INT IDENTITY | field_id | SERIAL | PK |
| | MemberId | INT | member_id | INT | FK → member_accounts, NOT NULL |
| | FieldName | NVARCHAR(100) | field_name | VARCHAR(100) | NOT NULL |
| | Acreage | DECIMAL(10,2) | acreage | NUMERIC(10,2) | NOT NULL |
| | SoilType | NVARCHAR(50) | soil_type | VARCHAR(50) | Nullable |
| | IrrigationType | NVARCHAR(50) | irrigation_type | VARCHAR(50) | Nullable |
| | GPSBoundary | GEOGRAPHY | gps_boundary | GEOMETRY(POLYGON,4326) | PostGIS |
| | CurrentCropId | INT | current_crop_id | INT | FK → crop_types, Nullable |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| | ModifiedDate | DATETIME | modified_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| CropManagement.Harvests | HarvestId | INT IDENTITY | harvest_id | SERIAL | PK |
| | FieldId | INT | field_id | INT | FK → fields, NOT NULL |
| | CropTypeId | INT | crop_type_id | INT | FK → crop_types, NOT NULL |
| | HarvestDate | DATE | harvest_date | DATE | NOT NULL |
| | Quantity | DECIMAL(12,2) | quantity | NUMERIC(12,2) | NOT NULL |
| | UnitType | NVARCHAR(20) | unit_type | VARCHAR(20) | NOT NULL |
| | YieldBushels | AS (computed) PERSISTED | yield_bushels | GENERATED ALWAYS AS (…) STORED | Computed column |
| | MoistureContent | DECIMAL(5,2) | moisture_content | NUMERIC(5,2) | Nullable |
| | GradeCode | NVARCHAR(10) | grade_code | VARCHAR(10) | Nullable |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| Trading.CommodityPrices | PriceId | INT IDENTITY | price_id | SERIAL | PK |
| | CropTypeId | INT | crop_type_id | INT | FK → crop_types, NOT NULL |
| | MarketDate | DATE | market_date | DATE | NOT NULL |
| | PricePerBushel | MONEY | price_per_bushel | NUMERIC(19,4) | Precision-sensitive |
| | MarketName | NVARCHAR(100) | market_name | VARCHAR(100) | Nullable |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |
| Inventory.FertilizerStock | StockId | INT IDENTITY | stock_id | SERIAL | PK |
| | ProductName | NVARCHAR(100) | product_name | VARCHAR(100) | NOT NULL |
| | ManufacturerName | NVARCHAR(100) | manufacturer_name | VARCHAR(100) | Nullable |
| | QuantityOnHand | DECIMAL(12,2) | quantity_on_hand | NUMERIC(12,2) | NOT NULL |
| | Unit | NVARCHAR(20) | unit | VARCHAR(20) | NOT NULL |
| | CostPerUnit | MONEY | cost_per_unit | NUMERIC(19,4) | Precision-sensitive |
| | ReorderLevel | DECIMAL(12,2) | reorder_level | NUMERIC(12,2) | Nullable |
| | LastRestockDate | DATE | last_restock_date | DATE | Nullable |
| | ExpirationDate | DATE | expiration_date | DATE | Nullable |
| | CreatedDate | DATETIME | created_date | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP |

> **PASS criteria**: Every column exists with the correct mapped type, nullability, and default.

---

## 3. Computed Column Validation

The SQL Server `YieldBushels` computed column uses `dbo.fn_CalculateYieldBushels(Quantity, UnitType)`. PostgreSQL uses `GENERATED ALWAYS AS (crop_management.calculate_yield_bushels(quantity, unit_type)) STORED`.

### 3.1 Conversion Factor Reference

| Unit Type | Conversion Factor | Formula |
|---|---|---|
| bushels | 1.0 | quantity × 1.0 |
| tonnes | 36.7437 | quantity × 36.7437 |
| hundredweight | 1.667 | quantity × 1.667 |
| kilograms | 0.0367437 | quantity × 0.0367437 |
| *(unknown)* | 1.0 (default) | quantity × 1.0 |

### 3.2 Full-Table Validation — PostgreSQL

```sql
-- Verify every row's generated yield_bushels matches the function output
SELECT
    harvest_id,
    quantity,
    unit_type,
    yield_bushels,
    crop_management.calculate_yield_bushels(quantity, unit_type) AS expected_yield,
    ABS(yield_bushels - crop_management.calculate_yield_bushels(quantity, unit_type)) AS diff
FROM crop_management.harvests
WHERE ABS(yield_bushels - crop_management.calculate_yield_bushels(quantity, unit_type)) > 0.001;
```

> **PASS criteria**: Zero rows returned (no discrepancies).

### 3.3 Unit-Specific Spot Checks — PostgreSQL

```sql
-- Bushels (identity conversion)
SELECT 'bushels' AS test_unit,
    crop_management.calculate_yield_bushels(100.00, 'bushels') AS result,
    100.00 AS expected,
    CASE WHEN crop_management.calculate_yield_bushels(100.00, 'bushels') = 100.00
         THEN 'PASS' ELSE 'FAIL' END AS status;

-- Tonnes
SELECT 'tonnes' AS test_unit,
    crop_management.calculate_yield_bushels(10.00, 'tonnes') AS result,
    367.44 AS expected,
    CASE WHEN ABS(crop_management.calculate_yield_bushels(10.00, 'tonnes') - 367.44) < 0.01
         THEN 'PASS' ELSE 'FAIL' END AS status;

-- Hundredweight
SELECT 'hundredweight' AS test_unit,
    crop_management.calculate_yield_bushels(100.00, 'hundredweight') AS result,
    166.70 AS expected,
    CASE WHEN ABS(crop_management.calculate_yield_bushels(100.00, 'hundredweight') - 166.70) < 0.01
         THEN 'PASS' ELSE 'FAIL' END AS status;

-- Kilograms
SELECT 'kilograms' AS test_unit,
    crop_management.calculate_yield_bushels(1000.00, 'kilograms') AS result,
    36.74 AS expected,
    CASE WHEN ABS(crop_management.calculate_yield_bushels(1000.00, 'kilograms') - 36.74) < 0.01
         THEN 'PASS' ELSE 'FAIL' END AS status;

-- Unknown unit (defaults to bushels)
SELECT 'unknown' AS test_unit,
    crop_management.calculate_yield_bushels(50.00, 'pounds') AS result,
    50.00 AS expected,
    CASE WHEN crop_management.calculate_yield_bushels(50.00, 'pounds') = 50.00
         THEN 'PASS' ELSE 'FAIL' END AS status;
```

### 3.4 Cross-Database Comparison

```sql
-- SQL Server: extract yield values
SELECT HarvestId, Quantity, UnitType, YieldBushels
FROM CropManagement.Harvests
ORDER BY HarvestId;

-- PostgreSQL: extract yield values
SELECT harvest_id, quantity, unit_type, yield_bushels
FROM crop_management.harvests
ORDER BY harvest_id;
```

> **PASS criteria**: Every (harvest_id, yield_bushels) pair matches between source and target within ±0.01 tolerance.

---

## 4. Foreign Key Integrity Checks

### 4.1 Orphaned Fields Without Members

```sql
-- PostgreSQL
SELECT f.field_id, f.field_name, f.member_id
FROM crop_management.fields f
LEFT JOIN members.member_accounts m ON f.member_id = m.member_id
WHERE m.member_id IS NULL;
```

> **PASS criteria**: Zero rows returned.

### 4.2 Orphaned Harvests Without Fields

```sql
-- PostgreSQL
SELECT h.harvest_id, h.field_id, h.harvest_date
FROM crop_management.harvests h
LEFT JOIN crop_management.fields f ON h.field_id = f.field_id
WHERE f.field_id IS NULL;
```

> **PASS criteria**: Zero rows returned.

### 4.3 Orphaned Commodity Prices Without Crop Types

```sql
-- PostgreSQL
SELECT cp.price_id, cp.crop_type_id, cp.market_date
FROM trading.commodity_prices cp
LEFT JOIN crop_management.crop_types ct ON cp.crop_type_id = ct.crop_type_id
WHERE ct.crop_type_id IS NULL;
```

> **PASS criteria**: Zero rows returned.

### 4.4 Orphaned Harvests Without Crop Types

```sql
-- PostgreSQL
SELECT h.harvest_id, h.crop_type_id
FROM crop_management.harvests h
LEFT JOIN crop_management.crop_types ct ON h.crop_type_id = ct.crop_type_id
WHERE ct.crop_type_id IS NULL;
```

> **PASS criteria**: Zero rows returned.

### 4.5 Orphaned Fields Without Crop Types (CurrentCropId)

```sql
-- PostgreSQL
SELECT f.field_id, f.current_crop_id
FROM crop_management.fields f
LEFT JOIN crop_management.crop_types ct ON f.current_crop_id = ct.crop_type_id
WHERE f.current_crop_id IS NOT NULL
  AND ct.crop_type_id IS NULL;
```

> **PASS criteria**: Zero rows returned.

### 4.6 Combined FK Summary

```sql
-- PostgreSQL: single summary query
SELECT check_name, issue_count FROM (
    SELECT 'Orphaned fields (no member)' AS check_name, COUNT(*) AS issue_count
    FROM crop_management.fields f
    LEFT JOIN members.member_accounts m ON f.member_id = m.member_id
    WHERE m.member_id IS NULL
  UNION ALL
    SELECT 'Orphaned harvests (no field)', COUNT(*)
    FROM crop_management.harvests h
    LEFT JOIN crop_management.fields f ON h.field_id = f.field_id
    WHERE f.field_id IS NULL
  UNION ALL
    SELECT 'Orphaned prices (no crop type)', COUNT(*)
    FROM trading.commodity_prices cp
    LEFT JOIN crop_management.crop_types ct ON cp.crop_type_id = ct.crop_type_id
    WHERE ct.crop_type_id IS NULL
  UNION ALL
    SELECT 'Orphaned harvests (no crop type)', COUNT(*)
    FROM crop_management.harvests h
    LEFT JOIN crop_management.crop_types ct ON h.crop_type_id = ct.crop_type_id
    WHERE ct.crop_type_id IS NULL
) AS fk_checks;
```

> **PASS criteria**: All issue_count values are 0.

---

## 5. Index Existence Verification

### 5.1 PostgreSQL — List All Indexes

```sql
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname IN ('crop_management', 'members', 'trading', 'inventory')
ORDER BY schemaname, tablename, indexname;
```

### 5.2 Expected Index Inventory

| Schema | Table | Index Name | Columns | Source Index (SQL Server) |
|---|---|---|---|---|
| crop_management | crop_types | idx_crop_types_name | name | IX_CropTypes_Name |
| crop_management | crop_types | idx_crop_types_season | growing_season | IX_CropTypes_Season |
| members | member_accounts | idx_members_number | member_number | IX_Members_Number |
| members | member_accounts | idx_members_name | last_name, first_name | IX_Members_Name |
| crop_management | fields | idx_fields_member | member_id | IX_Fields_Member |
| crop_management | fields | idx_fields_current_crop | current_crop_id | IX_Fields_CurrentCrop |
| crop_management | harvests | idx_harvests_field | field_id | IX_Harvests_Field |
| crop_management | harvests | idx_harvests_date | harvest_date | IX_Harvests_Date |
| trading | commodity_prices | idx_prices_crop_date | crop_type_id, market_date | IX_Prices_CropDate |
| inventory | fertilizer_stock | idx_fertilizer_product | product_name | IX_Fertilizer_Product |

### 5.3 Specific Index Verification Query

```sql
-- Verify each expected index exists
SELECT
    expected.index_name,
    CASE WHEN pi.indexname IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS status
FROM (VALUES
    ('idx_crop_types_name'),
    ('idx_crop_types_season'),
    ('idx_members_number'),
    ('idx_members_name'),
    ('idx_fields_member'),
    ('idx_fields_current_crop'),
    ('idx_harvests_field'),
    ('idx_harvests_date'),
    ('idx_prices_crop_date'),
    ('idx_fertilizer_product')
) AS expected(index_name)
LEFT JOIN pg_indexes pi ON pi.indexname = expected.index_name;
```

> **PASS criteria**: All indexes report `EXISTS`.

---

## 6. Constraint Validation

### 6.1 UNIQUE Constraint on member_number

```sql
-- PostgreSQL: verify UNIQUE constraint exists
SELECT
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'members'
    AND tc.table_name = 'member_accounts'
    AND tc.constraint_type = 'UNIQUE';
```

> **PASS criteria**: A UNIQUE constraint on `member_number` is returned.

### 6.2 UNIQUE Enforcement Test

```sql
-- PostgreSQL: attempt duplicate insert (should fail)
DO $$
BEGIN
    INSERT INTO members.member_accounts (member_number, first_name, last_name, membership_date)
    VALUES ('M001', 'Duplicate', 'Test', '2025-01-01');
    RAISE NOTICE 'FAIL: Duplicate member_number was accepted';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: Duplicate member_number correctly rejected';
END $$;
```

### 6.3 NOT NULL Constraint Verification

```sql
-- PostgreSQL: verify NOT NULL columns
SELECT
    table_schema || '.' || table_name AS full_table,
    column_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema IN ('crop_management', 'members', 'trading', 'inventory')
    AND is_nullable = 'NO'
ORDER BY full_table, ordinal_position;
```

### 6.4 NOT NULL Enforcement Tests

```sql
-- Test: CropTypes.name cannot be NULL
DO $$
BEGIN
    INSERT INTO crop_management.crop_types (name, growing_season, days_to_maturity)
    VALUES (NULL, 'Spring', 90);
    RAISE NOTICE 'FAIL: NULL name was accepted';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'PASS: NULL name correctly rejected';
END $$;

-- Test: Harvests.quantity cannot be NULL
DO $$
BEGIN
    INSERT INTO crop_management.harvests (field_id, crop_type_id, harvest_date, quantity, unit_type)
    VALUES (1, 1, '2025-01-01', NULL, 'bushels');
    RAISE NOTICE 'FAIL: NULL quantity was accepted';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'PASS: NULL quantity correctly rejected';
END $$;

-- Test: MemberAccounts.membership_date cannot be NULL
DO $$
BEGIN
    INSERT INTO members.member_accounts (member_number, first_name, last_name, membership_date)
    VALUES ('MTEST', 'Test', 'User', NULL);
    RAISE NOTICE 'FAIL: NULL membership_date was accepted';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'PASS: NULL membership_date correctly rejected';
END $$;
```

### 6.5 Primary Key Verification

```sql
-- PostgreSQL: verify all primary keys
SELECT
    tc.table_schema || '.' || tc.table_name AS full_table,
    tc.constraint_name,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.constraint_type = 'PRIMARY KEY'
    AND tc.table_schema IN ('crop_management', 'members', 'trading', 'inventory')
ORDER BY full_table;
```

### 6.6 Foreign Key Verification

```sql
-- PostgreSQL: list all foreign keys
SELECT
    tc.table_schema || '.' || tc.table_name AS source_table,
    kcu.column_name AS fk_column,
    ccu.table_schema || '.' || ccu.table_name AS target_table,
    ccu.column_name AS target_column,
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema IN ('crop_management', 'members', 'trading', 'inventory')
ORDER BY source_table;
```

> **Expected FKs**: fields → member_accounts (member_id), fields → crop_types (current_crop_id), harvests → fields (field_id), harvests → crop_types (crop_type_id), commodity_prices → crop_types (crop_type_id).

---

## 7. Data Type Fidelity

### 7.1 MONEY → NUMERIC Precision

SQL Server `MONEY` has 4 decimal places. The target uses `NUMERIC(19,4)`.

```sql
-- SQL Server: extract MONEY values with full precision
SELECT PriceId, CropTypeId, PricePerBushel
FROM Trading.CommodityPrices
ORDER BY PriceId;

-- PostgreSQL: compare values
SELECT price_id, crop_type_id, price_per_bushel
FROM trading.commodity_prices
ORDER BY price_id;
```

#### Precision Spot Check

```sql
-- PostgreSQL: ensure no precision loss on monetary columns
SELECT
    'commodity_prices.price_per_bushel' AS column_check,
    numeric_precision,
    numeric_scale,
    CASE WHEN numeric_precision >= 19 AND numeric_scale = 4
         THEN 'PASS' ELSE 'FAIL' END AS status
FROM information_schema.columns
WHERE table_schema = 'trading'
    AND table_name = 'commodity_prices'
    AND column_name = 'price_per_bushel'
UNION ALL
SELECT
    'fertilizer_stock.cost_per_unit',
    numeric_precision,
    numeric_scale,
    CASE WHEN numeric_precision >= 19 AND numeric_scale = 4
         THEN 'PASS' ELSE 'FAIL' END
FROM information_schema.columns
WHERE table_schema = 'inventory'
    AND table_name = 'fertilizer_stock'
    AND column_name = 'cost_per_unit';
```

> **PASS criteria**: Both columns have precision ≥ 19, scale = 4.

### 7.2 GEOGRAPHY → GEOMETRY Spatial Data

```sql
-- PostgreSQL: verify PostGIS extension is active
SELECT extname, extversion FROM pg_extension WHERE extname = 'postgis';
```

```sql
-- PostgreSQL: verify spatial column type and SRID
SELECT
    f_table_schema,
    f_table_name,
    f_geometry_column,
    type,
    srid
FROM geometry_columns
WHERE f_table_schema = 'crop_management'
    AND f_table_name = 'fields';
```

> **PASS criteria**: Column `gps_boundary` has type `POLYGON` and SRID `4326`.

```sql
-- PostgreSQL: verify spatial data is valid
SELECT
    field_id,
    field_name,
    ST_IsValid(gps_boundary) AS is_valid,
    ST_SRID(gps_boundary) AS srid,
    ST_GeometryType(gps_boundary) AS geom_type
FROM crop_management.fields
WHERE gps_boundary IS NOT NULL;
```

> **PASS criteria**: All rows show `is_valid = true`, `srid = 4326`, `geom_type = ST_Polygon`.

### 7.3 NVARCHAR → VARCHAR Encoding

```sql
-- PostgreSQL: verify database encoding supports Unicode
SHOW server_encoding;
-- Expected: UTF8
```

```sql
-- PostgreSQL: spot-check that multi-byte characters survived migration
SELECT member_id, first_name, last_name, email
FROM members.member_accounts
WHERE first_name ~ '[^\x00-\x7F]'
   OR last_name  ~ '[^\x00-\x7F]';
```

### 7.4 DATETIME → TIMESTAMP

```sql
-- PostgreSQL: verify timestamp columns have correct type
SELECT
    table_schema || '.' || table_name AS full_table,
    column_name,
    data_type,
    CASE WHEN data_type = 'timestamp without time zone'
         THEN 'PASS' ELSE 'FAIL' END AS status
FROM information_schema.columns
WHERE table_schema IN ('crop_management', 'members', 'trading', 'inventory')
    AND column_name IN ('created_date', 'modified_date')
ORDER BY full_table;
```

---

## 8. Stored Procedure Output Comparison

### 8.1 sp_CalculateOptimalRotation

#### SQL Server

```sql
EXEC CropPlanning.sp_CalculateOptimalRotation @FieldId = 1, @CurrentYear = 2025;
```

#### PostgreSQL Equivalent Function

```sql
-- Migrated as a function in PostgreSQL
SELECT * FROM crop_management.calculate_optimal_rotation(1, 2025);
```

#### Cross-Validation

Run both and compare the output columns:

| Column | Source Value | Target Value | Match? |
|---|---|---|---|
| CropTypeId / crop_type_id | | | |
| Name / name | | | |
| RotationScore / rotation_score | | | |
| CurrentPrice / current_price | | | |
| TotalScore / total_score | | | |

> **PASS criteria**: Same recommended crop type and scores within ±0.01.

### 8.2 sp_CalculateMemberPayment

#### SQL Server

```sql
DECLARE @Payment MONEY;
EXEC Settlement.sp_CalculateMemberPayment @MemberId = 1, @SettlementYear = 2025, @TotalPayment = @Payment OUTPUT;
SELECT @Payment AS TotalPayment;
```

#### PostgreSQL Equivalent Function

```sql
-- Migrated as a function with OUT parameter or return value
SELECT * FROM settlement.calculate_member_payment(1, 2025);
```

#### Cross-Validation for All Members

```sql
-- SQL Server: run for all members
DECLARE @Payment MONEY;
DECLARE @MemberId INT;
DECLARE member_cursor CURSOR FOR SELECT MemberId FROM Members.MemberAccounts;
OPEN member_cursor;
FETCH NEXT FROM member_cursor INTO @MemberId;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC Settlement.sp_CalculateMemberPayment @MemberId, 2025, @Payment OUTPUT;
    SELECT @MemberId AS MemberId, @Payment AS TotalPayment;
    FETCH NEXT FROM member_cursor INTO @MemberId;
END;
CLOSE member_cursor;
DEALLOCATE member_cursor;

-- PostgreSQL: run for all members
SELECT
    m.member_id,
    settlement.calculate_member_payment(m.member_id, 2025) AS total_payment
FROM members.member_accounts m
ORDER BY m.member_id;
```

> **PASS criteria**: Payment amounts match within ±0.01 for every member.

---

## 9. Trigger Behavior Validation

The SQL Server trigger `tr_AuditHarvestChanges` logs INSERT, UPDATE, and DELETE operations on `CropManagement.Harvests` to `Audit.HarvestAuditLog`. In PostgreSQL this is migrated to a trigger function on `crop_management.harvests` that writes to `audit.harvest_audit_log`.

### 9.1 Verify Trigger Exists

```sql
-- PostgreSQL
SELECT
    trigger_schema,
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema || '.' || event_object_table AS target_table
FROM information_schema.triggers
WHERE event_object_schema = 'crop_management'
    AND event_object_table = 'harvests';
```

> **PASS criteria**: Trigger exists for INSERT, UPDATE, and DELETE events.

### 9.2 INSERT Audit Test

```sql
-- PostgreSQL: record baseline
SELECT COUNT(*) AS before_count FROM audit.harvest_audit_log;

-- Insert a test harvest
INSERT INTO crop_management.harvests (field_id, crop_type_id, harvest_date, quantity, unit_type)
VALUES (1, 1, '2025-12-01', 500.00, 'bushels');

-- Verify audit entry
SELECT COUNT(*) AS after_count FROM audit.harvest_audit_log;
SELECT * FROM audit.harvest_audit_log
ORDER BY change_date DESC LIMIT 1;
```

> **PASS criteria**: `after_count = before_count + 1`, change_type = 'INSERT'.

### 9.3 UPDATE Audit Test

```sql
-- PostgreSQL: update the test harvest
UPDATE crop_management.harvests
SET quantity = 600.00
WHERE harvest_date = '2025-12-01' AND quantity = 500.00;

-- Verify audit entry
SELECT * FROM audit.harvest_audit_log
ORDER BY change_date DESC LIMIT 1;
```

> **PASS criteria**: New audit row with change_type = 'UPDATE', old_value shows quantity 500, new_value shows quantity 600.

### 9.4 DELETE Audit Test

```sql
-- PostgreSQL: delete the test harvest
DELETE FROM crop_management.harvests
WHERE harvest_date = '2025-12-01' AND quantity = 600.00;

-- Verify audit entry
SELECT * FROM audit.harvest_audit_log
ORDER BY change_date DESC LIMIT 1;
```

> **PASS criteria**: New audit row with change_type = 'DELETE'.

### 9.5 Cleanup

```sql
-- Remove test audit entries
DELETE FROM audit.harvest_audit_log
WHERE change_date >= CURRENT_DATE;
```

---

## 10. View Output Comparison

### 10.1 vw_FieldProductivity

#### SQL Server

```sql
SELECT
    FieldId, FieldName, MemberNumber, MemberName, Acreage,
    CurrentCrop, TotalYield, YieldPerAcre, HarvestCount, LastHarvestDate
FROM CropManagement.vw_FieldProductivity
ORDER BY FieldId;
```

#### PostgreSQL

```sql
SELECT
    field_id, field_name, member_number, member_name, acreage,
    current_crop, total_yield, yield_per_acre, harvest_count, last_harvest_date
FROM crop_management.vw_field_productivity
ORDER BY field_id;
```

### 10.2 Column-by-Column Comparison

| Column (Source) | Column (Target) | Comparison |
|---|---|---|
| FieldId | field_id | Exact match |
| FieldName | field_name | Exact match |
| MemberNumber | member_number | Exact match |
| MemberName (FirstName + ' ' + LastName) | member_name (first_name \|\| ' ' \|\| last_name) | Exact match |
| Acreage | acreage | Exact match |
| CurrentCrop | current_crop | Exact match |
| TotalYield | total_yield | Within ±0.01 |
| YieldPerAcre | yield_per_acre | Within ±0.01 |
| HarvestCount | harvest_count | Exact match |
| LastHarvestDate | last_harvest_date | Exact match |

### 10.3 View Definition Verification

```sql
-- PostgreSQL: verify view exists and is queryable
SELECT
    schemaname,
    viewname,
    definition
FROM pg_views
WHERE schemaname = 'crop_management'
    AND viewname = 'vw_field_productivity';
```

> **PASS criteria**: View exists, returns same row count and values as SQL Server source.

---

## 11. Seed Data Verification

### 11.1 CropTypes — 5 Rows Exact Values

```sql
-- PostgreSQL
SELECT
    crop_type_id,
    name,
    growing_season,
    days_to_maturity,
    min_temperature,
    max_temperature,
    water_requirement
FROM crop_management.crop_types
ORDER BY crop_type_id;
```

#### Expected Values

| crop_type_id | name | growing_season | days_to_maturity | min_temperature | max_temperature | water_requirement |
|---|---|---|---|---|---|---|
| 1 | Corn | Spring/Summer | 120 | 10.00 | 30.00 | High |
| 2 | Soybeans | Spring/Summer | 100 | 15.00 | 28.00 | Medium |
| 3 | Wheat | Fall/Winter | 180 | 0.00 | 25.00 | Low |
| 4 | Barley | Spring | 90 | 5.00 | 22.00 | Medium |
| 5 | Oats | Spring | 80 | 7.00 | 20.00 | Medium |

```sql
-- PostgreSQL: automated verification
SELECT
    CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END AS count_check,
    CASE WHEN COUNT(*) FILTER (WHERE name = 'Corn' AND growing_season = 'Spring/Summer'
        AND days_to_maturity = 120 AND min_temperature = 10.00 AND max_temperature = 30.00
        AND water_requirement = 'High') = 1 THEN 'PASS' ELSE 'FAIL' END AS corn_check,
    CASE WHEN COUNT(*) FILTER (WHERE name = 'Soybeans' AND growing_season = 'Spring/Summer'
        AND days_to_maturity = 100 AND min_temperature = 15.00 AND max_temperature = 28.00
        AND water_requirement = 'Medium') = 1 THEN 'PASS' ELSE 'FAIL' END AS soybeans_check,
    CASE WHEN COUNT(*) FILTER (WHERE name = 'Wheat' AND growing_season = 'Fall/Winter'
        AND days_to_maturity = 180 AND min_temperature = 0.00 AND max_temperature = 25.00
        AND water_requirement = 'Low') = 1 THEN 'PASS' ELSE 'FAIL' END AS wheat_check,
    CASE WHEN COUNT(*) FILTER (WHERE name = 'Barley' AND growing_season = 'Spring'
        AND days_to_maturity = 90 AND min_temperature = 5.00 AND max_temperature = 22.00
        AND water_requirement = 'Medium') = 1 THEN 'PASS' ELSE 'FAIL' END AS barley_check,
    CASE WHEN COUNT(*) FILTER (WHERE name = 'Oats' AND growing_season = 'Spring'
        AND days_to_maturity = 80 AND min_temperature = 7.00 AND max_temperature = 20.00
        AND water_requirement = 'Medium') = 1 THEN 'PASS' ELSE 'FAIL' END AS oats_check
FROM crop_management.crop_types;
```

### 11.2 Members — 3 Rows Exact Values

```sql
-- PostgreSQL
SELECT
    member_id,
    member_number,
    first_name,
    last_name,
    email,
    phone_number,
    membership_date,
    status
FROM members.member_accounts
ORDER BY member_id;
```

#### Expected Values

| member_number | first_name | last_name | email | phone_number | membership_date | status |
|---|---|---|---|---|---|---|
| M001 | John | Smith | jsmith@email.com | 555-0101 | 2020-01-15 | Active |
| M002 | Mary | Johnson | mjohnson@email.com | 555-0102 | 2019-05-20 | Active |
| M003 | Robert | Williams | rwilliams@email.com | 555-0103 | 2021-03-10 | Active |

```sql
-- PostgreSQL: automated verification
SELECT
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS count_check,
    CASE WHEN COUNT(*) FILTER (WHERE member_number = 'M001' AND first_name = 'John'
        AND last_name = 'Smith' AND email = 'jsmith@email.com'
        AND phone_number = '555-0101' AND membership_date = '2020-01-15'
        AND status = 'Active') = 1 THEN 'PASS' ELSE 'FAIL' END AS m001_check,
    CASE WHEN COUNT(*) FILTER (WHERE member_number = 'M002' AND first_name = 'Mary'
        AND last_name = 'Johnson' AND email = 'mjohnson@email.com'
        AND phone_number = '555-0102' AND membership_date = '2019-05-20'
        AND status = 'Active') = 1 THEN 'PASS' ELSE 'FAIL' END AS m002_check,
    CASE WHEN COUNT(*) FILTER (WHERE member_number = 'M003' AND first_name = 'Robert'
        AND last_name = 'Williams' AND email = 'rwilliams@email.com'
        AND phone_number = '555-0103' AND membership_date = '2021-03-10'
        AND status = 'Active') = 1 THEN 'PASS' ELSE 'FAIL' END AS m003_check
FROM members.member_accounts;
```

> **PASS criteria**: All checks return 'PASS'.

---

## 12. Edge Case Tests

### 12.1 NULL Handling

```sql
-- PostgreSQL: verify NULL columns remain NULL after migration
SELECT
    'fields.soil_type' AS column_check,
    COUNT(*) FILTER (WHERE soil_type IS NULL) AS null_count,
    COUNT(*) AS total_count
FROM crop_management.fields
UNION ALL
SELECT 'fields.irrigation_type',
    COUNT(*) FILTER (WHERE irrigation_type IS NULL), COUNT(*)
FROM crop_management.fields
UNION ALL
SELECT 'fields.gps_boundary',
    COUNT(*) FILTER (WHERE gps_boundary IS NULL), COUNT(*)
FROM crop_management.fields
UNION ALL
SELECT 'harvests.moisture_content',
    COUNT(*) FILTER (WHERE moisture_content IS NULL), COUNT(*)
FROM crop_management.harvests
UNION ALL
SELECT 'harvests.grade_code',
    COUNT(*) FILTER (WHERE grade_code IS NULL), COUNT(*)
FROM crop_management.harvests
UNION ALL
SELECT 'member_accounts.email',
    COUNT(*) FILTER (WHERE email IS NULL), COUNT(*)
FROM members.member_accounts;
```

> **PASS criteria**: NULL counts match between source and target for each column.

### 12.2 Boundary Values — Numeric Precision

```sql
-- PostgreSQL: check extreme values in quantity and yield
SELECT
    'max_quantity' AS test,
    MAX(quantity) AS value,
    CASE WHEN MAX(quantity) <= 9999999999.99 THEN 'PASS' ELSE 'FAIL' END AS status
FROM crop_management.harvests
UNION ALL
SELECT 'min_quantity', MIN(quantity),
    CASE WHEN MIN(quantity) >= 0 THEN 'PASS' ELSE 'FAIL' END
FROM crop_management.harvests
UNION ALL
SELECT 'max_price', MAX(price_per_bushel),
    CASE WHEN MAX(price_per_bushel) <= 999999999999999.9999 THEN 'PASS' ELSE 'FAIL' END
FROM trading.commodity_prices
UNION ALL
SELECT 'max_acreage', MAX(acreage),
    CASE WHEN MAX(acreage) <= 99999999.99 THEN 'PASS' ELSE 'FAIL' END
FROM crop_management.fields;
```

### 12.3 Boundary Values — Date Ranges

```sql
-- PostgreSQL: verify date ranges are reasonable
SELECT
    'harvest_date range' AS test,
    MIN(harvest_date) AS min_date,
    MAX(harvest_date) AS max_date,
    CASE WHEN MIN(harvest_date) >= '2000-01-01' AND MAX(harvest_date) <= CURRENT_DATE + INTERVAL '1 year'
         THEN 'PASS' ELSE 'REVIEW' END AS status
FROM crop_management.harvests
UNION ALL
SELECT 'membership_date range',
    MIN(membership_date), MAX(membership_date),
    CASE WHEN MIN(membership_date) >= '1990-01-01' AND MAX(membership_date) <= CURRENT_DATE
         THEN 'PASS' ELSE 'REVIEW' END
FROM members.member_accounts;
```

### 12.4 Empty String vs NULL Consistency

```sql
-- PostgreSQL: check for empty strings that should be NULL
SELECT
    'member_accounts.email' AS column_check,
    COUNT(*) FILTER (WHERE email = '') AS empty_string_count
FROM members.member_accounts
UNION ALL
SELECT 'member_accounts.phone_number',
    COUNT(*) FILTER (WHERE phone_number = '')
FROM members.member_accounts
UNION ALL
SELECT 'member_accounts.address',
    COUNT(*) FILTER (WHERE address = '')
FROM members.member_accounts;
```

> **PASS criteria**: Zero empty strings (should be NULL instead, per PostgreSQL conventions).

### 12.5 Yield Calculation with Zero and Negative Values

```sql
-- PostgreSQL: verify function handles edge cases
SELECT
    'zero_quantity' AS test,
    crop_management.calculate_yield_bushels(0.00, 'bushels') AS result,
    CASE WHEN crop_management.calculate_yield_bushels(0.00, 'bushels') = 0
         THEN 'PASS' ELSE 'FAIL' END AS status
UNION ALL
SELECT 'null_unit_type',
    crop_management.calculate_yield_bushels(100.00, NULL),
    CASE WHEN crop_management.calculate_yield_bushels(100.00, NULL) IS NULL
         THEN 'PASS (NULL)' ELSE 'REVIEW' END
UNION ALL
SELECT 'empty_unit_type',
    crop_management.calculate_yield_bushels(100.00, ''),
    CASE WHEN crop_management.calculate_yield_bushels(100.00, '') = 100.00
         THEN 'PASS (defaults)' ELSE 'REVIEW' END;
```

### 12.6 Sequence/Identity Continuity

```sql
-- PostgreSQL: verify sequences are correctly positioned after migration
SELECT
    'crop_types' AS table_name,
    MAX(crop_type_id) AS max_id,
    (SELECT last_value FROM crop_management.crop_types_crop_type_id_seq) AS seq_value,
    CASE WHEN (SELECT last_value FROM crop_management.crop_types_crop_type_id_seq) >= MAX(crop_type_id)
         THEN 'PASS' ELSE 'FAIL' END AS status
FROM crop_management.crop_types
UNION ALL
SELECT 'member_accounts', MAX(member_id),
    (SELECT last_value FROM members.member_accounts_member_id_seq),
    CASE WHEN (SELECT last_value FROM members.member_accounts_member_id_seq) >= MAX(member_id)
         THEN 'PASS' ELSE 'FAIL' END
FROM members.member_accounts
UNION ALL
SELECT 'fields', MAX(field_id),
    (SELECT last_value FROM crop_management.fields_field_id_seq),
    CASE WHEN (SELECT last_value FROM crop_management.fields_field_id_seq) >= MAX(field_id)
         THEN 'PASS' ELSE 'FAIL' END
FROM crop_management.fields
UNION ALL
SELECT 'harvests', MAX(harvest_id),
    (SELECT last_value FROM crop_management.harvests_harvest_id_seq),
    CASE WHEN (SELECT last_value FROM crop_management.harvests_harvest_id_seq) >= MAX(harvest_id)
         THEN 'PASS' ELSE 'FAIL' END
FROM crop_management.harvests;
```

> **PASS criteria**: All sequence values ≥ max ID (prevents PK collisions on new inserts).

---

## 13. Performance Baseline Queries

Capture execution times on the target PostgreSQL database to establish a post-migration performance baseline.

### 13.1 Full Table Scan Baseline

```sql
-- PostgreSQL: time each full table scan
EXPLAIN ANALYZE SELECT COUNT(*) FROM crop_management.crop_types;
EXPLAIN ANALYZE SELECT COUNT(*) FROM members.member_accounts;
EXPLAIN ANALYZE SELECT COUNT(*) FROM crop_management.fields;
EXPLAIN ANALYZE SELECT COUNT(*) FROM crop_management.harvests;
EXPLAIN ANALYZE SELECT COUNT(*) FROM trading.commodity_prices;
EXPLAIN ANALYZE SELECT COUNT(*) FROM inventory.fertilizer_stock;
```

### 13.2 Indexed Lookup Performance

```sql
-- Index scan on member_number
EXPLAIN ANALYZE
SELECT * FROM members.member_accounts WHERE member_number = 'M001';

-- Index scan on crop name
EXPLAIN ANALYZE
SELECT * FROM crop_management.crop_types WHERE name = 'Corn';

-- Index scan on harvest date range
EXPLAIN ANALYZE
SELECT * FROM crop_management.harvests
WHERE harvest_date BETWEEN '2025-01-01' AND '2025-12-31';

-- Composite index scan on commodity prices
EXPLAIN ANALYZE
SELECT * FROM trading.commodity_prices
WHERE crop_type_id = 1 AND market_date >= '2025-01-01';
```

### 13.3 Join Performance

```sql
-- View materialization (mirrors vw_field_productivity)
EXPLAIN ANALYZE
SELECT
    f.field_id,
    f.field_name,
    m.member_number,
    m.first_name || ' ' || m.last_name AS member_name,
    f.acreage,
    ct.name AS current_crop,
    SUM(h.yield_bushels) AS total_yield,
    SUM(h.yield_bushels) / f.acreage AS yield_per_acre,
    COUNT(h.harvest_id) AS harvest_count,
    MAX(h.harvest_date) AS last_harvest_date
FROM crop_management.fields f
INNER JOIN members.member_accounts m ON f.member_id = m.member_id
LEFT JOIN crop_management.crop_types ct ON f.current_crop_id = ct.crop_type_id
LEFT JOIN crop_management.harvests h ON f.field_id = h.field_id
GROUP BY f.field_id, f.field_name, m.member_number, m.first_name, m.last_name, f.acreage, ct.name;
```

### 13.4 Spatial Query Performance

```sql
-- PostGIS spatial query baseline
EXPLAIN ANALYZE
SELECT field_id, field_name, ST_Area(gps_boundary::geography) AS area_sq_meters
FROM crop_management.fields
WHERE gps_boundary IS NOT NULL;
```

### 13.5 Aggregation Performance

```sql
-- Member settlement calculation (mirrors sp_CalculateMemberPayment logic)
EXPLAIN ANALYZE
SELECT
    f.member_id,
    SUM(h.yield_bushels) AS total_yield,
    AVG(CAST(h.grade_code AS NUMERIC(5,2))) AS avg_grade
FROM crop_management.harvests h
INNER JOIN crop_management.fields f ON h.field_id = f.field_id
WHERE EXTRACT(YEAR FROM h.harvest_date) = 2025
GROUP BY f.member_id;
```

### 13.6 Performance Benchmark Summary Template

Record results in this table after running the above queries:

| Query | Execution Time (ms) | Rows Returned | Scan Type | Notes |
|---|---|---|---|---|
| Full scan: crop_types | | | | |
| Full scan: member_accounts | | | | |
| Full scan: fields | | | | |
| Full scan: harvests | | | | |
| Full scan: commodity_prices | | | | |
| Full scan: fertilizer_stock | | | | |
| Index: member_number lookup | | | Index Scan | |
| Index: crop name lookup | | | Index Scan | |
| Index: harvest date range | | | Index Scan | |
| Index: commodity price composite | | | Index Scan | |
| Join: field productivity view | | | | |
| Spatial: area calculation | | | | |
| Aggregation: member settlement | | | | |

---

## Validation Summary Checklist

| # | Validation Area | Status |
|---|---|---|
| 1 | Row counts match (all 6 tables) | ☐ |
| 2 | Schema columns, types, nullability, defaults | ☐ |
| 3 | Computed column yield_bushels (all unit types) | ☐ |
| 4 | Foreign key integrity (no orphans) | ☐ |
| 5 | All 10 indexes exist | ☐ |
| 6 | UNIQUE, NOT NULL, PK, FK constraints enforced | ☐ |
| 7 | MONEY → NUMERIC(19,4) precision preserved | ☐ |
| 8 | GEOGRAPHY → GEOMETRY(POLYGON,4326) spatial data valid | ☐ |
| 9 | sp_CalculateOptimalRotation output matches | ☐ |
| 10 | sp_CalculateMemberPayment output matches | ☐ |
| 11 | Trigger fires on INSERT/UPDATE/DELETE | ☐ |
| 12 | vw_field_productivity output matches | ☐ |
| 13 | Seed data: 5 CropTypes exact values | ☐ |
| 14 | Seed data: 3 Members exact values | ☐ |
| 15 | NULL handling consistent | ☐ |
| 16 | Boundary values within range | ☐ |
| 17 | Sequences positioned correctly | ☐ |
| 18 | Performance baseline captured | ☐ |

> **Migration is validated** when all checklist items show ☑.
