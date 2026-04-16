# Step 05 — Migration Scripts

## GreenHarvest SQL Server → PostgreSQL Migration

| Attribute | Value |
|---|---|
| **Source System** | SQL Server 2012 Standard Edition |
| **Target System** | Azure Database for PostgreSQL — Flexible Server |
| **Database Name** | greenharvest |
| **Generated Date** | 2026-04-16 |
| **Total Scripts** | 7 (DDL · Functions · Triggers · Views · DML · Stored Procedures · Rollback) |
| **Execution Time (est.)** | < 5 minutes on empty database |

---

## Table of Contents

1. [Pre-Migration Checklist](#1-pre-migration-checklist)
2. [Migration Execution Order](#2-migration-execution-order)
3. [Script 1 — DDL Migration (Schemas, Extensions, Tables, Indexes, Constraints)](#3-script-1--ddl-migration)
4. [Script 2 — PL/pgSQL Function: calculate_yield_bushels](#4-script-2--plpgsql-function-calculate_yield_bushels)
5. [Script 3 — Audit Trigger Function and Trigger Definition](#5-script-3--audit-trigger-function-and-trigger-definition)
6. [Script 4 — View Creation: vw_field_productivity](#6-script-4--view-creation)
7. [Script 5 — DML Migration (Seed & Sample Data)](#7-script-5--dml-migration-seed--sample-data)
8. [Script 6 — Stored Procedure Migration (PL/pgSQL Functions)](#8-script-6--stored-procedure-migration)
9. [Script 7 — Rollback Scripts](#9-script-7--rollback-scripts)
10. [Post-Migration Checklist](#10-post-migration-checklist)

---

## 1. Pre-Migration Checklist

| # | Task | Status | Notes |
|---|---|---|---|
| 1 | Back up source SQL Server database | ☐ | Full backup with `BACKUP DATABASE GreenHarvest ...` |
| 2 | Confirm target PostgreSQL server is provisioned | ☐ | Azure Database for PostgreSQL — Flexible Server |
| 3 | Verify PostgreSQL version ≥ 12 | ☐ | Required for `GENERATED ALWAYS AS ... STORED` columns |
| 4 | Verify PostGIS extension is available | ☐ | Run `SELECT * FROM pg_available_extensions WHERE name = 'postgis';` |
| 5 | Create target database | ☐ | `CREATE DATABASE greenharvest ENCODING 'UTF8';` |
| 6 | Create migration user with sufficient privileges | ☐ | Needs `CREATE`, `USAGE` on schemas; superuser for extensions |
| 7 | Verify network connectivity to target | ☐ | Test with `psql -h <host> -U <user> -d greenharvest` |
| 8 | Document source row counts for validation | ☐ | Run validation queries on source before migration |
| 9 | Schedule maintenance window | ☐ | Coordinate with stakeholders for downtime |
| 10 | Review and approve migration scripts | ☐ | DBA sign-off on all scripts below |

---

## 2. Migration Execution Order

Scripts must be executed in the following order due to object dependencies:

```
┌─────────────────────────────────────────────────────────────────┐
│  Execution Order                                                │
├─────┬───────────────────────────────────────────────────────────┤
│  1  │ Script 1 — DDL: Extensions + Schemas                     │
│     │   └─ PostGIS extension, 5 schemas                        │
│  2  │ Script 2 — Function: calculate_yield_bushels (IMMUTABLE) │
│     │   └─ Must exist BEFORE harvests table (generated column) │
│  3  │ Script 1 — DDL: Tables (in dependency order)             │
│     │   ├─ members.member_accounts      (no FK deps)           │
│     │   ├─ crop_management.crop_types   (no FK deps)           │
│     │   ├─ crop_management.fields       (FK → members, crops)  │
│     │   ├─ crop_management.harvests     (FK → fields, crops;   │
│     │   │                                gen col → function)   │
│     │   ├─ inventory.fertilizer_stock   (no FK deps)           │
│     │   ├─ trading.commodity_prices     (FK → crop_types)      │
│     │   └─ audit.harvest_audit_log      (no FK deps)           │
│  4  │ Script 1 — DDL: Indexes (all B-tree + GiST)             │
│  5  │ Script 3 — Audit trigger function + trigger binding      │
│     │   └─ Depends on: harvests table, audit_log table         │
│  6  │ Script 4 — View: vw_field_productivity                   │
│     │   └─ Depends on: fields, members, crop_types, harvests   │
│  7  │ Script 5 — DML: Seed data (CropTypes) then Sample data   │
│     │   └─ CropTypes before Members (no FK dep, but logical)   │
│  8  │ Script 6 — Stored procedures (PL/pgSQL functions)        │
│     │   └─ Depends on: all tables and trading schema           │
└─────┴───────────────────────────────────────────────────────────┘
```

> **Critical Dependency:** Script 2 (calculate_yield_bushels) **must** execute before the `crop_management.harvests` table is created, because the table has a `GENERATED ALWAYS AS` column that references this function. The function must be `IMMUTABLE`.

---

## 3. Script 1 — DDL Migration

### 3.1 Extensions and Schemas

```sql
-- ============================================================
-- Script 1A: Extensions and Schema Creation
-- Database: greenharvest
-- Target: Azure Database for PostgreSQL — Flexible Server
-- ============================================================

-- Enable PostGIS for spatial data (GEOGRAPHY → GEOMETRY)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create application schemas
CREATE SCHEMA IF NOT EXISTS crop_management;
CREATE SCHEMA IF NOT EXISTS members;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS audit;
```

### 3.2 Table Creation (Dependency Order)

```sql
-- ============================================================
-- Script 1B: Table Creation (dependency-ordered)
-- ============================================================

-- ------------------------------------------------------------
-- Table 1: members.member_accounts
-- Source: Members.MemberAccounts
-- Dependencies: NONE
-- ------------------------------------------------------------
CREATE TABLE members.member_accounts (
    member_id       SERIAL PRIMARY KEY,
    member_number   VARCHAR(20) UNIQUE NOT NULL,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    email           VARCHAR(100),
    phone_number    VARCHAR(20),
    address         VARCHAR(200),
    city            VARCHAR(50),
    state           VARCHAR(2),
    zip_code        VARCHAR(10),
    membership_date DATE NOT NULL,
    status          VARCHAR(20) DEFAULT 'Active',
    created_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------
-- Table 2: crop_management.crop_types
-- Source: CropManagement.CropTypes
-- Dependencies: NONE
-- ------------------------------------------------------------
CREATE TABLE crop_management.crop_types (
    crop_type_id    SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    growing_season  VARCHAR(50) NOT NULL,
    days_to_maturity INT NOT NULL,
    min_temperature NUMERIC(5,2),
    max_temperature NUMERIC(5,2),
    water_requirement VARCHAR(20),
    created_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------
-- Table 3: crop_management.fields
-- Source: CropManagement.Fields
-- Dependencies: members.member_accounts, crop_management.crop_types
-- Notes: GEOGRAPHY → GEOMETRY(POLYGON, 4326) via PostGIS
-- ------------------------------------------------------------
CREATE TABLE crop_management.fields (
    field_id        SERIAL PRIMARY KEY,
    member_id       INT NOT NULL,
    field_name      VARCHAR(100) NOT NULL,
    acreage         NUMERIC(10,2) NOT NULL,
    soil_type       VARCHAR(50),
    irrigation_type VARCHAR(50),
    gps_boundary    GEOMETRY(POLYGON, 4326),
    current_crop_id INT,
    created_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fields_member FOREIGN KEY (member_id)
        REFERENCES members.member_accounts(member_id),
    CONSTRAINT fk_fields_crop FOREIGN KEY (current_crop_id)
        REFERENCES crop_management.crop_types(crop_type_id)
);

-- ------------------------------------------------------------
-- Table 4: crop_management.harvests
-- Source: CropManagement.Harvests
-- Dependencies: crop_management.fields, crop_management.crop_types,
--               crop_management.calculate_yield_bushels (FUNCTION)
-- Notes: Computed PERSISTED column → GENERATED ALWAYS AS ... STORED
--        Function MUST be created before this table (see Script 2)
-- ------------------------------------------------------------
CREATE TABLE crop_management.harvests (
    harvest_id      SERIAL PRIMARY KEY,
    field_id        INT NOT NULL,
    crop_type_id    INT NOT NULL,
    harvest_date    DATE NOT NULL,
    quantity        NUMERIC(12,2) NOT NULL,
    unit_type       VARCHAR(20) NOT NULL,
    yield_bushels   NUMERIC(12,2) GENERATED ALWAYS AS (
                        crop_management.calculate_yield_bushels(quantity, unit_type)
                    ) STORED,
    moisture_content NUMERIC(5,2),
    grade_code      VARCHAR(10),
    created_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_harvests_field FOREIGN KEY (field_id)
        REFERENCES crop_management.fields(field_id),
    CONSTRAINT fk_harvests_crop_type FOREIGN KEY (crop_type_id)
        REFERENCES crop_management.crop_types(crop_type_id)
);

-- ------------------------------------------------------------
-- Table 5: inventory.fertilizer_stock
-- Source: Inventory.FertilizerStock
-- Dependencies: NONE
-- Notes: MONEY → NUMERIC(19,4) for precision control
-- ------------------------------------------------------------
CREATE TABLE inventory.fertilizer_stock (
    stock_id         SERIAL PRIMARY KEY,
    product_name     VARCHAR(100) NOT NULL,
    manufacturer_name VARCHAR(100),
    quantity_on_hand NUMERIC(12,2) NOT NULL,
    unit             VARCHAR(20) NOT NULL,
    cost_per_unit    NUMERIC(19,4) NOT NULL,
    reorder_level    NUMERIC(12,2),
    last_restock_date DATE,
    expiration_date  DATE,
    created_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ------------------------------------------------------------
-- Table 6: trading.commodity_prices
-- Source: Trading.CommodityPrices
-- Dependencies: crop_management.crop_types
-- Notes: MONEY → NUMERIC(19,4)
-- ------------------------------------------------------------
CREATE TABLE trading.commodity_prices (
    price_id        SERIAL PRIMARY KEY,
    crop_type_id    INT NOT NULL,
    market_date     DATE NOT NULL,
    price_per_bushel NUMERIC(19,4) NOT NULL,
    market_name     VARCHAR(100),
    created_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_prices_crop_type FOREIGN KEY (crop_type_id)
        REFERENCES crop_management.crop_types(crop_type_id)
);

-- ------------------------------------------------------------
-- Table 7: audit.harvest_audit_log
-- Source: Audit.HarvestAuditLog (implied by trigger)
-- Dependencies: NONE
-- Notes: FOR JSON AUTO → JSONB; SUSER_SNAME() → current_user
-- ------------------------------------------------------------
CREATE TABLE audit.harvest_audit_log (
    audit_id     SERIAL PRIMARY KEY,
    harvest_id   INT NOT NULL,
    change_type  VARCHAR(10) NOT NULL
                     CHECK (change_type IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_by   VARCHAR(100) NOT NULL DEFAULT current_user,
    change_date  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_value    JSONB,
    new_value    JSONB
);
```

### 3.3 Index Creation

```sql
-- ============================================================
-- Script 1C: Index Creation
-- ============================================================

-- members.member_accounts
CREATE INDEX idx_members_number ON members.member_accounts(member_number);
CREATE INDEX idx_members_name   ON members.member_accounts(last_name, first_name);

-- crop_management.crop_types
CREATE INDEX idx_crop_types_name   ON crop_management.crop_types(name);
CREATE INDEX idx_crop_types_season ON crop_management.crop_types(growing_season);

-- crop_management.fields (B-tree + GiST spatial)
CREATE INDEX idx_fields_member       ON crop_management.fields(member_id);
CREATE INDEX idx_fields_current_crop ON crop_management.fields(current_crop_id);
CREATE INDEX idx_fields_gps_boundary ON crop_management.fields USING GIST (gps_boundary);

-- crop_management.harvests
CREATE INDEX idx_harvests_field ON crop_management.harvests(field_id);
CREATE INDEX idx_harvests_date  ON crop_management.harvests(harvest_date);

-- inventory.fertilizer_stock
CREATE INDEX idx_fertilizer_product ON inventory.fertilizer_stock(product_name);

-- trading.commodity_prices
CREATE INDEX idx_prices_crop_date ON trading.commodity_prices(crop_type_id, market_date);

-- audit.harvest_audit_log
CREATE INDEX idx_audit_harvest_id  ON audit.harvest_audit_log(harvest_id);
CREATE INDEX idx_audit_change_date ON audit.harvest_audit_log(change_date);
CREATE INDEX idx_audit_change_type ON audit.harvest_audit_log(change_type);
```

### 3.4 Constraint and Foreign Key Summary

| Constraint Name | Table | Type | References |
|---|---|---|---|
| `member_accounts_pkey` | `members.member_accounts` | PRIMARY KEY | — |
| `member_accounts_member_number_key` | `members.member_accounts` | UNIQUE | — |
| `crop_types_pkey` | `crop_management.crop_types` | PRIMARY KEY | — |
| `fields_pkey` | `crop_management.fields` | PRIMARY KEY | — |
| `fk_fields_member` | `crop_management.fields` | FOREIGN KEY | `members.member_accounts(member_id)` |
| `fk_fields_crop` | `crop_management.fields` | FOREIGN KEY | `crop_management.crop_types(crop_type_id)` |
| `harvests_pkey` | `crop_management.harvests` | PRIMARY KEY | — |
| `fk_harvests_field` | `crop_management.harvests` | FOREIGN KEY | `crop_management.fields(field_id)` |
| `fk_harvests_crop_type` | `crop_management.harvests` | FOREIGN KEY | `crop_management.crop_types(crop_type_id)` |
| `fertilizer_stock_pkey` | `inventory.fertilizer_stock` | PRIMARY KEY | — |
| `commodity_prices_pkey` | `trading.commodity_prices` | PRIMARY KEY | — |
| `fk_prices_crop_type` | `trading.commodity_prices` | FOREIGN KEY | `crop_management.crop_types(crop_type_id)` |
| `harvest_audit_log_pkey` | `audit.harvest_audit_log` | PRIMARY KEY | — |
| `harvest_audit_log_change_type_check` | `audit.harvest_audit_log` | CHECK | `change_type IN ('INSERT','UPDATE','DELETE')` |

---

## 4. Script 2 — PL/pgSQL Function: calculate_yield_bushels

> **Source:** `dbo.fn_CalculateYieldBushels`
>
> **Critical:** This function must be created **before** the `crop_management.harvests` table because the `yield_bushels` generated column references it. The function must be marked `IMMUTABLE`.

```sql
-- ============================================================
-- Script 2: Scalar Function — calculate_yield_bushels
-- Source: dbo.fn_CalculateYieldBushels (T-SQL)
-- Schema: crop_management
-- Volatility: IMMUTABLE (required for GENERATED ALWAYS AS)
-- ============================================================

CREATE OR REPLACE FUNCTION crop_management.calculate_yield_bushels(
    p_quantity  NUMERIC,
    p_unit_type VARCHAR
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Convert various harvest measurement units to bushels
    RETURN CASE p_unit_type
        WHEN 'bushels'       THEN p_quantity
        WHEN 'tonnes'        THEN p_quantity * 36.7437    -- 1 tonne ≈ 36.7437 bushels (wheat basis)
        WHEN 'hundredweight' THEN p_quantity * 1.667      -- 1 cwt ≈ 1.667 bushels
        WHEN 'kilograms'     THEN p_quantity * 0.0367437  -- 1 kg ≈ 0.0367437 bushels
        ELSE p_quantity  -- Default: assume bushels if unit is unknown
    END;
END;
$$;

COMMENT ON FUNCTION crop_management.calculate_yield_bushels(NUMERIC, VARCHAR) IS
    'Converts harvest quantity from various units (tonnes, hundredweight, kilograms) to bushels. '
    'Marked IMMUTABLE for use in the yield_bushels generated column on crop_management.harvests.';
```

**Key Conversion Notes:**

| SQL Server (T-SQL) | PostgreSQL (PL/pgSQL) |
|---|---|
| `CREATE FUNCTION dbo.fn_CalculateYieldBushels` | `CREATE OR REPLACE FUNCTION crop_management.calculate_yield_bushels` |
| `@Quantity DECIMAL(12,2)` | `p_quantity NUMERIC` |
| `@UnitType NVARCHAR(20)` | `p_unit_type VARCHAR` |
| `RETURNS DECIMAL(12,2)` | `RETURNS NUMERIC(12,2)` |
| `DECLARE @Bushels DECIMAL(12,2); SET @Bushels = CASE ...` | `RETURN CASE ... END;` (direct return) |
| No volatility annotation | `IMMUTABLE` (required for generated columns) |
| `dbo` schema | `crop_management` schema (co-located with table) |

---

## 5. Script 3 — Audit Trigger Function and Trigger Definition

> **Source:** `tr_AuditHarvestChanges` (T-SQL AFTER trigger)
>
> PostgreSQL separates trigger logic into a **trigger function** (the logic) and a **trigger definition** (the binding to a table).

### 5.1 Trigger Function

```sql
-- ============================================================
-- Script 3A: Trigger Function — fn_audit_harvest_changes
-- Source: tr_AuditHarvestChanges (T-SQL)
-- Schema: audit
-- Notes:
--   - TG_OP replaces inserted/deleted pseudo-table checks
--   - row_to_json() replaces FOR JSON AUTO
--   - current_user replaces SUSER_SNAME()
--   - FOR EACH ROW (PostgreSQL) vs statement-level (SQL Server)
-- ============================================================

CREATE OR REPLACE FUNCTION audit.fn_audit_harvest_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.harvest_audit_log
            (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES
            (NEW.harvest_id, 'INSERT', current_user, CURRENT_TIMESTAMP,
             NULL, row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.harvest_audit_log
            (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES
            (NEW.harvest_id, 'UPDATE', current_user, CURRENT_TIMESTAMP,
             row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.harvest_audit_log
            (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES
            (OLD.harvest_id, 'DELETE', current_user, CURRENT_TIMESTAMP,
             row_to_json(OLD)::jsonb, NULL);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION audit.fn_audit_harvest_changes() IS
    'Trigger function for regulatory compliance auditing of harvest data changes. '
    'Logs INSERT, UPDATE, and DELETE operations with JSONB payloads to audit.harvest_audit_log.';
```

### 5.2 Trigger Definition

```sql
-- ============================================================
-- Script 3B: Trigger Binding
-- Binds fn_audit_harvest_changes to crop_management.harvests
-- ============================================================

CREATE TRIGGER trg_audit_harvest_changes
    AFTER INSERT OR UPDATE OR DELETE
    ON crop_management.harvests
    FOR EACH ROW
    EXECUTE FUNCTION audit.fn_audit_harvest_changes();
```

### 5.3 SQL Server vs PostgreSQL Comparison

| Aspect | SQL Server (`tr_AuditHarvestChanges`) | PostgreSQL (`fn_audit_harvest_changes`) |
|---|---|---|
| Architecture | Single trigger body on table | Separate trigger function + trigger binding |
| Row access | `inserted` / `deleted` pseudo-tables | `NEW` / `OLD` record variables |
| Operation detection | `EXISTS (SELECT * FROM inserted)` | `TG_OP` variable (`'INSERT'`, `'UPDATE'`, `'DELETE'`) |
| JSON serialization | `FOR JSON AUTO` | `row_to_json(NEW)::jsonb` |
| Current user | `SUSER_SNAME()` | `current_user` |
| Execution model | Statement-level (once per statement) | `FOR EACH ROW` (once per affected row) |
| SET NOCOUNT | `SET NOCOUNT ON` required | Not applicable in PostgreSQL |
| Return value | Not required | Must `RETURN NEW` / `RETURN OLD` / `RETURN NULL` |

---

## 6. Script 4 — View Creation

> **Source:** `CropManagement.vw_FieldProductivity`

```sql
-- ============================================================
-- Script 4: View — vw_field_productivity
-- Source: CropManagement.vw_FieldProductivity
-- Dependencies: fields, member_accounts, crop_types, harvests
-- Notes:
--   - String concatenation: + → ||
--   - All identifiers converted to snake_case
-- ============================================================

CREATE OR REPLACE VIEW crop_management.vw_field_productivity AS
SELECT
    f.field_id,
    f.field_name,
    m.member_number,
    m.first_name || ' ' || m.last_name AS member_name,
    f.acreage,
    ct.name                            AS current_crop,
    SUM(h.yield_bushels)               AS total_yield,
    SUM(h.yield_bushels) / f.acreage   AS yield_per_acre,
    COUNT(h.harvest_id)                AS harvest_count,
    MAX(h.harvest_date)                AS last_harvest_date
FROM crop_management.fields f
INNER JOIN members.member_accounts m
    ON f.member_id = m.member_id
LEFT JOIN crop_management.crop_types ct
    ON f.current_crop_id = ct.crop_type_id
LEFT JOIN crop_management.harvests h
    ON f.field_id = h.field_id
GROUP BY
    f.field_id,
    f.field_name,
    m.member_number,
    m.first_name,
    m.last_name,
    f.acreage,
    ct.name;

COMMENT ON VIEW crop_management.vw_field_productivity IS
    'Aggregated field-level productivity metrics: total yield, yield per acre, harvest count, and last harvest date.';
```

**Key Conversion:**

| SQL Server | PostgreSQL |
|---|---|
| `m.FirstName + ' ' + m.LastName` | `m.first_name \|\| ' ' \|\| m.last_name` |

---

## 7. Script 5 — DML Migration (Seed & Sample Data)

### 7.1 Seed Data: crop_types

> **Source:** `Data/SeedData/CropTypes.sql`

```sql
-- ============================================================
-- Script 5A: Seed Data — crop_types
-- Source: CropManagement.CropTypes seed data
-- Notes:
--   - Column names converted to snake_case
--   - NVARCHAR values unchanged (PostgreSQL VARCHAR is UTF-8)
--   - created_date / modified_date default to CURRENT_TIMESTAMP
-- ============================================================

INSERT INTO crop_management.crop_types
    (name, growing_season, days_to_maturity, min_temperature, max_temperature, water_requirement)
VALUES
    ('Corn',     'Spring/Summer', 120, 10.0, 30.0, 'High'),
    ('Soybeans', 'Spring/Summer', 100, 15.0, 28.0, 'Medium'),
    ('Wheat',    'Fall/Winter',   180,  0.0, 25.0, 'Low'),
    ('Barley',   'Spring',         90,  5.0, 22.0, 'Medium'),
    ('Oats',     'Spring',         80,  7.0, 20.0, 'Medium');
```

### 7.2 Sample Data: member_accounts

> **Source:** `Data/SampleData/Members.sql`

```sql
-- ============================================================
-- Script 5B: Sample Data — member_accounts
-- Source: Members.MemberAccounts sample data
-- Notes:
--   - Column names converted to snake_case
--   - membership_date uses ISO 8601 DATE format (unchanged)
--   - status defaults to 'Active' if not specified
--   - address, city, state, zip_code omitted (NULL in source)
-- ============================================================

INSERT INTO members.member_accounts
    (member_number, first_name, last_name, email, phone_number, membership_date, status)
VALUES
    ('M001', 'John',   'Smith',    'jsmith@email.com',     '555-0101', '2020-01-15', 'Active'),
    ('M002', 'Mary',   'Johnson',  'mjohnson@email.com',   '555-0102', '2019-05-20', 'Active'),
    ('M003', 'Robert', 'Williams', 'rwilliams@email.com',  '555-0103', '2021-03-10', 'Active');
```

### 7.3 DML Conversion Notes

| SQL Server Syntax | PostgreSQL Syntax | Applied In |
|---|---|---|
| `INSERT INTO CropManagement.CropTypes (Name, ...)` | `INSERT INTO crop_management.crop_types (name, ...)` | Schema + column to snake_case |
| `NVARCHAR` string values `N'...'` | `VARCHAR` string values `'...'` | N-prefix not needed (UTF-8 native) |
| `IDENTITY(1,1)` auto-increment | `SERIAL` auto-increment | ID columns omitted from INSERT |
| `DEFAULT GETDATE()` | `DEFAULT CURRENT_TIMESTAMP` | Timestamp columns omitted from INSERT |

---

## 8. Script 6 — Stored Procedure Migration

### 8.1 calculate_optimal_rotation

> **Source:** `CropPlanning.sp_CalculateOptimalRotation`
>
> SQL Server stored procedure → PL/pgSQL function returning `TABLE`.

```sql
-- ============================================================
-- Script 6A: Stored Procedure → PL/pgSQL Function
-- Source: CropPlanning.sp_CalculateOptimalRotation
-- Target: crop_management.calculate_optimal_rotation
-- Return: RETURNS TABLE (set-returning function)
-- Notes:
--   - SET NOCOUNT ON → not needed in PostgreSQL
--   - SELECT TOP 1 → LIMIT 1
--   - Local variables via DECLARE block
--   - CTE syntax identical; column names to snake_case
-- ============================================================

CREATE OR REPLACE FUNCTION crop_management.calculate_optimal_rotation(
    p_field_id     INT,
    p_current_year INT
)
RETURNS TABLE (
    crop_type_id   INT,
    name           VARCHAR,
    rotation_score NUMERIC,
    current_price  NUMERIC(19,4),
    total_score    NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_crop_id INT;
    v_soil_type    VARCHAR(50);
BEGIN
    -- Retrieve current crop and soil type for the field
    SELECT f.current_crop_id, f.soil_type
    INTO v_last_crop_id, v_soil_type
    FROM crop_management.fields f
    WHERE f.field_id = p_field_id;

    -- Calculate optimal rotation based on:
    -- 1. Previous crop (rotation rules)
    -- 2. Soil type
    -- 3. Current market prices
    RETURN QUERY
    WITH rotation_rules AS (
        SELECT
            ct.crop_type_id,
            ct.name,
            CASE
                WHEN v_last_crop_id = 1 THEN 10  -- After corn, prefer soybeans
                WHEN v_last_crop_id = 2 THEN 5   -- After soybeans, any crop ok
                ELSE 7
            END AS rotation_score,
            cp.price_per_bushel AS current_price
        FROM crop_management.crop_types ct
        LEFT JOIN trading.commodity_prices cp
            ON ct.crop_type_id = cp.crop_type_id
            AND cp.market_date = (
                SELECT MAX(sub.market_date)
                FROM trading.commodity_prices sub
                WHERE sub.crop_type_id = ct.crop_type_id
            )
        WHERE ct.crop_type_id != v_last_crop_id
    )
    SELECT
        rr.crop_type_id,
        rr.name,
        rr.rotation_score,
        rr.current_price,
        (rr.rotation_score * 0.6 + (rr.current_price / 10) * 0.4) AS total_score
    FROM rotation_rules rr
    ORDER BY total_score DESC
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION crop_management.calculate_optimal_rotation(INT, INT) IS
    'Calculates the optimal crop rotation recommendation for a field based on '
    'previous crop history, soil type, and current market prices. '
    'Returns the single best crop candidate with scoring breakdown.';
```

**Conversion Details:**

| SQL Server Pattern | PostgreSQL Equivalent |
|---|---|
| `CREATE PROCEDURE CropPlanning.sp_CalculateOptimalRotation` | `CREATE OR REPLACE FUNCTION crop_management.calculate_optimal_rotation` |
| `@FieldId INT, @CurrentYear INT` | `p_field_id INT, p_current_year INT` |
| `SET NOCOUNT ON` | *(removed — not applicable)* |
| `DECLARE @LastCropId INT` | `DECLARE v_last_crop_id INT` |
| `SELECT @LastCropId = CurrentCropId` | `SELECT ... INTO v_last_crop_id` |
| `SELECT TOP 1 ... ORDER BY TotalScore DESC` | `ORDER BY total_score DESC LIMIT 1` |
| Implicit result set | `RETURNS TABLE (...)` + `RETURN QUERY` |

### 8.2 calculate_member_payment

> **Source:** `Settlement.sp_CalculateMemberPayment`
>
> SQL Server stored procedure with OUTPUT parameter → PL/pgSQL function returning `NUMERIC`.

```sql
-- ============================================================
-- Script 6B: Stored Procedure → PL/pgSQL Function
-- Source: Settlement.sp_CalculateMemberPayment
-- Target: trading.calculate_member_payment
-- Return: RETURNS NUMERIC(19,4) (replaces OUTPUT parameter)
-- Notes:
--   - @TotalPayment MONEY OUTPUT → RETURNS NUMERIC(19,4)
--   - YEAR(date) → EXTRACT(YEAR FROM date)
--   - CAST(col AS type) → col::type
--   - MONEY arithmetic → NUMERIC(19,4) arithmetic
--   - TOP 1 → LIMIT 1
-- ============================================================

CREATE OR REPLACE FUNCTION trading.calculate_member_payment(
    p_member_id       INT,
    p_settlement_year INT
)
RETURNS NUMERIC(19,4)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_yield        NUMERIC(12,2);
    v_average_grade      NUMERIC(5,2);
    v_quality_multiplier NUMERIC(5,3);
    v_total_payment      NUMERIC(19,4);
BEGIN
    -- Calculate total yield for member in settlement year
    SELECT SUM(h.yield_bushels)
    INTO v_total_yield
    FROM crop_management.harvests h
    INNER JOIN crop_management.fields f ON h.field_id = f.field_id
    WHERE f.member_id = p_member_id
      AND EXTRACT(YEAR FROM h.harvest_date) = p_settlement_year;

    -- Calculate average grade
    SELECT AVG(h.grade_code::NUMERIC(5,2))
    INTO v_average_grade
    FROM crop_management.harvests h
    INNER JOIN crop_management.fields f ON h.field_id = f.field_id
    WHERE f.member_id = p_member_id
      AND EXTRACT(YEAR FROM h.harvest_date) = p_settlement_year;

    -- Quality multiplier based on grade
    v_quality_multiplier := CASE
        WHEN v_average_grade >= 90 THEN 1.15
        WHEN v_average_grade >= 80 THEN 1.10
        WHEN v_average_grade >= 70 THEN 1.05
        ELSE 1.00
    END;

    -- Calculate payment with quality bonus using latest commodity price
    SELECT v_total_yield * cp.price_per_bushel * v_quality_multiplier
    INTO v_total_payment
    FROM trading.commodity_prices cp
    WHERE cp.market_date = (
        SELECT MAX(sub.market_date)
        FROM trading.commodity_prices sub
        WHERE EXTRACT(YEAR FROM sub.market_date) = p_settlement_year
    )
    AND cp.crop_type_id = (
        SELECT h.crop_type_id
        FROM crop_management.harvests h
        INNER JOIN crop_management.fields f ON h.field_id = f.field_id
        WHERE f.member_id = p_member_id
        GROUP BY h.crop_type_id
        ORDER BY SUM(h.yield_bushels) DESC
        LIMIT 1
    );

    RETURN v_total_payment;
END;
$$;

COMMENT ON FUNCTION trading.calculate_member_payment(INT, INT) IS
    'Calculates end-of-year settlement payment for a cooperative member. '
    'Based on total yield, grade quality multiplier, and latest commodity prices. '
    'Returns the total payment amount as NUMERIC(19,4).';
```

**Conversion Details:**

| SQL Server Pattern | PostgreSQL Equivalent |
|---|---|
| `CREATE PROCEDURE Settlement.sp_CalculateMemberPayment` | `CREATE OR REPLACE FUNCTION trading.calculate_member_payment` |
| `@MemberId INT, @SettlementYear INT` | `p_member_id INT, p_settlement_year INT` |
| `@TotalPayment MONEY OUTPUT` | `RETURNS NUMERIC(19,4)` |
| `SET NOCOUNT ON` | *(removed — not applicable)* |
| `DECLARE @TotalYield DECIMAL(12,2)` | `DECLARE v_total_yield NUMERIC(12,2)` |
| `SELECT @TotalYield = SUM(...)` | `SELECT SUM(...) INTO v_total_yield` |
| `YEAR(h.HarvestDate)` | `EXTRACT(YEAR FROM h.harvest_date)` |
| `CAST(h.GradeCode AS DECIMAL(5,2))` | `h.grade_code::NUMERIC(5,2)` |
| `SET @QualityMultiplier = CASE ...` | `v_quality_multiplier := CASE ... END` |
| `SELECT TOP 1 ... ORDER BY SUM(...) DESC` | `ORDER BY SUM(...) DESC LIMIT 1` |
| `RETURN 0` (success code) | `RETURN v_total_payment` (actual value) |

---

## 9. Script 7 — Rollback Scripts

> Execute in **reverse dependency order** to cleanly remove all migrated objects.
> Use these scripts if migration fails and you need to restore the database to pre-migration state.

```sql
-- ============================================================
-- Script 7: Rollback — Complete Migration Reversal
-- Execute in REVERSE dependency order
-- WARNING: This will permanently delete all migrated data!
-- ============================================================

-- Step 1: Drop stored procedure functions
DROP FUNCTION IF EXISTS trading.calculate_member_payment(INT, INT);
DROP FUNCTION IF EXISTS crop_management.calculate_optimal_rotation(INT, INT);

-- Step 2: Drop view
DROP VIEW IF EXISTS crop_management.vw_field_productivity;

-- Step 3: Drop trigger (must be dropped before trigger function)
DROP TRIGGER IF EXISTS trg_audit_harvest_changes ON crop_management.harvests;

-- Step 4: Drop trigger function
DROP FUNCTION IF EXISTS audit.fn_audit_harvest_changes();

-- Step 5: Drop tables in reverse dependency order
-- (child tables with FKs first, then parent tables)
DROP TABLE IF EXISTS audit.harvest_audit_log;
DROP TABLE IF EXISTS trading.commodity_prices;
DROP TABLE IF EXISTS inventory.fertilizer_stock;
DROP TABLE IF EXISTS crop_management.harvests;
DROP TABLE IF EXISTS crop_management.fields;
DROP TABLE IF EXISTS crop_management.crop_types;
DROP TABLE IF EXISTS members.member_accounts;

-- Step 6: Drop the yield calculation function
-- (must be after harvests table which has a generated column referencing it)
DROP FUNCTION IF EXISTS crop_management.calculate_yield_bushels(NUMERIC, VARCHAR);

-- Step 7: Drop schemas (only if empty; CASCADE would drop remaining objects)
DROP SCHEMA IF EXISTS audit;
DROP SCHEMA IF EXISTS trading;
DROP SCHEMA IF EXISTS inventory;
DROP SCHEMA IF EXISTS crop_management;
DROP SCHEMA IF EXISTS members;

-- Step 8: Drop extensions
DROP EXTENSION IF EXISTS postgis;
```

### Rollback Dependency Order Explanation

```
Drop Order (reverse of creation):
─────────────────────────────────
 1. Functions (stored procs)      ← no dependents
 2. View (vw_field_productivity)  ← no dependents
 3. Trigger (trg_audit_...)       ← bound to harvests table
 4. Trigger function (fn_audit_.) ← referenced by trigger
 5. audit.harvest_audit_log       ← no FK dependents
 6. trading.commodity_prices      ← no FK dependents
 7. inventory.fertilizer_stock    ← no FK dependents
 8. crop_management.harvests      ← FK refs fields, crop_types; gen col refs function
 9. crop_management.fields        ← FK refs member_accounts, crop_types
10. crop_management.crop_types    ← referenced by fields, harvests, commodity_prices
11. members.member_accounts       ← referenced by fields
12. Function (calculate_yield_.)  ← referenced by harvests generated column
13. Schemas                       ← contain all above objects
14. Extension (postgis)           ← GEOMETRY type used by fields
```

---

## 10. Post-Migration Checklist

| # | Task | Status | Validation Query / Action |
|---|---|---|---|
| 1 | Verify all schemas exist | ☐ | `SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('crop_management','members','inventory','trading','audit');` |
| 2 | Verify all tables created (7 total) | ☐ | `SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema IN ('crop_management','members','inventory','trading','audit') ORDER BY table_schema, table_name;` |
| 3 | Verify row counts match source | ☐ | `SELECT 'crop_types' AS tbl, COUNT(*) FROM crop_management.crop_types UNION ALL SELECT 'member_accounts', COUNT(*) FROM members.member_accounts;` |
| 4 | Verify computed column (yield_bushels) | ☐ | `SELECT crop_management.calculate_yield_bushels(100, 'tonnes');` → should return `3674.37` |
| 5 | Verify generated column works on INSERT | ☐ | Insert a test harvest row; confirm `yield_bushels` is auto-calculated |
| 6 | Verify audit trigger fires | ☐ | Insert/update/delete a harvest; check `audit.harvest_audit_log` for entries |
| 7 | Verify view returns data | ☐ | `SELECT * FROM crop_management.vw_field_productivity LIMIT 5;` |
| 8 | Verify foreign key constraints | ☐ | Attempt to insert a field with invalid `member_id`; should fail |
| 9 | Verify indexes exist (16 total) | ☐ | `SELECT schemaname, tablename, indexname FROM pg_indexes WHERE schemaname IN ('crop_management','members','inventory','trading','audit');` |
| 10 | Verify PostGIS extension active | ☐ | `SELECT PostGIS_Version();` |
| 11 | Verify stored procedure functions | ☐ | `SELECT * FROM crop_management.calculate_optimal_rotation(1, 2026);` |
| 12 | Verify spatial index (GiST) | ☐ | `SELECT indexname FROM pg_indexes WHERE indexname = 'idx_fields_gps_boundary';` |
| 13 | Run full validation suite | ☐ | Execute `Migration/Validation/validation_queries.sql` |
| 14 | Performance baseline test | ☐ | Run `EXPLAIN ANALYZE` on key queries |
| 15 | Update application connection strings | ☐ | Switch from SQL Server to PostgreSQL connection |
| 16 | Notify stakeholders of completion | ☐ | Send migration completion report |

---

## Appendix A — Complete Single-File Migration Script

For convenience, below is the recommended execution sequence as a single transaction:

```sql
-- ============================================================
-- COMPLETE MIGRATION SCRIPT — Execute as single transaction
-- Database: greenharvest
-- ============================================================

BEGIN;

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Schemas
CREATE SCHEMA IF NOT EXISTS crop_management;
CREATE SCHEMA IF NOT EXISTS members;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS audit;

-- 3. Function (MUST precede harvests table)
CREATE OR REPLACE FUNCTION crop_management.calculate_yield_bushels(
    p_quantity NUMERIC, p_unit_type VARCHAR
) RETURNS NUMERIC(12,2) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    RETURN CASE p_unit_type
        WHEN 'bushels'       THEN p_quantity
        WHEN 'tonnes'        THEN p_quantity * 36.7437
        WHEN 'hundredweight' THEN p_quantity * 1.667
        WHEN 'kilograms'     THEN p_quantity * 0.0367437
        ELSE p_quantity
    END;
END; $$;

-- 4. Tables
CREATE TABLE members.member_accounts (
    member_id SERIAL PRIMARY KEY, member_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL, last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100), phone_number VARCHAR(20), address VARCHAR(200),
    city VARCHAR(50), state VARCHAR(2), zip_code VARCHAR(10),
    membership_date DATE NOT NULL, status VARCHAR(20) DEFAULT 'Active',
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE crop_management.crop_types (
    crop_type_id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL,
    growing_season VARCHAR(50) NOT NULL, days_to_maturity INT NOT NULL,
    min_temperature NUMERIC(5,2), max_temperature NUMERIC(5,2),
    water_requirement VARCHAR(20),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE crop_management.fields (
    field_id SERIAL PRIMARY KEY, member_id INT NOT NULL,
    field_name VARCHAR(100) NOT NULL, acreage NUMERIC(10,2) NOT NULL,
    soil_type VARCHAR(50), irrigation_type VARCHAR(50),
    gps_boundary GEOMETRY(POLYGON, 4326), current_crop_id INT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fields_member FOREIGN KEY (member_id) REFERENCES members.member_accounts(member_id),
    CONSTRAINT fk_fields_crop FOREIGN KEY (current_crop_id) REFERENCES crop_management.crop_types(crop_type_id)
);

CREATE TABLE crop_management.harvests (
    harvest_id SERIAL PRIMARY KEY, field_id INT NOT NULL, crop_type_id INT NOT NULL,
    harvest_date DATE NOT NULL, quantity NUMERIC(12,2) NOT NULL,
    unit_type VARCHAR(20) NOT NULL,
    yield_bushels NUMERIC(12,2) GENERATED ALWAYS AS (
        crop_management.calculate_yield_bushels(quantity, unit_type)) STORED,
    moisture_content NUMERIC(5,2), grade_code VARCHAR(10),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_harvests_field FOREIGN KEY (field_id) REFERENCES crop_management.fields(field_id),
    CONSTRAINT fk_harvests_crop_type FOREIGN KEY (crop_type_id) REFERENCES crop_management.crop_types(crop_type_id)
);

CREATE TABLE inventory.fertilizer_stock (
    stock_id SERIAL PRIMARY KEY, product_name VARCHAR(100) NOT NULL,
    manufacturer_name VARCHAR(100), quantity_on_hand NUMERIC(12,2) NOT NULL,
    unit VARCHAR(20) NOT NULL, cost_per_unit NUMERIC(19,4) NOT NULL,
    reorder_level NUMERIC(12,2), last_restock_date DATE, expiration_date DATE,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trading.commodity_prices (
    price_id SERIAL PRIMARY KEY, crop_type_id INT NOT NULL,
    market_date DATE NOT NULL, price_per_bushel NUMERIC(19,4) NOT NULL,
    market_name VARCHAR(100), created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_prices_crop_type FOREIGN KEY (crop_type_id) REFERENCES crop_management.crop_types(crop_type_id)
);

CREATE TABLE audit.harvest_audit_log (
    audit_id SERIAL PRIMARY KEY, harvest_id INT NOT NULL,
    change_type VARCHAR(10) NOT NULL CHECK (change_type IN ('INSERT','UPDATE','DELETE')),
    changed_by VARCHAR(100) NOT NULL DEFAULT current_user,
    change_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_value JSONB, new_value JSONB
);

-- 5. Indexes
CREATE INDEX idx_members_number ON members.member_accounts(member_number);
CREATE INDEX idx_members_name ON members.member_accounts(last_name, first_name);
CREATE INDEX idx_crop_types_name ON crop_management.crop_types(name);
CREATE INDEX idx_crop_types_season ON crop_management.crop_types(growing_season);
CREATE INDEX idx_fields_member ON crop_management.fields(member_id);
CREATE INDEX idx_fields_current_crop ON crop_management.fields(current_crop_id);
CREATE INDEX idx_fields_gps_boundary ON crop_management.fields USING GIST (gps_boundary);
CREATE INDEX idx_harvests_field ON crop_management.harvests(field_id);
CREATE INDEX idx_harvests_date ON crop_management.harvests(harvest_date);
CREATE INDEX idx_fertilizer_product ON inventory.fertilizer_stock(product_name);
CREATE INDEX idx_prices_crop_date ON trading.commodity_prices(crop_type_id, market_date);
CREATE INDEX idx_audit_harvest_id ON audit.harvest_audit_log(harvest_id);
CREATE INDEX idx_audit_change_date ON audit.harvest_audit_log(change_date);
CREATE INDEX idx_audit_change_type ON audit.harvest_audit_log(change_type);

-- 6. Trigger function + binding
CREATE OR REPLACE FUNCTION audit.fn_audit_harvest_changes() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (NEW.harvest_id, 'INSERT', current_user, CURRENT_TIMESTAMP, NULL, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (NEW.harvest_id, 'UPDATE', current_user, CURRENT_TIMESTAMP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (OLD.harvest_id, 'DELETE', current_user, CURRENT_TIMESTAMP, row_to_json(OLD)::jsonb, NULL);
        RETURN OLD;
    END IF;
    RETURN NULL;
END; $$;

CREATE TRIGGER trg_audit_harvest_changes
    AFTER INSERT OR UPDATE OR DELETE ON crop_management.harvests
    FOR EACH ROW EXECUTE FUNCTION audit.fn_audit_harvest_changes();

-- 7. View
CREATE OR REPLACE VIEW crop_management.vw_field_productivity AS
SELECT f.field_id, f.field_name, m.member_number,
    m.first_name || ' ' || m.last_name AS member_name,
    f.acreage, ct.name AS current_crop,
    SUM(h.yield_bushels) AS total_yield,
    SUM(h.yield_bushels) / f.acreage AS yield_per_acre,
    COUNT(h.harvest_id) AS harvest_count,
    MAX(h.harvest_date) AS last_harvest_date
FROM crop_management.fields f
INNER JOIN members.member_accounts m ON f.member_id = m.member_id
LEFT JOIN crop_management.crop_types ct ON f.current_crop_id = ct.crop_type_id
LEFT JOIN crop_management.harvests h ON f.field_id = h.field_id
GROUP BY f.field_id, f.field_name, m.member_number, m.first_name, m.last_name, f.acreage, ct.name;

-- 8. Seed data
INSERT INTO crop_management.crop_types (name, growing_season, days_to_maturity, min_temperature, max_temperature, water_requirement)
VALUES ('Corn','Spring/Summer',120,10.0,30.0,'High'),('Soybeans','Spring/Summer',100,15.0,28.0,'Medium'),
    ('Wheat','Fall/Winter',180,0.0,25.0,'Low'),('Barley','Spring',90,5.0,22.0,'Medium'),('Oats','Spring',80,7.0,20.0,'Medium');

INSERT INTO members.member_accounts (member_number, first_name, last_name, email, phone_number, membership_date, status)
VALUES ('M001','John','Smith','jsmith@email.com','555-0101','2020-01-15','Active'),
    ('M002','Mary','Johnson','mjohnson@email.com','555-0102','2019-05-20','Active'),
    ('M003','Robert','Williams','rwilliams@email.com','555-0103','2021-03-10','Active');

-- 9. Stored procedure functions
CREATE OR REPLACE FUNCTION crop_management.calculate_optimal_rotation(
    p_field_id INT, p_current_year INT
) RETURNS TABLE (crop_type_id INT, name VARCHAR, rotation_score NUMERIC, current_price NUMERIC(19,4), total_score NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE v_last_crop_id INT; v_soil_type VARCHAR(50);
BEGIN
    SELECT f.current_crop_id, f.soil_type INTO v_last_crop_id, v_soil_type
    FROM crop_management.fields f WHERE f.field_id = p_field_id;
    RETURN QUERY
    WITH rotation_rules AS (
        SELECT ct.crop_type_id, ct.name,
            CASE WHEN v_last_crop_id = 1 THEN 10 WHEN v_last_crop_id = 2 THEN 5 ELSE 7 END AS rotation_score,
            cp.price_per_bushel AS current_price
        FROM crop_management.crop_types ct
        LEFT JOIN trading.commodity_prices cp ON ct.crop_type_id = cp.crop_type_id
            AND cp.market_date = (SELECT MAX(sub.market_date) FROM trading.commodity_prices sub WHERE sub.crop_type_id = ct.crop_type_id)
        WHERE ct.crop_type_id != v_last_crop_id
    )
    SELECT rr.crop_type_id, rr.name, rr.rotation_score, rr.current_price,
        (rr.rotation_score * 0.6 + (rr.current_price / 10) * 0.4) AS total_score
    FROM rotation_rules rr ORDER BY total_score DESC LIMIT 1;
END; $$;

CREATE OR REPLACE FUNCTION trading.calculate_member_payment(
    p_member_id INT, p_settlement_year INT
) RETURNS NUMERIC(19,4) LANGUAGE plpgsql AS $$
DECLARE v_total_yield NUMERIC(12,2); v_average_grade NUMERIC(5,2);
    v_quality_multiplier NUMERIC(5,3); v_total_payment NUMERIC(19,4);
BEGIN
    SELECT SUM(h.yield_bushels) INTO v_total_yield
    FROM crop_management.harvests h INNER JOIN crop_management.fields f ON h.field_id = f.field_id
    WHERE f.member_id = p_member_id AND EXTRACT(YEAR FROM h.harvest_date) = p_settlement_year;

    SELECT AVG(h.grade_code::NUMERIC(5,2)) INTO v_average_grade
    FROM crop_management.harvests h INNER JOIN crop_management.fields f ON h.field_id = f.field_id
    WHERE f.member_id = p_member_id AND EXTRACT(YEAR FROM h.harvest_date) = p_settlement_year;

    v_quality_multiplier := CASE
        WHEN v_average_grade >= 90 THEN 1.15 WHEN v_average_grade >= 80 THEN 1.10
        WHEN v_average_grade >= 70 THEN 1.05 ELSE 1.00 END;

    SELECT v_total_yield * cp.price_per_bushel * v_quality_multiplier INTO v_total_payment
    FROM trading.commodity_prices cp
    WHERE cp.market_date = (SELECT MAX(sub.market_date) FROM trading.commodity_prices sub
        WHERE EXTRACT(YEAR FROM sub.market_date) = p_settlement_year)
    AND cp.crop_type_id = (SELECT h.crop_type_id FROM crop_management.harvests h
        INNER JOIN crop_management.fields f ON h.field_id = f.field_id
        WHERE f.member_id = p_member_id GROUP BY h.crop_type_id
        ORDER BY SUM(h.yield_bushels) DESC LIMIT 1);

    RETURN v_total_payment;
END; $$;

COMMIT;
```

---

## Appendix B — Object Inventory

| Category | Count | Objects |
|---|---|---|
| Extensions | 1 | `postgis` |
| Schemas | 5 | `crop_management`, `members`, `inventory`, `trading`, `audit` |
| Tables | 7 | `member_accounts`, `crop_types`, `fields`, `harvests`, `fertilizer_stock`, `commodity_prices`, `harvest_audit_log` |
| Functions | 4 | `calculate_yield_bushels`, `fn_audit_harvest_changes`, `calculate_optimal_rotation`, `calculate_member_payment` |
| Triggers | 1 | `trg_audit_harvest_changes` |
| Views | 1 | `vw_field_productivity` |
| B-tree Indexes | 14 | See Section 3.3 |
| GiST Indexes | 1 | `idx_fields_gps_boundary` |
| CHECK Constraints | 1 | `change_type` on `harvest_audit_log` |
| Foreign Keys | 5 | See Section 3.4 |
