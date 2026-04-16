# Step 04 — Target PostgreSQL Schema Design

## GreenHarvest SQL Server → PostgreSQL Migration

| Attribute | Value |
|---|---|
| **Source System** | SQL Server 2012 Standard Edition |
| **Target System** | Azure Database for PostgreSQL — Flexible Server |
| **Database Name** | greenharvest |
| **Design Date** | 2026-04-16 |
| **PostGIS Version** | 3.x (required extension) |
| **Total Objects** | 7 Tables · 1 Function · 1 Trigger Function · 1 View · 10 Indexes |

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Schema Mapping](#2-schema-mapping)
3. [Naming Convention Mapping](#3-naming-convention-mapping)
4. [Data Type Conversion Table](#4-data-type-conversion-table)
5. [Extension Requirements](#5-extension-requirements)
6. [Complete Target Table DDL](#6-complete-target-table-ddl)
7. [PL/pgSQL Function — calculate_yield_bushels](#7-plpgsql-function--calculate_yield_bushels)
8. [Audit Log Table Design](#8-audit-log-table-design)
9. [PostgreSQL Trigger Function — Harvest Audit](#9-postgresql-trigger-function--harvest-audit)
10. [View — vw_field_productivity](#10-view--vw_field_productivity)
11. [Index Strategy](#11-index-strategy)
12. [Stored Procedure Conversions](#12-stored-procedure-conversions)

---

## 1. Design Principles

| # | Principle | Detail |
|---|---|---|
| 1 | **snake_case everywhere** | All identifiers — schemas, tables, columns, indexes, functions — use `snake_case`. PostgreSQL folds unquoted identifiers to lowercase; snake_case avoids the need for double-quoting. |
| 2 | **PostgreSQL-idiomatic types** | Use `SERIAL` for auto-increment, `VARCHAR` instead of `NVARCHAR` (PostgreSQL is natively UTF-8), `NUMERIC` instead of `MONEY`, `TIMESTAMP` instead of `DATETIME`. |
| 3 | **PostGIS for spatial data** | Replace SQL Server `GEOGRAPHY` with PostGIS `GEOMETRY(POLYGON, 4326)`. SRID 4326 (WGS 84) is the standard for GPS coordinates. GiST indexes replace SQL Server spatial indexes. |
| 4 | **Generated columns over computed** | SQL Server `PERSISTED` computed columns become PostgreSQL `GENERATED ALWAYS AS (...) STORED` columns. The referenced function must be `IMMUTABLE`. |
| 5 | **PL/pgSQL functions** | Scalar UDFs become `PL/pgSQL` functions. Stored procedures convert to `PL/pgSQL` functions returning `TABLE` or using `OUT` parameters. |
| 6 | **Trigger functions** | SQL Server `AFTER` triggers become PostgreSQL trigger functions using `TG_OP`, `row_to_json()`, and `current_user` instead of `FOR JSON AUTO` and `SUSER_SNAME()`. |
| 7 | **Explicit schema qualification** | All objects are schema-qualified. No reliance on `search_path` for production DDL. |
| 8 | **Inline foreign keys** | Use `REFERENCES` in column definitions for single-column FKs; named `CONSTRAINT` blocks for clarity on multi-purpose constraints. |

---

## 2. Schema Mapping

| SQL Server Schema | PostgreSQL Schema | Purpose |
|---|---|---|
| `CropManagement` | `crop_management` | Fields, crop types, harvests, planning |
| `Members` | `members` | Cooperative member accounts |
| `Inventory` | `inventory` | Fertilizer and input-supply stock |
| `Trading` | `trading` | Commodity market pricing |
| `Audit` | `audit` | Regulatory-compliance change logs |
| `dbo` | *(moved into owning schema)* | Shared functions relocated to `crop_management` |
| `CropPlanning` | `crop_management` | Rotation procedure merged into `crop_management` |
| `Settlement` | `trading` | Payment procedure merged into `trading` |

---

## 3. Naming Convention Mapping

| SQL Server Convention | PostgreSQL Convention | Example |
|---|---|---|
| `PascalCase` table names | `snake_case` table names | `CropTypes` → `crop_types` |
| `PascalCase` column names | `snake_case` column names | `CropTypeId` → `crop_type_id` |
| `IX_Table_Column` indexes | `idx_table_column` indexes | `IX_CropTypes_Name` → `idx_crop_types_name` |
| `FK_Child_Parent` constraints | `fk_child_parent` constraints | `FK_Fields_Member` → `fk_fields_member` |
| `fn_FunctionName` functions | `function_name` functions | `fn_CalculateYieldBushels` → `calculate_yield_bushels` |
| `sp_ProcedureName` procedures | `function_name` functions | `sp_CalculateOptimalRotation` → `calculate_optimal_rotation` |
| `tr_TriggerName` triggers | `trg_trigger_name` + `fn_trigger_name` | `tr_AuditHarvestChanges` → `trg_audit_harvest_changes` / `fn_audit_harvest_changes` |
| `vw_ViewName` views | `vw_view_name` views | `vw_FieldProductivity` → `vw_field_productivity` |
| `NVARCHAR(n)` | `VARCHAR(n)` | PostgreSQL is natively UTF-8 |
| `GETDATE()` | `CURRENT_TIMESTAMP` | Standard SQL function |

---

## 4. Data Type Conversion Table

| SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|
| `INT IDENTITY(1,1)` | `SERIAL` | Auto-incrementing 4-byte integer (creates underlying `SEQUENCE`) |
| `INT` | `INT` | Direct mapping — no change |
| `NVARCHAR(n)` | `VARCHAR(n)` | PostgreSQL `VARCHAR` is natively UTF-8; no `N` prefix needed |
| `DECIMAL(p,s)` | `NUMERIC(p,s)` | Functionally identical; `NUMERIC` is idiomatic PostgreSQL |
| `MONEY` | `NUMERIC(19,4)` | PostgreSQL has a `MONEY` type but `NUMERIC(19,4)` is preferred for precision control |
| `DATE` | `DATE` | Direct mapping — no change |
| `DATETIME` | `TIMESTAMP` | `TIMESTAMP WITHOUT TIME ZONE`; use `TIMESTAMPTZ` if timezone-awareness is needed |
| `GEOGRAPHY` | `GEOMETRY(POLYGON, 4326)` | Requires PostGIS extension; SRID 4326 = WGS 84 GPS |
| Computed `PERSISTED` | `GENERATED ALWAYS AS (...) STORED` | Referenced function must be marked `IMMUTABLE` |
| `SUSER_SNAME()` | `current_user` | Returns the current PostgreSQL session role |
| `GETDATE()` | `CURRENT_TIMESTAMP` | Returns current date and time |
| `FOR JSON AUTO` | `row_to_json()` | Converts a row to a JSON object |
| `+` (string concat) | `\|\|` | PostgreSQL string concatenation operator |
| `TOP 1` | `LIMIT 1` | Row-limiting syntax |
| `YEAR(date)` | `EXTRACT(YEAR FROM date)` | Date part extraction |
| `CAST(x AS type)` | `CAST(x AS type)` or `x::type` | PostgreSQL supports both; `::` is idiomatic shorthand |

---

## 5. Extension Requirements

```sql
-- Required extensions (run as superuser or with CREATE privilege)
CREATE EXTENSION IF NOT EXISTS postgis;        -- Spatial data types and functions
CREATE EXTENSION IF NOT EXISTS postgis_topology; -- Optional: topology support
```

**Why PostGIS?** The `CropManagement.Fields` table stores GPS boundary polygons using SQL Server's `GEOGRAPHY` type. PostGIS provides `GEOMETRY(POLYGON, 4326)` as the equivalent, along with spatial indexing (GiST) and a rich library of spatial functions (`ST_Area`, `ST_Contains`, `ST_Distance`, etc.).

---

## 6. Complete Target Table DDL

### 6.1 Schema Creation

```sql
CREATE SCHEMA IF NOT EXISTS crop_management;
CREATE SCHEMA IF NOT EXISTS members;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS audit;
```

### 6.2 members.member_accounts

> Source: `Members.MemberAccounts`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| MemberId | `INT IDENTITY(1,1)` | member_id | `SERIAL` |
| MemberNumber | `NVARCHAR(20) UNIQUE` | member_number | `VARCHAR(20) UNIQUE` |
| FirstName | `NVARCHAR(50)` | first_name | `VARCHAR(50)` |
| LastName | `NVARCHAR(50)` | last_name | `VARCHAR(50)` |
| Email | `NVARCHAR(100)` | email | `VARCHAR(100)` |
| PhoneNumber | `NVARCHAR(20)` | phone_number | `VARCHAR(20)` |
| Address | `NVARCHAR(200)` | address | `VARCHAR(200)` |
| City | `NVARCHAR(50)` | city | `VARCHAR(50)` |
| State | `NVARCHAR(2)` | state | `VARCHAR(2)` |
| ZipCode | `NVARCHAR(10)` | zip_code | `VARCHAR(10)` |
| MembershipDate | `DATE` | membership_date | `DATE` |
| Status | `NVARCHAR(20)` | status | `VARCHAR(20)` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | modified_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

### 6.3 crop_management.crop_types

> Source: `CropManagement.CropTypes`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| CropTypeId | `INT IDENTITY(1,1)` | crop_type_id | `SERIAL` |
| Name | `NVARCHAR(100)` | name | `VARCHAR(100)` |
| GrowingSeason | `NVARCHAR(50)` | growing_season | `VARCHAR(50)` |
| DaysToMaturity | `INT` | days_to_maturity | `INT` |
| MinTemperature | `DECIMAL(5,2)` | min_temperature | `NUMERIC(5,2)` |
| MaxTemperature | `DECIMAL(5,2)` | max_temperature | `NUMERIC(5,2)` |
| WaterRequirement | `NVARCHAR(20)` | water_requirement | `VARCHAR(20)` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | modified_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

### 6.4 crop_management.fields

> Source: `CropManagement.Fields`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| FieldId | `INT IDENTITY(1,1)` | field_id | `SERIAL` |
| MemberId | `INT NOT NULL` | member_id | `INT NOT NULL` |
| FieldName | `NVARCHAR(100)` | field_name | `VARCHAR(100)` |
| Acreage | `DECIMAL(10,2)` | acreage | `NUMERIC(10,2)` |
| SoilType | `NVARCHAR(50)` | soil_type | `VARCHAR(50)` |
| IrrigationType | `NVARCHAR(50)` | irrigation_type | `VARCHAR(50)` |
| GPSBoundary | `GEOGRAPHY` | gps_boundary | `GEOMETRY(POLYGON, 4326)` |
| CurrentCropId | `INT` | current_crop_id | `INT` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | modified_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

**Migration Note:** `GEOGRAPHY` → `GEOMETRY(POLYGON, 4326)` requires spatial data re-projection. SQL Server `GEOGRAPHY` uses a geodetic model; PostGIS `GEOMETRY` with SRID 4326 uses a planar projection. For small areas (field boundaries), this is functionally equivalent. Use `ST_Transform()` if higher precision is needed.

### 6.5 crop_management.harvests

> Source: `CropManagement.Harvests`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| HarvestId | `INT IDENTITY(1,1)` | harvest_id | `SERIAL` |
| FieldId | `INT NOT NULL` | field_id | `INT NOT NULL` |
| CropTypeId | `INT NOT NULL` | crop_type_id | `INT NOT NULL` |
| HarvestDate | `DATE` | harvest_date | `DATE` |
| YieldBushels | Computed `PERSISTED` | yield_bushels | `GENERATED ALWAYS AS (...) STORED` |
| Quantity | `DECIMAL(12,2)` | quantity | `NUMERIC(12,2)` |
| UnitType | `NVARCHAR(20)` | unit_type | `VARCHAR(20)` |
| MoistureContent | `DECIMAL(5,2)` | moisture_content | `NUMERIC(5,2)` |
| GradeCode | `NVARCHAR(10)` | grade_code | `VARCHAR(10)` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

**Migration Note:** The `yield_bushels` column is a `GENERATED ALWAYS AS ... STORED` column that calls `crop_management.calculate_yield_bushels()`. The function **must** be created before this table and must be marked `IMMUTABLE` for use in generated columns.

### 6.6 inventory.fertilizer_stock

> Source: `Inventory.FertilizerStock`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| StockId | `INT IDENTITY(1,1)` | stock_id | `SERIAL` |
| ProductName | `NVARCHAR(100)` | product_name | `VARCHAR(100)` |
| ManufacturerName | `NVARCHAR(100)` | manufacturer_name | `VARCHAR(100)` |
| QuantityOnHand | `DECIMAL(12,2)` | quantity_on_hand | `NUMERIC(12,2)` |
| Unit | `NVARCHAR(20)` | unit | `VARCHAR(20)` |
| CostPerUnit | `MONEY` | cost_per_unit | `NUMERIC(19,4)` |
| ReorderLevel | `DECIMAL(12,2)` | reorder_level | `NUMERIC(12,2)` |
| LastRestockDate | `DATE` | last_restock_date | `DATE` |
| ExpirationDate | `DATE` | expiration_date | `DATE` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

**Migration Note:** `MONEY` → `NUMERIC(19,4)`. SQL Server `MONEY` is an 8-byte fixed-point type with 4 decimal places. `NUMERIC(19,4)` provides identical precision and range without the locale-dependent formatting of PostgreSQL's native `MONEY` type.

### 6.7 trading.commodity_prices

> Source: `Trading.CommodityPrices`

```sql
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
```

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| PriceId | `INT IDENTITY(1,1)` | price_id | `SERIAL` |
| CropTypeId | `INT NOT NULL` | crop_type_id | `INT NOT NULL` |
| MarketDate | `DATE` | market_date | `DATE` |
| PricePerBushel | `MONEY` | price_per_bushel | `NUMERIC(19,4)` |
| MarketName | `NVARCHAR(100)` | market_name | `VARCHAR(100)` |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | created_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |

---

## 7. PL/pgSQL Function — calculate_yield_bushels

> Source: `dbo.fn_CalculateYieldBushels`

```sql
CREATE OR REPLACE FUNCTION crop_management.calculate_yield_bushels(
    p_quantity NUMERIC,
    p_unit_type VARCHAR
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Convert various units to bushels
    RETURN CASE p_unit_type
        WHEN 'bushels'      THEN p_quantity
        WHEN 'tonnes'       THEN p_quantity * 36.7437   -- 1 tonne ≈ 36.7437 bushels (wheat)
        WHEN 'hundredweight' THEN p_quantity * 1.667    -- 1 cwt ≈ 1.667 bushels
        WHEN 'kilograms'    THEN p_quantity * 0.0367437
        ELSE p_quantity  -- Default: assume bushels if unit unknown
    END;
END;
$$;

COMMENT ON FUNCTION crop_management.calculate_yield_bushels(NUMERIC, VARCHAR) IS
    'Converts harvest quantity from various units to bushels. '
    'Used as IMMUTABLE function in the yield_bushels generated column on crop_management.harvests.';
```

**Key Differences from SQL Server:**

| Aspect | SQL Server | PostgreSQL |
|---|---|---|
| Language | T-SQL | PL/pgSQL |
| Volatility | N/A (deterministic implied) | `IMMUTABLE` (required for generated columns) |
| Schema | `dbo` | `crop_management` (co-located with table) |
| Variable declaration | `DECLARE @Var TYPE` | Parameters via function signature |
| Assignment | `SET @Var = ...` | `RETURN CASE ... END` (direct return) |

---

## 8. Audit Log Table Design

> Source: `Audit.HarvestAuditLog` (implied by trigger `tr_AuditHarvestChanges`)

### 8.1 Table DDL

```sql
CREATE TABLE audit.harvest_audit_log (
    audit_id     SERIAL PRIMARY KEY,
    harvest_id   INT NOT NULL,
    change_type  VARCHAR(10) NOT NULL CHECK (change_type IN ('INSERT', 'UPDATE', 'DELETE')),
    changed_by   VARCHAR(100) NOT NULL DEFAULT current_user,
    change_date  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_value    JSONB,
    new_value    JSONB
);

CREATE INDEX idx_audit_harvest_id ON audit.harvest_audit_log(harvest_id);
CREATE INDEX idx_audit_change_date ON audit.harvest_audit_log(change_date);
CREATE INDEX idx_audit_change_type ON audit.harvest_audit_log(change_type);
```

### 8.2 Column Mapping

| Source Column | Source Type | Target Column | Target Type |
|---|---|---|---|
| *(implied PK)* | `INT IDENTITY` | audit_id | `SERIAL` |
| HarvestId | `INT` | harvest_id | `INT` |
| ChangeType | `VARCHAR` | change_type | `VARCHAR(10) CHECK (...)` |
| ChangedBy | `SUSER_SNAME()` | changed_by | `VARCHAR(100) DEFAULT current_user` |
| ChangeDate | `GETDATE()` | change_date | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` |
| OldValue | `FOR JSON AUTO` (NVARCHAR) | old_value | `JSONB` |
| NewValue | `FOR JSON AUTO` (NVARCHAR) | new_value | `JSONB` |

**Design Notes:**
- `JSONB` instead of `JSON` — supports indexing, efficient storage, and equality comparisons.
- `current_user` replaces `SUSER_SNAME()` — returns the current PostgreSQL session role.
- `CHECK` constraint enforces valid change types at the database level.

---

## 9. PostgreSQL Trigger Function — Harvest Audit

> Source: `tr_AuditHarvestChanges`

### 9.1 Trigger Function

```sql
CREATE OR REPLACE FUNCTION audit.fn_audit_harvest_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
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
END;
$$;

COMMENT ON FUNCTION audit.fn_audit_harvest_changes() IS
    'Trigger function for regulatory compliance auditing of harvest data changes. '
    'Logs INSERT, UPDATE, and DELETE operations as JSONB to audit.harvest_audit_log.';
```

### 9.2 Trigger Definition

```sql
CREATE TRIGGER trg_audit_harvest_changes
    AFTER INSERT OR UPDATE OR DELETE
    ON crop_management.harvests
    FOR EACH ROW
    EXECUTE FUNCTION audit.fn_audit_harvest_changes();
```

### 9.3 Key Differences from SQL Server

| Aspect | SQL Server (`tr_AuditHarvestChanges`) | PostgreSQL (`fn_audit_harvest_changes`) |
|---|---|---|
| Architecture | Single trigger body | Separate trigger function + trigger binding |
| Row access | `inserted` / `deleted` pseudo-tables | `NEW` / `OLD` record variables |
| Operation detection | `EXISTS (SELECT * FROM inserted)` | `TG_OP` variable (`'INSERT'`, `'UPDATE'`, `'DELETE'`) |
| JSON serialization | `FOR JSON AUTO` | `row_to_json(NEW)::jsonb` |
| Current user | `SUSER_SNAME()` | `current_user` |
| Execution | Statement-level (one fire per statement) | `FOR EACH ROW` (one fire per affected row) |
| SET NOCOUNT | `SET NOCOUNT ON` required | Not applicable in PostgreSQL |

---

## 10. View — vw_field_productivity

> Source: `CropManagement.vw_FieldProductivity`

```sql
CREATE OR REPLACE VIEW crop_management.vw_field_productivity AS
SELECT
    f.field_id,
    f.field_name,
    m.member_number,
    m.first_name || ' ' || m.last_name AS member_name,
    f.acreage,
    ct.name AS current_crop,
    SUM(h.yield_bushels)              AS total_yield,
    SUM(h.yield_bushels) / f.acreage  AS yield_per_acre,
    COUNT(h.harvest_id)               AS harvest_count,
    MAX(h.harvest_date)               AS last_harvest_date
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
    'Aggregated field-level productivity metrics including total yield, yield per acre, and harvest counts.';
```

**Key Difference:** String concatenation uses `||` instead of `+`.

| SQL Server | PostgreSQL |
|---|---|
| `m.FirstName + ' ' + m.LastName` | `m.first_name \|\| ' ' \|\| m.last_name` |

---

## 11. Index Strategy

### 11.1 B-Tree Indexes (Standard)

B-tree is the default PostgreSQL index type — optimal for equality and range queries.

```sql
-- members.member_accounts
CREATE INDEX idx_members_number ON members.member_accounts(member_number);
CREATE INDEX idx_members_name   ON members.member_accounts(last_name, first_name);

-- crop_management.crop_types
CREATE INDEX idx_crop_types_name   ON crop_management.crop_types(name);
CREATE INDEX idx_crop_types_season ON crop_management.crop_types(growing_season);

-- crop_management.fields
CREATE INDEX idx_fields_member       ON crop_management.fields(member_id);
CREATE INDEX idx_fields_current_crop ON crop_management.fields(current_crop_id);

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

### 11.2 GiST Index (Spatial)

GiST (Generalized Search Tree) indexes support PostGIS spatial queries such as `ST_Contains`, `ST_Intersects`, and `ST_DWithin`.

```sql
-- Spatial index on field GPS boundaries
CREATE INDEX idx_fields_gps_boundary
    ON crop_management.fields
    USING GIST (gps_boundary);
```

**Why GiST?** Unlike B-tree, GiST supports multi-dimensional data. It enables efficient spatial queries like:
- `WHERE ST_Contains(gps_boundary, ST_SetSRID(ST_MakePoint(lng, lat), 4326))` — point-in-polygon
- `WHERE ST_Intersects(a.gps_boundary, b.gps_boundary)` — boundary overlap detection
- `WHERE ST_DWithin(gps_boundary, point, distance)` — proximity search

### 11.3 Index Mapping Summary

| SQL Server Index | Type | PostgreSQL Index | Type |
|---|---|---|---|
| `IX_CropTypes_Name` | Non-clustered | `idx_crop_types_name` | B-tree |
| `IX_CropTypes_Season` | Non-clustered | `idx_crop_types_season` | B-tree |
| `IX_Fields_Member` | Non-clustered | `idx_fields_member` | B-tree |
| `IX_Fields_CurrentCrop` | Non-clustered | `idx_fields_current_crop` | B-tree |
| `IX_Harvests_Field` | Non-clustered | `idx_harvests_field` | B-tree |
| `IX_Harvests_Date` | Non-clustered | `idx_harvests_date` | B-tree |
| `IX_Fertilizer_Product` | Non-clustered | `idx_fertilizer_product` | B-tree |
| `IX_Prices_CropDate` | Non-clustered | `idx_prices_crop_date` | B-tree |
| `IX_Members_Number` | Non-clustered | `idx_members_number` | B-tree |
| `IX_Members_Name` | Non-clustered | `idx_members_name` | B-tree |
| *(SQL Server spatial)* | Spatial | `idx_fields_gps_boundary` | GiST |

---

## 12. Stored Procedure Conversions

### 12.1 calculate_optimal_rotation

> Source: `CropPlanning.sp_CalculateOptimalRotation`

```sql
CREATE OR REPLACE FUNCTION crop_management.calculate_optimal_rotation(
    p_field_id INT,
    p_current_year INT
)
RETURNS TABLE (
    crop_type_id    INT,
    name            VARCHAR,
    rotation_score  NUMERIC,
    current_price   NUMERIC(19,4),
    total_score     NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_crop_id INT;
    v_soil_type    VARCHAR(50);
BEGIN
    SELECT current_crop_id, soil_type
    INTO v_last_crop_id, v_soil_type
    FROM crop_management.fields
    WHERE field_id = p_field_id;

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
                SELECT MAX(market_date)
                FROM trading.commodity_prices
                WHERE crop_type_id = ct.crop_type_id
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
    'previous crop, soil type, and current market prices.';
```

### 12.2 calculate_member_payment

> Source: `Settlement.sp_CalculateMemberPayment`

```sql
CREATE OR REPLACE FUNCTION trading.calculate_member_payment(
    p_member_id       INT,
    p_settlement_year INT,
    OUT p_total_payment NUMERIC(19,4)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_yield        NUMERIC(12,2);
    v_average_grade      NUMERIC(5,2);
    v_quality_multiplier NUMERIC(5,3);
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

    -- Calculate payment with quality bonus
    SELECT v_total_yield * cp.price_per_bushel * v_quality_multiplier
    INTO p_total_payment
    FROM trading.commodity_prices cp
    WHERE cp.market_date = (
        SELECT MAX(market_date)
        FROM trading.commodity_prices
        WHERE EXTRACT(YEAR FROM market_date) = p_settlement_year
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
END;
$$;

COMMENT ON FUNCTION trading.calculate_member_payment(INT, INT) IS
    'Calculates end-of-year settlement payment for a cooperative member based on '
    'total yield, grade quality multiplier, and latest commodity prices.';
```

**Key Conversion Notes:**

| SQL Server Pattern | PostgreSQL Equivalent |
|---|---|
| `CREATE PROCEDURE ... @Param OUTPUT` | `CREATE FUNCTION ... (OUT param)` |
| `TOP 1 ... ORDER BY` | `ORDER BY ... LIMIT 1` |
| `YEAR(date)` | `EXTRACT(YEAR FROM date)` |
| `CAST(col AS TYPE)` | `col::TYPE` |
| `MONEY` arithmetic | `NUMERIC(19,4)` arithmetic |
| `SET @Var = (SELECT ...)` | `SELECT ... INTO var` |
| `RETURN 0` (success code) | Implicit return via `OUT` parameter |

---

## Appendix A — Full DDL Execution Order

Objects must be created in dependency order:

```
1.  CREATE EXTENSION postgis
2.  CREATE SCHEMA crop_management, members, inventory, trading, audit
3.  CREATE TABLE members.member_accounts          (no FK dependencies)
4.  CREATE TABLE crop_management.crop_types        (no FK dependencies)
5.  CREATE FUNCTION crop_management.calculate_yield_bushels  (needed by harvests)
6.  CREATE TABLE crop_management.fields            (FK → member_accounts, crop_types)
7.  CREATE TABLE crop_management.harvests          (FK → fields, crop_types; generated column → function)
8.  CREATE TABLE inventory.fertilizer_stock        (no FK dependencies)
9.  CREATE TABLE trading.commodity_prices          (FK → crop_types)
10. CREATE TABLE audit.harvest_audit_log           (no FK dependencies)
11. CREATE FUNCTION audit.fn_audit_harvest_changes (trigger function)
12. CREATE TRIGGER trg_audit_harvest_changes       (on harvests → audit function)
13. CREATE VIEW crop_management.vw_field_productivity
14. CREATE FUNCTION crop_management.calculate_optimal_rotation
15. CREATE FUNCTION trading.calculate_member_payment
16. CREATE INDEX (all B-tree and GiST indexes)
```

## Appendix B — Object Count Summary

| Category | Count | Objects |
|---|---|---|
| Schemas | 5 | `crop_management`, `members`, `inventory`, `trading`, `audit` |
| Tables | 7 | `member_accounts`, `crop_types`, `fields`, `harvests`, `fertilizer_stock`, `commodity_prices`, `harvest_audit_log` |
| Functions | 4 | `calculate_yield_bushels`, `fn_audit_harvest_changes`, `calculate_optimal_rotation`, `calculate_member_payment` |
| Triggers | 1 | `trg_audit_harvest_changes` |
| Views | 1 | `vw_field_productivity` |
| B-tree Indexes | 13 | See Section 11.1 |
| GiST Indexes | 1 | `idx_fields_gps_boundary` |
| Extensions | 1 | `postgis` |
