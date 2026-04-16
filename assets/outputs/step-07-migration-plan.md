# Step 07 — Comprehensive Migration Plan

## GreenHarvest Agricultural Co-op: SQL Server → PostgreSQL

| Attribute | Value |
|---|---|
| **Document Version** | 1.0 |
| **Created** | 2026-04-16 |
| **Source System** | SQL Server 2019 (Developer Edition via Docker) |
| **Target System** | Azure Database for PostgreSQL — Flexible Server (PostgreSQL 16) |
| **Database Name** | GreenHarvest → greenharvest |
| **Total Objects** | 6 Tables · 2 Stored Procedures · 1 Function · 1 Trigger · 1 View |
| **Reference Documents** | Steps 01–06 (assets/outputs/) |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Pre-Migration Phase](#2-pre-migration-phase)
3. [Migration Phases — Detailed Timeline](#3-migration-phases--detailed-timeline)
4. [Rollback Procedures](#4-rollback-procedures)
5. [Risk Register](#5-risk-register)
6. [Validation Checklist](#6-validation-checklist)
7. [Communication Plan](#7-communication-plan)
8. [Post-Migration Tasks](#8-post-migration-tasks)
9. [Go/No-Go Decision Criteria](#9-gono-go-decision-criteria)
10. [Appendices](#10-appendices)

---

## 1. Executive Summary

### 1.1 Scope

This migration plan covers the complete transition of the **GreenHarvest Agricultural Cooperative** database from Microsoft SQL Server 2019 to Azure Database for PostgreSQL 16 with PostGIS 3.4 spatial extensions. The migration includes:

- **6 tables** across 4 schemas (CropManagement, Members, Inventory, Trading) plus 1 implied Audit table
- **2 stored procedures** encoding critical business rules (crop rotation and member payment settlement)
- **1 scalar UDF** (`fn_CalculateYieldBushels`) used in a PERSISTED computed column
- **1 AFTER trigger** (`tr_AuditHarvestChanges`) for USDA regulatory compliance auditing
- **1 view** (`vw_FieldProductivity`) for field-level productivity reporting
- **Seed data** (5 crop types) and **sample data** (3 member accounts)
- **9 indexes** including a GiST spatial index for PostGIS

### 1.2 Timeline Summary

| Phase | Duration | Calendar |
|---|---|---|
| Pre-Migration Preparation | 3 days | Days 1–3 |
| Phase 1: Schema Migration | 2 days | Days 4–5 |
| Phase 2: Function & Trigger Migration | 2 days | Days 6–7 |
| Phase 3: Data Migration | 1 day | Day 8 |
| Phase 4: Stored Procedure Migration | 3 days | Days 9–11 |
| Phase 5: View Recreation | 0.5 days | Day 12 (AM) |
| Phase 6: Validation | 2.5 days | Days 12 (PM)–14 |
| Post-Migration Stabilization | 5 days | Days 15–19 |
| **Total** | **~4 weeks** (including parallel-run) | |

**Estimated Total Effort:** 53.5 developer-hours (~7 developer-days)

### 1.3 Risk Level

| Dimension | Rating | Justification |
|---|---|---|
| **Overall** | 🟡 **Medium-High** | Complex object migrations offset by small database size |
| **Schema** | 🟡 Medium | GEOGRAPHY → PostGIS and MONEY → NUMERIC require careful handling |
| **Business Logic** | 🔴 High | Financial settlement procedure must maintain precision parity |
| **Data Integrity** | 🟢 Low | Small data volume; full validation suite available |
| **Rollback Safety** | 🟢 Low | Source system preserved in read-only mode during parallel run |

---

## 2. Pre-Migration Phase

### 2.1 Environment Setup with Docker Compose

The development and testing environment uses the project's `docker-compose.yml` to run all three database engines in parallel:

```yaml
version: '3.8'

services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:2019-latest
    environment:
      ACCEPT_EULA: Y
      SA_PASSWORD: GreenHarvest2024!
      MSSQL_PID: Developer
    ports:
      - "1433:1433"
    volumes:
      - sqlserver-data:/var/opt/mssql

  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: greenharvest
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data

  postgis:
    image: postgis/postgis:16-3.4
    environment:
      POSTGRES_DB: greenharvest
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5433:5432"
    volumes:
      - postgis-data:/var/lib/postgresql/data

volumes:
  sqlserver-data:
  postgres-data:
  postgis-data:
```

**Setup Commands:**

```bash
# Start all containers
docker compose up -d

# Verify SQL Server is ready
docker compose exec sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P 'GreenHarvest2024!' -Q "SELECT @@VERSION"

# Verify PostgreSQL 16 is ready
docker compose exec postgres psql -U postgres -d greenharvest \
  -c "SELECT version();"

# Verify PostGIS 16-3.4 is ready
docker compose exec postgis psql -U postgres -d greenharvest \
  -c "SELECT PostGIS_Full_Version();"
```

> **Note:** The `postgis/postgis:16-3.4` image ships with PostGIS pre-installed. For Azure Database for PostgreSQL, enable PostGIS via the `azure.extensions` server parameter.

### 2.2 Backup Procedures

| # | Task | Command / Action | Responsible |
|---|---|---|---|
| 1 | Full SQL Server backup | `BACKUP DATABASE GreenHarvest TO DISK = '/var/opt/mssql/backup/GreenHarvest_pre_migration.bak' WITH COMPRESSION, CHECKSUM;` | DBA |
| 2 | Verify backup integrity | `RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backup/GreenHarvest_pre_migration.bak';` | DBA |
| 3 | Export source row counts | Run Step 06 §1 row count queries; save results to `pre_migration_counts.csv` | Migration Lead |
| 4 | Export source computed values | Run Step 06 §3 computed column queries; save 100 sample rows | Migration Lead |
| 5 | Export financial baselines | Run `sp_CalculateMemberPayment` for all members × years; save results | Migration Lead |
| 6 | Export spatial data samples | `SELECT FieldId, GPSBoundary.STAsText() FROM CropManagement.Fields;` | Migration Lead |
| 7 | Snapshot PostgreSQL target (empty) | `pg_dump -Fc greenharvest > greenharvest_empty.dump` | DBA |
| 8 | Set SQL Server to read-only (cutover day) | `ALTER DATABASE GreenHarvest SET READ_ONLY;` | DBA |

### 2.3 Team Roles

| Role | Responsibility | Phase Involvement |
|---|---|---|
| **Migration Lead** | Overall coordination, Go/No-Go decisions, stakeholder communication | All phases |
| **DBA — SQL Server** | Source backup, data export, source system validation, read-only cutover | Pre-Migration, Phase 3, Phase 6 |
| **DBA — PostgreSQL** | Target provisioning, extension setup, performance tuning, index optimization | Pre-Migration, Phases 1–6, Post-Migration |
| **Backend Developer** | PL/pgSQL function/trigger conversion, stored procedure migration, Python service stubs | Phases 2, 4, 5 |
| **QA / Validation Lead** | Validation query execution, test case management, regression testing | Phase 6, Post-Migration |
| **Application Developer** | Connection string updates, ORM configuration, application-level testing | Phase 6, Post-Migration |
| **Compliance Officer** | Audit trigger validation, USDA reporting format review, JSON format sign-off | Phase 2, Phase 6 |

### 2.4 Pre-Migration Checklist

| # | Task | Owner | Status |
|---|---|---|---|
| 1 | Back up source SQL Server database (full + differential) | DBA – SQL Server | ☐ |
| 2 | Provision Azure Database for PostgreSQL — Flexible Server | DBA – PostgreSQL | ☐ |
| 3 | Verify PostgreSQL version ≥ 16 (required for GENERATED ALWAYS AS with functions) | DBA – PostgreSQL | ☐ |
| 4 | Enable PostGIS extension via `azure.extensions` server parameter | DBA – PostgreSQL | ☐ |
| 5 | Create target database: `CREATE DATABASE greenharvest ENCODING 'UTF8';` | DBA – PostgreSQL | ☐ |
| 6 | Create migration user with CREATE, USAGE privileges + superuser for extensions | DBA – PostgreSQL | ☐ |
| 7 | Verify network connectivity: `psql -h <host> -U <user> -d greenharvest` | DBA – PostgreSQL | ☐ |
| 8 | Document source row counts and baseline metrics | Migration Lead | ☐ |
| 9 | Schedule maintenance window with stakeholders | Migration Lead | ☐ |
| 10 | Review and obtain DBA sign-off on all migration scripts (Steps 04–05) | DBA – Both | ☐ |
| 11 | Run Docker Compose environment locally and execute dry-run migration | Backend Developer | ☐ |
| 12 | Confirm compliance team has reviewed audit trigger JSON format change | Compliance Officer | ☐ |

---

## 3. Migration Phases — Detailed Timeline

### Phase 1: Schema Migration (Days 4–5)

**Goal:** Create all PostgreSQL schemas, extensions, tables, indexes, and constraints in correct dependency order.

**Estimated Effort:** 11 hours (Development: 5.5h · Testing: 4h · Documentation: 1.5h)

#### 1.1 Extensions (Day 4, Hour 1)

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

**Validation:** `SELECT PostGIS_Full_Version();` — must return PostGIS 3.4.x.

#### 1.2 Schemas (Day 4, Hour 1)

Create schemas in this order (no dependencies between schemas):

```sql
CREATE SCHEMA IF NOT EXISTS crop_management;
CREATE SCHEMA IF NOT EXISTS members;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS audit;
```

#### 1.3 Tables — Dependency Order (Day 4, Hours 2–8)

Tables must be created in this strict order due to foreign key and function dependencies:

| Order | Table | Dependencies | Complexity | Notes |
|---|---|---|---|---|
| **1** | `members.member_accounts` | None | 🟢 Low | Foundation table |
| **2** | `crop_management.crop_types` | None | 🟢 Low | Foundation table; referenced by 3 FKs |
| **3** | `inventory.fertilizer_stock` | None | 🟡 Medium | MONEY → NUMERIC(19,4) |
| **4** | `crop_management.fields` | `member_accounts`, `crop_types` | 🔴 High | GEOGRAPHY → GEOMETRY(POLYGON, 4326) via PostGIS |
| **5** | `trading.commodity_prices` | `crop_types` | 🟡 Medium | MONEY → NUMERIC(19,4) |
| **6** | `crop_management.harvests` | `fields`, `crop_types`, `calculate_yield_bushels()` | 🔴 Critical | PERSISTED computed column → GENERATED ALWAYS AS; **function must exist first** (see Phase 2 overlap) |
| **7** | `audit.harvest_audit_log` | None | 🟢 Low | Target for audit trigger; JSONB columns |

> **⚠ Critical Dependency:** The `calculate_yield_bushels` IMMUTABLE function (Phase 2.1) **must** be created before the `harvests` table. This creates a dependency overlap between Phase 1 and Phase 2.

**Execution sequence:**

```
Tables 1–5 → Phase 2.1 (function) → Table 6 (harvests) → Table 7 (audit log) → Indexes
```

#### 1.4 Indexes (Day 5, Hours 1–2)

Create all 16 indexes after table creation:

| Index | Table | Type | Source Index |
|---|---|---|---|
| `idx_members_number` | `member_accounts` | B-tree | `IX_Members_Number` |
| `idx_members_name` | `member_accounts` | B-tree (composite) | `IX_Members_Name` |
| `idx_crop_types_name` | `crop_types` | B-tree | `IX_CropTypes_Name` |
| `idx_crop_types_season` | `crop_types` | B-tree | `IX_CropTypes_Season` |
| `idx_fields_member` | `fields` | B-tree | `IX_Fields_Member` |
| `idx_fields_current_crop` | `fields` | B-tree | `IX_Fields_CurrentCrop` |
| `idx_fields_gps_boundary` | `fields` | **GiST** | *(new — spatial)* |
| `idx_harvests_field` | `harvests` | B-tree | `IX_Harvests_Field` |
| `idx_harvests_date` | `harvests` | B-tree | `IX_Harvests_Date` |
| `idx_fertilizer_product` | `fertilizer_stock` | B-tree | `IX_Fertilizer_Product` |
| `idx_prices_crop_date` | `commodity_prices` | B-tree (composite) | `IX_Prices_CropDate` |
| `idx_audit_harvest_id` | `harvest_audit_log` | B-tree | *(new)* |
| `idx_audit_change_date` | `harvest_audit_log` | B-tree | *(new)* |
| `idx_audit_change_type` | `harvest_audit_log` | B-tree | *(new)* |

**Phase 1 Exit Criteria:**
- ☐ All 5 schemas exist
- ☐ PostGIS extension active
- ☐ All 7 tables created with correct column types
- ☐ All 14+ indexes created (including GiST spatial index)
- ☐ All foreign key constraints enforced
- ☐ `information_schema.columns` output matches Step 04 design

---

### Phase 2: Function & Trigger Migration (Days 6–7)

**Goal:** Migrate the scalar UDF and audit trigger to PL/pgSQL equivalents.

**Estimated Effort:** 15 hours (Development: 6h · Testing: 6h · Documentation: 3h)

> **Note:** Phase 2.1 (function creation) overlaps with Phase 1 and must execute **before** the `harvests` table.

#### 2.1 calculate_yield_bushels — IMMUTABLE Function

**Source:** `dbo.fn_CalculateYieldBushels` (T-SQL scalar UDF)
**Target:** `crop_management.calculate_yield_bushels` (PL/pgSQL IMMUTABLE function)

| Conversion | SQL Server | PostgreSQL |
|---|---|---|
| Schema | `dbo` | `crop_management` |
| Parameters | `@Quantity DECIMAL(12,2)`, `@UnitType NVARCHAR(20)` | `p_quantity NUMERIC`, `p_unit_type VARCHAR` |
| Return type | `DECIMAL(12,2)` | `NUMERIC(12,2)` |
| Volatility | None (implicit) | `IMMUTABLE` (required for generated column) |

**Validation:**

```sql
-- Expected: 3674.37
SELECT crop_management.calculate_yield_bushels(100, 'tonnes');

-- Expected: 166.70
SELECT crop_management.calculate_yield_bushels(100, 'hundredweight');

-- Expected: 100.00
SELECT crop_management.calculate_yield_bushels(100, 'bushels');

-- Expected: 3.67
SELECT crop_management.calculate_yield_bushels(100, 'kilograms');

-- Expected: 50.00 (unknown unit defaults to quantity)
SELECT crop_management.calculate_yield_bushels(50, 'pounds');
```

#### 2.2 Audit Trigger — fn_audit_harvest_changes + trg_audit_harvest_changes

**Source:** `tr_AuditHarvestChanges` (T-SQL AFTER trigger with `inserted`/`deleted` pseudo-tables)
**Target:** `audit.fn_audit_harvest_changes()` (trigger function) + `trg_audit_harvest_changes` (trigger binding)

| Conversion | SQL Server | PostgreSQL |
|---|---|---|
| Architecture | Single trigger body | Separate trigger function + trigger definition |
| Row access | `inserted` / `deleted` pseudo-tables | `NEW` / `OLD` row variables |
| Operation detection | `EXISTS(SELECT * FROM inserted)` | `TG_OP` variable |
| JSON serialization | `FOR JSON AUTO` | `row_to_json(NEW)::jsonb` |
| Current user | `SUSER_SNAME()` | `current_user` |
| Execution model | Statement-level | `FOR EACH ROW` |

**Validation:**

```sql
-- Insert test → verify audit log entry with change_type = 'INSERT'
INSERT INTO crop_management.harvests (field_id, crop_type_id, harvest_date, quantity, unit_type)
VALUES (1, 1, '2026-01-15', 500.00, 'bushels');

SELECT * FROM audit.harvest_audit_log ORDER BY audit_id DESC LIMIT 1;
-- Expected: change_type = 'INSERT', old_value = NULL, new_value = {JSON}

-- Update test → verify audit log entry with change_type = 'UPDATE'
UPDATE crop_management.harvests SET quantity = 550.00 WHERE harvest_id = (SELECT MAX(harvest_id) FROM crop_management.harvests);

-- Delete test → verify audit log entry with change_type = 'DELETE'
DELETE FROM crop_management.harvests WHERE harvest_id = (SELECT MAX(harvest_id) FROM crop_management.harvests);
```

**Phase 2 Exit Criteria:**
- ☐ `calculate_yield_bushels` function created and marked `IMMUTABLE`
- ☐ All unit conversion test cases pass (bushels, tonnes, hundredweight, kilograms, unknown)
- ☐ Generated column `yield_bushels` auto-populates on INSERT
- ☐ Audit trigger fires for INSERT, UPDATE, DELETE
- ☐ Audit log entries contain valid JSONB in `old_value` / `new_value`
- ☐ Compliance officer signs off on JSON audit format

---

### Phase 3: Data Migration (Day 8)

**Goal:** Migrate all seed data, sample data, and production data from SQL Server to PostgreSQL.

**Estimated Effort:** 4 hours (Development: 1.5h · Testing: 2h · Documentation: 0.5h)

#### 3.1 Seed Data — CropTypes

```sql
INSERT INTO crop_management.crop_types
    (name, growing_season, days_to_maturity, min_temperature, max_temperature, water_requirement)
VALUES
    ('Corn',     'Spring/Summer', 120, 10.0, 30.0, 'High'),
    ('Soybeans', 'Spring/Summer', 100, 15.0, 28.0, 'Medium'),
    ('Wheat',    'Fall/Winter',   180,  0.0, 25.0, 'Low'),
    ('Barley',   'Spring',         90,  5.0, 22.0, 'Medium'),
    ('Oats',     'Spring',         80,  7.0, 20.0, 'Medium');
```

#### 3.2 Sample Data — MemberAccounts

```sql
INSERT INTO members.member_accounts
    (member_number, first_name, last_name, email, phone_number, membership_date, status)
VALUES
    ('M001', 'John',   'Smith',    'jsmith@email.com',    '555-0101', '2020-01-15', 'Active'),
    ('M002', 'Mary',   'Johnson',  'mjohnson@email.com',  '555-0102', '2019-05-20', 'Active'),
    ('M003', 'Robert', 'Williams', 'rwilliams@email.com', '555-0103', '2021-03-10', 'Active');
```

#### 3.3 Bulk Data Transfer (Production Data)

For tables with production data, use the following transfer strategy:

| Method | Tables | Notes |
|---|---|---|
| **Direct INSERT** | `crop_types`, `member_accounts` | Small reference data; manual SQL |
| **CSV Export/Import** | `fields`, `harvests`, `fertilizer_stock`, `commodity_prices` | `bcp` export from SQL Server → `\COPY` import to PostgreSQL |
| **Spatial Data** | `fields.gps_boundary` | Export as WKT via `STAsText()` → import via `ST_GeomFromText()` |

**Bulk Transfer Commands:**

```bash
# Export from SQL Server (CSV)
bcp "SELECT FieldId, MemberId, FieldName, Acreage, SoilType, IrrigationType, GPSBoundary.STAsText(), CurrentCropId FROM CropManagement.Fields" queryout fields.csv -c -t"," -S localhost -U sa -P 'GreenHarvest2024!'

# Import to PostgreSQL (with spatial conversion)
psql -U postgres -d greenharvest -c "\COPY crop_management.fields_staging FROM 'fields.csv' CSV"
```

> **⚠ Important:** When inserting into `crop_management.harvests`, **omit** the `yield_bushels` column — it is a generated column and will be auto-calculated.

#### 3.4 Data Migration Order

Due to foreign key constraints, data must be loaded in this order:

```
1. crop_management.crop_types      (no FK deps)
2. members.member_accounts         (no FK deps)
3. inventory.fertilizer_stock      (no FK deps)
4. crop_management.fields          (FK → member_accounts, crop_types)
5. trading.commodity_prices        (FK → crop_types)
6. crop_management.harvests        (FK → fields, crop_types; generated column)
```

**Phase 3 Exit Criteria:**
- ☐ Row counts match source for all 6 tables (see Step 06 §1)
- ☐ `yield_bushels` generated column populated correctly for all harvest rows
- ☐ Audit log contains INSERT entries for all migrated harvest rows
- ☐ Spatial data validated — 10+ field boundaries match `STAsText()` output
- ☐ No orphaned foreign key references (Step 06 §4 queries pass)
- ☐ Sequence values set correctly for SERIAL columns: `SELECT setval('schema.table_column_seq', (SELECT MAX(id) FROM schema.table));`

---

### Phase 4: Stored Procedure Migration (Days 9–11)

**Goal:** Convert T-SQL stored procedures to PL/pgSQL functions or Python service stubs.

**Estimated Effort:** 17 hours (Development: 7h · Testing: 8h · Documentation: 2h)

#### 4.1 sp_CalculateOptimalRotation → PL/pgSQL Function

**Source:** `CropPlanning.sp_CalculateOptimalRotation`
**Target:** `crop_management.calculate_optimal_rotation(p_field_id INT, p_current_year INT)`
**Returns:** `TABLE (crop_type_id INT, name VARCHAR, rotation_score NUMERIC, current_price NUMERIC(19,4), total_score NUMERIC)`

| T-SQL Pattern | PL/pgSQL Equivalent |
|---|---|
| `SET NOCOUNT ON` | *(removed — not applicable)* |
| `DECLARE @var TYPE` | `DECLARE v_var TYPE` |
| `SELECT @var = col FROM table` | `SELECT col INTO v_var FROM table` |
| `SELECT TOP 1 ... ORDER BY` | `ORDER BY ... LIMIT 1` |
| CTE (`WITH ... AS`) | Identical syntax |
| Implicit result set | `RETURNS TABLE (...)` + `RETURN QUERY` |

**Complexity:** 🔴 High (6–8 hours)

#### 4.2 sp_CalculateMemberPayment → PL/pgSQL Function

**Source:** `Settlement.sp_CalculateMemberPayment`
**Target:** `trading.calculate_member_payment(p_member_id INT, p_settlement_year INT)`
**Returns:** `NUMERIC(19,4)` (replaces `@TotalPayment MONEY OUTPUT`)

| T-SQL Pattern | PL/pgSQL Equivalent |
|---|---|
| `@TotalPayment MONEY OUTPUT` | `RETURNS NUMERIC(19,4)` |
| `YEAR(date)` | `EXTRACT(YEAR FROM date)::INT` |
| `CAST(col AS DECIMAL)` | `col::NUMERIC` |
| `MONEY` arithmetic | `NUMERIC(19,4)` arithmetic |
| `RETURN 0` (status) | `RETURN v_total_payment` (value) |

**Complexity:** 🔴 Critical (8–12 hours) — financial precision is paramount.

#### 4.3 Python Service Alternative

For long-term maintainability, stored procedures may be extracted to Python services:

```python
# Example: Python service for settlement calculation
from decimal import Decimal

def calculate_member_payment(member_id: int, settlement_year: int) -> Decimal:
    total_yield = get_member_total_yield(member_id, settlement_year)
    average_grade = get_average_grade(member_id, settlement_year)

    quality_multiplier = Decimal('1.00')
    if average_grade >= 90:
        quality_multiplier = Decimal('1.15')
    elif average_grade >= 80:
        quality_multiplier = Decimal('1.10')
    elif average_grade >= 70:
        quality_multiplier = Decimal('1.05')

    market_price = get_latest_market_price(settlement_year)
    return total_yield * market_price * quality_multiplier
```

> **Recommendation:** Implement both PL/pgSQL functions (for immediate parity) and Python service stubs (for future extraction). The PL/pgSQL functions serve as the migration target; Python services serve as the modernization target.

**Phase 4 Exit Criteria:**
- ☐ `calculate_optimal_rotation` returns valid crop recommendation for test inputs
- ☐ `calculate_member_payment` returns values matching SQL Server output within ±$0.01
- ☐ Financial precision regression tests pass for 100+ member/year combinations
- ☐ All T-SQL patterns converted (TOP→LIMIT, YEAR→EXTRACT, @vars→v_vars)
- ☐ Python service stubs documented for future extraction

---

### Phase 5: View Recreation (Day 12 AM)

**Goal:** Recreate the field productivity view with PostgreSQL syntax.

**Estimated Effort:** 2.5 hours (Development: 1h · Testing: 1h · Documentation: 0.5h)

**Source:** `CropManagement.vw_FieldProductivity`
**Target:** `crop_management.vw_field_productivity`

| Conversion | SQL Server | PostgreSQL |
|---|---|---|
| String concatenation | `m.FirstName + ' ' + m.LastName` | `m.first_name \|\| ' ' \|\| m.last_name` |
| Identifiers | `PascalCase` | `snake_case` |
| Schema references | `CropManagement.Fields` | `crop_management.fields` |

**Validation:**

```sql
-- Compare view output with source
SELECT * FROM crop_management.vw_field_productivity ORDER BY field_id;

-- Verify aggregations
SELECT
    COUNT(*) AS total_rows,
    SUM(total_yield) AS sum_yield,
    AVG(yield_per_acre) AS avg_yield_per_acre
FROM crop_management.vw_field_productivity;
```

**Phase 5 Exit Criteria:**
- ☐ View returns correct row count
- ☐ `total_yield`, `yield_per_acre`, `harvest_count` match source view output
- ☐ `member_name` concatenation renders correctly
- ☐ NULL handling correct for fields without harvests

---

### Phase 6: Validation (Days 12 PM – 14)

**Goal:** Execute the complete validation suite from Step 06 to verify data integrity, schema correctness, and functional equivalence.

**Estimated Effort:** 12 hours (all testing/validation)

#### 6.1 Row Count Validation

Run source vs. target row counts for all 6 tables. **PASS criteria:** exact match.

| Table (Source) | Table (Target) | Expected |
|---|---|---|
| `CropManagement.CropTypes` | `crop_management.crop_types` | 5 |
| `Members.MemberAccounts` | `members.member_accounts` | 3 |
| `CropManagement.Fields` | `crop_management.fields` | *match source* |
| `CropManagement.Harvests` | `crop_management.harvests` | *match source* |
| `Trading.CommodityPrices` | `trading.commodity_prices` | *match source* |
| `Inventory.FertilizerStock` | `inventory.fertilizer_stock` | *match source* |

#### 6.2 Schema Validation

Compare `INFORMATION_SCHEMA.COLUMNS` output between source and target for column names, data types, nullability, and defaults.

#### 6.3 Computed Column Validation

```sql
-- All rows must pass (zero FAILs)
SELECT COUNT(*) FILTER (WHERE validation_status = 'FAIL') AS failures
FROM (
    SELECT
        harvest_id,
        yield_bushels,
        crop_management.calculate_yield_bushels(quantity, unit_type) AS calculated,
        CASE WHEN yield_bushels = crop_management.calculate_yield_bushels(quantity, unit_type)
             THEN 'PASS' ELSE 'FAIL' END AS validation_status
    FROM crop_management.harvests
) sub;
```

#### 6.4 Foreign Key Integrity

```sql
-- Zero orphaned records expected
SELECT 'Orphaned fields' AS check_name, COUNT(*) AS issues
FROM crop_management.fields f
LEFT JOIN members.member_accounts m ON f.member_id = m.member_id
WHERE m.member_id IS NULL
UNION ALL
SELECT 'Orphaned harvests', COUNT(*)
FROM crop_management.harvests h
LEFT JOIN crop_management.fields f ON h.field_id = f.field_id
WHERE f.field_id IS NULL;
```

#### 6.5 Stored Procedure Output Comparison

Run both procedures with identical inputs on source and target; compare results:

```sql
-- PostgreSQL
SELECT trading.calculate_member_payment(1, 2025);

-- SQL Server (compare result)
DECLARE @Payment MONEY;
EXEC Settlement.sp_CalculateMemberPayment @MemberId = 1, @SettlementYear = 2025, @TotalPayment = @Payment OUTPUT;
SELECT @Payment;
```

#### 6.6 Full Validation Suite

Execute `Migration/Validation/validation_queries.sql` covering all 13 validation categories from Step 06.

**Phase 6 Exit Criteria:**
- ☐ All row counts match (0 discrepancies)
- ☐ All FK integrity checks pass (0 orphaned records)
- ☐ Computed column validation: 0 failures
- ☐ Stored procedure outputs match within ±$0.01
- ☐ View results match source output
- ☐ Trigger behavior verified (INSERT, UPDATE, DELETE)
- ☐ Seed data verified (5 crop types with correct attributes)
- ☐ Performance baselines captured with `EXPLAIN ANALYZE`
- ☐ Edge case tests pass (NULL yields, zero acreage, unknown units)

---

## 4. Rollback Procedures

### 4.1 Per-Phase Rollback Scripts

#### Phase 1 Rollback — Schema

```sql
-- Drop all tables, schemas, and extensions
DROP TABLE IF EXISTS audit.harvest_audit_log CASCADE;
DROP TABLE IF EXISTS trading.commodity_prices CASCADE;
DROP TABLE IF EXISTS inventory.fertilizer_stock CASCADE;
DROP TABLE IF EXISTS crop_management.harvests CASCADE;
DROP TABLE IF EXISTS crop_management.fields CASCADE;
DROP TABLE IF EXISTS crop_management.crop_types CASCADE;
DROP TABLE IF EXISTS members.member_accounts CASCADE;

DROP SCHEMA IF EXISTS audit CASCADE;
DROP SCHEMA IF EXISTS trading CASCADE;
DROP SCHEMA IF EXISTS inventory CASCADE;
DROP SCHEMA IF EXISTS crop_management CASCADE;
DROP SCHEMA IF EXISTS members CASCADE;

DROP EXTENSION IF EXISTS postgis CASCADE;
```

#### Phase 2 Rollback — Functions & Triggers

```sql
DROP TRIGGER IF EXISTS trg_audit_harvest_changes ON crop_management.harvests;
DROP FUNCTION IF EXISTS audit.fn_audit_harvest_changes();
DROP FUNCTION IF EXISTS crop_management.calculate_yield_bushels(NUMERIC, VARCHAR);
```

> **Note:** Dropping `calculate_yield_bushels` requires dropping `crop_management.harvests` first (generated column dependency).

#### Phase 3 Rollback — Data

```sql
-- Truncate all tables in reverse dependency order
TRUNCATE crop_management.harvests CASCADE;
TRUNCATE trading.commodity_prices CASCADE;
TRUNCATE crop_management.fields CASCADE;
TRUNCATE inventory.fertilizer_stock CASCADE;
TRUNCATE members.member_accounts CASCADE;
TRUNCATE crop_management.crop_types CASCADE;
TRUNCATE audit.harvest_audit_log;

-- Reset sequences
ALTER SEQUENCE crop_management.crop_types_crop_type_id_seq RESTART WITH 1;
ALTER SEQUENCE members.member_accounts_member_id_seq RESTART WITH 1;
ALTER SEQUENCE crop_management.fields_field_id_seq RESTART WITH 1;
ALTER SEQUENCE crop_management.harvests_harvest_id_seq RESTART WITH 1;
ALTER SEQUENCE inventory.fertilizer_stock_stock_id_seq RESTART WITH 1;
ALTER SEQUENCE trading.commodity_prices_price_id_seq RESTART WITH 1;
ALTER SEQUENCE audit.harvest_audit_log_audit_id_seq RESTART WITH 1;
```

#### Phase 4 Rollback — Stored Procedures

```sql
DROP FUNCTION IF EXISTS trading.calculate_member_payment(INT, INT);
DROP FUNCTION IF EXISTS crop_management.calculate_optimal_rotation(INT, INT);
```

#### Phase 5 Rollback — Views

```sql
DROP VIEW IF EXISTS crop_management.vw_field_productivity;
```

#### Complete Rollback Script

See Step 05 §9 (Script 7) for the full reverse-dependency-order rollback script.

### 4.2 Point-of-No-Return Criteria

The **point of no return** is reached when **all** of the following conditions are met:

| # | Criterion | Justification |
|---|---|---|
| 1 | Application connection strings switched to PostgreSQL | Application writes going to new database |
| 2 | Source SQL Server set to `READ_ONLY` for > 24 hours | No new data being written to source |
| 3 | All Phase 6 validation checks pass | Data integrity confirmed |
| 4 | Financial settlement calculations match within tolerance (±$0.01) | Business-critical precision verified |
| 5 | Compliance officer sign-off on audit trail format | Regulatory requirement met |
| 6 | 48-hour parallel run with zero critical incidents | Stability confirmed |

**Before point-of-no-return:** Rollback is simple — switch connection strings back to SQL Server, restore from backup if needed, and set SQL Server back to `READ_WRITE`.

**After point-of-no-return:** Rollback requires reverse migration (PostgreSQL → SQL Server) which is significantly more complex. Source system is decommissioned after 30-day retention period.

### 4.3 Data Preservation

| Strategy | Detail |
|---|---|
| **Source backup retention** | Keep SQL Server full backup for 90 days post-migration |
| **Source system read-only** | SQL Server remains in `READ_ONLY` mode for 30 days as hot standby |
| **PostgreSQL snapshots** | Take `pg_dump` snapshot before each migration phase |
| **Audit trail** | All migration operations logged to `audit.harvest_audit_log` via trigger |
| **Version control** | All migration scripts committed to repository under `Migration/Scripts/` |

---

## 5. Risk Register

### 5.1 Computed Column with UDF (🔴 Critical)

| Attribute | Detail |
|---|---|
| **Risk ID** | R-001 |
| **Description** | `Harvests.YieldBushels` is a SQL Server PERSISTED computed column referencing `dbo.fn_CalculateYieldBushels`. PostgreSQL `GENERATED ALWAYS AS ... STORED` requires the referenced function to be `IMMUTABLE`. |
| **Affected Objects** | `crop_management.harvests`, `crop_management.calculate_yield_bushels`, `vw_field_productivity`, `trading.calculate_member_payment` |
| **Likelihood** | High (known incompatibility) |
| **Impact** | 🔴 Critical — cascading failure across views, procedures, and settlement calculations |
| **Mitigation** | Create function as `IMMUTABLE` (qualifies — pure function with deterministic output). PG 16+ supports this. Fallback: inline CASE expression directly in generated column. |
| **Validation** | `SELECT COUNT(*) FROM harvests WHERE yield_bushels != calculate_yield_bushels(quantity, unit_type)` → expect 0 |
| **Owner** | Backend Developer |

### 5.2 GEOGRAPHY to PostGIS Conversion (🔴 High)

| Attribute | Detail |
|---|---|
| **Risk ID** | R-002 |
| **Description** | SQL Server `GEOGRAPHY` uses geodetic coordinates (lat/lng order). PostGIS `GEOMETRY(POLYGON, 4326)` uses Cartesian coordinates (lng/lat order). Coordinate ordering mismatch can silently corrupt spatial boundaries. |
| **Affected Objects** | `crop_management.fields.gps_boundary` |
| **Likelihood** | High (known difference) |
| **Impact** | 🔴 High — corrupted field boundaries affect acreage calculations and GPS-based queries |
| **Mitigation** | Export boundaries as WKT (`STAsText()`), validate coordinate ordering, import via `ST_GeomFromText()` with SRID 4326 enforcement. Validate 10+ known boundaries post-migration. |
| **Validation** | Compare `ST_AsText(gps_boundary)` output with source `GPSBoundary.STAsText()` for all fields |
| **Owner** | DBA — PostgreSQL |

### 5.3 MONEY Type Precision (🟡 Medium-High)

| Attribute | Detail |
|---|---|
| **Risk ID** | R-003 |
| **Description** | SQL Server `MONEY` type (8-byte, 4 decimal places) has implicit rounding rules that differ from PostgreSQL `NUMERIC(19,4)`. Mixed `MONEY × DECIMAL` arithmetic in SQL Server returns `MONEY`; in PostgreSQL all values are `NUMERIC` with different rounding. |
| **Affected Objects** | `inventory.fertilizer_stock.cost_per_unit`, `trading.commodity_prices.price_per_bushel`, `trading.calculate_member_payment` |
| **Likelihood** | Medium |
| **Impact** | 🔴 High — financial settlement errors directly affect member payments |
| **Mitigation** | Run parallel calculations for 100+ member/year combinations on both systems. Define tolerance: ±$0.01 per transaction. Log intermediate calculation values to identify divergence point. |
| **Validation** | Side-by-side `sp_CalculateMemberPayment` vs `calculate_member_payment` comparison |
| **Owner** | QA / Validation Lead |

### 5.4 Trigger JSON Serialization Format (🟡 Medium)

| Attribute | Detail |
|---|---|
| **Risk ID** | R-004 |
| **Description** | SQL Server `FOR JSON AUTO` produces JSON with PascalCase keys and array-wrapped output. PostgreSQL `row_to_json()` / `to_jsonb()` produces flat JSON objects with snake_case keys. Downstream USDA reporting parsers may depend on specific JSON structure. |
| **Affected Objects** | `audit.harvest_audit_log.old_value`, `audit.harvest_audit_log.new_value` |
| **Likelihood** | Medium |
| **Impact** | 🟡 Medium — breaks downstream JSON parsers if they expect specific key names or structure |
| **Mitigation** | Document expected JSON format changes. Obtain compliance officer sign-off. If exact format match required, create a wrapper function that transforms `to_jsonb()` output to match `FOR JSON AUTO` structure. |
| **Validation** | Compare 10 sample audit entries side-by-side |
| **Owner** | Compliance Officer |

### 5.5 Business Logic in Stored Procedures (🟡 Medium)

| Attribute | Detail |
|---|---|
| **Risk ID** | R-005 |
| **Description** | 2 stored procedures contain critical business rules (crop rotation scoring algorithm and financial settlement calculation). T-SQL to PL/pgSQL conversion introduces risk of logic errors, especially in the quality multiplier and scoring formulas. |
| **Affected Objects** | `crop_management.calculate_optimal_rotation`, `trading.calculate_member_payment` |
| **Likelihood** | Medium |
| **Impact** | 🔴 High — incorrect crop recommendations or payment calculations |
| **Mitigation** | Line-by-line conversion review. Parallel execution testing with identical inputs. Python service stubs as independent validation of business logic. Code review by second developer. |
| **Validation** | Execute both procedures with 20+ test scenarios including edge cases (zero yield, NULL grades, missing prices) |
| **Owner** | Backend Developer + QA Lead |

### Risk Summary Matrix

| Risk ID | Risk | Likelihood | Impact | Priority |
|---|---|---|---|---|
| R-001 | Computed column with UDF | High | 🔴 Critical | **P1** |
| R-002 | GEOGRAPHY → PostGIS coordinates | High | 🔴 High | **P1** |
| R-003 | MONEY precision divergence | Medium | 🔴 High | **P2** |
| R-004 | Trigger JSON format change | Medium | 🟡 Medium | **P3** |
| R-005 | Business logic in stored procs | Medium | 🔴 High | **P2** |

---

## 6. Validation Checklist

### 6.1 Data Integrity Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 1 | **Row counts** — all 6 tables | Step 06 §1 source vs target | Exact match | ☐ |
| 2 | **Schema validation** — column types, nullability, defaults | Step 06 §2 information_schema comparison | All columns match design (Step 04) | ☐ |
| 3 | **FK integrity** — no orphaned records | Step 06 §4 LEFT JOIN checks | 0 orphaned records | ☐ |
| 4 | **Constraint validation** — CHECK, UNIQUE, NOT NULL | Step 06 §6 constraint queries | All constraints enforced | ☐ |
| 5 | **Data type fidelity** — MONEY, DECIMAL precision | Step 06 §7 type comparison | All values within tolerance | ☐ |

### 6.2 Computed Column Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 6 | **yield_bushels** — generated column matches function | `WHERE yield_bushels != calculate_yield_bushels(...)` | 0 mismatches | ☐ |
| 7 | **Unit conversion — bushels** | `calculate_yield_bushels(100, 'bushels')` | = 100.00 | ☐ |
| 8 | **Unit conversion — tonnes** | `calculate_yield_bushels(100, 'tonnes')` | = 3674.37 | ☐ |
| 9 | **Unit conversion — hundredweight** | `calculate_yield_bushels(100, 'hundredweight')` | = 166.70 | ☐ |
| 10 | **Unit conversion — kilograms** | `calculate_yield_bushels(100, 'kilograms')` | = 3.67 | ☐ |
| 11 | **Unit conversion — unknown** | `calculate_yield_bushels(50, 'pounds')` | = 50.00 | ☐ |

### 6.3 Stored Procedure Output Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 12 | **calculate_optimal_rotation** — valid recommendation | `SELECT * FROM calculate_optimal_rotation(1, 2026)` | Returns 1 row with valid crop_type_id | ☐ |
| 13 | **calculate_member_payment** — financial accuracy | Side-by-side comparison for all member/year combos | ±$0.01 tolerance | ☐ |
| 14 | **Edge case: zero yield** | `calculate_member_payment` with member having no harvests | Returns NULL or 0 (match source) | ☐ |
| 15 | **Edge case: NULL grade** | Payment calculation with NULL grade_code | Handles gracefully (match source) | ☐ |

### 6.4 View Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 16 | **vw_field_productivity** — row count | `SELECT COUNT(*) FROM vw_field_productivity` | Matches source view | ☐ |
| 17 | **vw_field_productivity** — total_yield | `SUM(total_yield)` comparison | Matches source | ☐ |
| 18 | **vw_field_productivity** — yield_per_acre** | `AVG(yield_per_acre)` comparison | Matches source | ☐ |
| 19 | **vw_field_productivity** — member_name** | String concatenation renders correctly | "FirstName LastName" format | ☐ |

### 6.5 Trigger Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 20 | **INSERT audit** | Insert harvest row; check audit log | `change_type = 'INSERT'`, valid JSON in `new_value` | ☐ |
| 21 | **UPDATE audit** | Update harvest row; check audit log | `change_type = 'UPDATE'`, both `old_value` and `new_value` populated | ☐ |
| 22 | **DELETE audit** | Delete harvest row; check audit log | `change_type = 'DELETE'`, valid JSON in `old_value` | ☐ |
| 23 | **Audit log `changed_by`** | Verify current user captured | Matches connected PostgreSQL user | ☐ |

### 6.6 Infrastructure Validation

| # | Check | Query/Method | Pass Criteria | Status |
|---|---|---|---|---|
| 24 | **PostGIS extension** | `SELECT PostGIS_Version()` | Returns 3.4.x | ☐ |
| 25 | **All indexes exist** | `SELECT indexname FROM pg_indexes WHERE schemaname IN (...)` | 14+ indexes present | ☐ |
| 26 | **GiST spatial index** | `SELECT indexname FROM pg_indexes WHERE indexname = 'idx_fields_gps_boundary'` | Exists | ☐ |
| 27 | **Seed data** | `SELECT COUNT(*) FROM crop_management.crop_types` | = 5 | ☐ |
| 28 | **Performance baseline** | `EXPLAIN ANALYZE` on key queries | No sequential scans on indexed columns | ☐ |

---

## 7. Communication Plan

### 7.1 Stakeholder Communication Schedule

| Timing | Audience | Channel | Message | Owner |
|---|---|---|---|---|
| **Day −7** (Pre-migration) | All stakeholders | Email + Meeting | Migration schedule, expected downtime, rollback plan | Migration Lead |
| **Day −3** (Pre-migration) | Engineering team | Slack/Teams | Environment setup complete, dry-run results, script review status | Migration Lead |
| **Day −1** (Pre-migration) | All stakeholders | Email | Final Go/No-Go decision, maintenance window confirmation | Migration Lead |
| **Day 1** (Migration start) | All stakeholders | Email + Status page | Migration started, source system in read-only mode | Migration Lead |
| **Day 8** (Data migration) | Engineering + Compliance | Slack/Teams | Data transfer complete, validation in progress | QA Lead |
| **Day 12** (Views + Validation) | All stakeholders | Email | All migration phases complete, validation in progress | Migration Lead |
| **Day 14** (Validation complete) | All stakeholders | Email + Meeting | Validation results, Go/No-Go for production cutover | Migration Lead |
| **Day 15** (Cutover) | All stakeholders | Email + Status page | Application switched to PostgreSQL, monitoring active | Migration Lead |
| **Day 19** (Stabilization end) | All stakeholders | Email | Stabilization period complete, migration successful | Migration Lead |

### 7.2 Escalation Path

| Severity | Example | Escalation | Response Time |
|---|---|---|---|
| 🟢 Low | Index missing, minor performance difference | Migration Lead | 4 hours |
| 🟡 Medium | View output discrepancy, non-critical data mismatch | Migration Lead → DBA Team | 2 hours |
| 🔴 High | Financial calculation mismatch, FK integrity failure | Migration Lead → Engineering Manager | 1 hour |
| 🚨 Critical | Data loss, audit trail corruption, compliance failure | Migration Lead → VP Engineering + Compliance | 30 minutes |

### 7.3 Status Reporting

- **Daily standups** during migration window (Days 4–14)
- **Phase completion reports** posted to shared Slack/Teams channel
- **Validation dashboard** (shared spreadsheet tracking all 28 checklist items)
- **Post-migration retrospective** at Day 19

---

## 8. Post-Migration Tasks

### 8.1 Performance Tuning

| # | Task | Action | Priority |
|---|---|---|---|
| 1 | **Run ANALYZE** on all tables | `ANALYZE crop_management.harvests;` (repeat for all tables) | Immediate |
| 2 | **Capture query plans** | Run `EXPLAIN ANALYZE` on top 10 most frequent queries | Day 15 |
| 3 | **Compare execution times** | Source (SQL Server) vs Target (PostgreSQL) for critical queries | Day 15–16 |
| 4 | **Tune `work_mem`** | Adjust for settlement calculation complexity | Day 16 |
| 5 | **Tune `shared_buffers`** | Set to 25% of available RAM for Azure Flexible Server | Day 15 |
| 6 | **Connection pooling** | Configure PgBouncer or Azure built-in connection pooling | Day 15 |

### 8.2 Monitoring Setup

| # | Metric | Tool | Threshold |
|---|---|---|---|
| 1 | Query execution time (P95, P99) | Azure Monitor / pg_stat_statements | < 2× SQL Server baseline |
| 2 | Connection count | Azure Monitor | < 80% of `max_connections` |
| 3 | Disk usage growth | Azure Monitor | Alert at 80% capacity |
| 4 | Lock wait time | `pg_stat_activity` | Alert if > 5 seconds |
| 5 | Replication lag (if applicable) | Azure Monitor | < 1 second |
| 6 | Autovacuum activity | `pg_stat_user_tables` (dead tuple count) | `n_dead_tup` < 10% of `n_live_tup` |
| 7 | Audit log growth | `SELECT COUNT(*) FROM audit.harvest_audit_log` | Monitor daily |

### 8.3 Index Optimization

| # | Task | Action | Timeline |
|---|---|---|---|
| 1 | **Verify index usage** | `SELECT * FROM pg_stat_user_indexes WHERE idx_scan = 0;` | Day 16 |
| 2 | **Remove unused indexes** | Drop indexes with zero scans after 7 days of monitoring | Day 22 |
| 3 | **Add missing indexes** | Review `pg_stat_user_tables` for sequential scans on large tables | Day 16 |
| 4 | **Spatial index validation** | `EXPLAIN ANALYZE SELECT * FROM fields WHERE ST_Contains(gps_boundary, ST_Point(-95.5, 40.5))` | Day 16 |
| 5 | **Partial indexes** | Consider partial indexes for `status = 'Active'` on `member_accounts` | Day 22 |
| 6 | **REINDEX** | Rebuild indexes after bulk data load: `REINDEX TABLE crop_management.harvests;` | Day 15 |

### 8.4 Application Updates

| # | Task | Owner | Timeline |
|---|---|---|---|
| 1 | Update connection strings | Application Developer | Day 15 |
| 2 | Update ORM configuration (if applicable) | Application Developer | Day 15 |
| 3 | Replace MONEY-type handling in application code | Application Developer | Day 15–16 |
| 4 | Update stored procedure call patterns (EXEC → SELECT function()) | Application Developer | Day 15 |
| 5 | Update spatial query syntax (SQL Server spatial → PostGIS) | Application Developer | Day 16 |
| 6 | Feature flag: PostgreSQL connection enabled | Application Developer | Day 15 |

### 8.5 Documentation Updates

| # | Document | Update Required | Owner |
|---|---|---|---|
| 1 | API documentation | New connection parameters, function call syntax | Application Developer |
| 2 | Runbook | PostgreSQL-specific maintenance procedures | DBA — PostgreSQL |
| 3 | Disaster recovery plan | PostgreSQL backup/restore procedures | DBA — PostgreSQL |
| 4 | USDA compliance documentation | Updated audit trail format (JSONB) | Compliance Officer |
| 5 | Schema documentation | snake_case naming, new data types | Migration Lead |

---

## 9. Go/No-Go Decision Criteria

### 9.1 Go Criteria (ALL must be met)

| # | Criterion | Metric | Measured By |
|---|---|---|---|
| 1 | **Row count parity** | 100% match across all 6 tables | Validation query (Step 06 §1) |
| 2 | **Zero FK violations** | 0 orphaned records in all FK checks | Validation query (Step 06 §4) |
| 3 | **Computed column accuracy** | 0 mismatches in yield_bushels | Validation query (Step 06 §3) |
| 4 | **Financial precision** | Settlement calculations within ±$0.01 for all test cases | Parallel execution comparison |
| 5 | **Audit trigger functional** | INSERT/UPDATE/DELETE all logged with valid JSONB | Manual test + automated validation |
| 6 | **View output match** | vw_field_productivity results identical to source | Side-by-side comparison |
| 7 | **PostGIS functional** | Spatial queries return correct results; GiST index active | `EXPLAIN ANALYZE` on spatial query |
| 8 | **Performance acceptable** | No query > 3× slower than SQL Server baseline | `EXPLAIN ANALYZE` comparison |
| 9 | **Compliance sign-off** | Written approval from Compliance Officer on audit format | Email/ticket confirmation |
| 10 | **Dry-run successful** | Complete migration executed on staging environment | Migration Lead sign-off |
| 11 | **Rollback tested** | Full rollback script executed successfully on staging | DBA sign-off |
| 12 | **Backup verified** | SQL Server backup integrity confirmed via `RESTORE VERIFYONLY` | DBA sign-off |

### 9.2 No-Go Criteria (ANY triggers postponement)

| # | Criterion | Action |
|---|---|---|
| 1 | Row count mismatch on any table | Investigate data loss; re-extract from source |
| 2 | Financial calculation exceeds ±$0.01 tolerance | Root-cause MONEY→NUMERIC rounding; adjust conversion |
| 3 | Computed column mismatch | Debug `IMMUTABLE` function; verify conversion factors |
| 4 | FK integrity failures | Fix data ordering; re-load in correct dependency order |
| 5 | PostGIS extension unavailable on target | Provision extension or adjust Azure server configuration |
| 6 | Compliance officer rejects audit format | Build JSON format adapter function |
| 7 | Rollback script fails on staging | Fix dependency ordering; re-test |
| 8 | Unresolved P1 or P2 risk items | Defer migration until resolved |

### 9.3 Decision Timeline

| Date | Milestone | Decision |
|---|---|---|
| Day 11 (end of Phase 4) | All migration phases complete | Preliminary Go/No-Go |
| Day 14 (end of Phase 6) | Full validation complete | Final Go/No-Go for cutover |
| Day 15 | Cutover window opens | Execute or defer |

**Decision Authority:** Migration Lead with sign-off from DBA Lead, Engineering Manager, and Compliance Officer.

---

## 10. Appendices

### Appendix A — Reference Commands

#### Docker Environment

```bash
# Start all containers
docker compose up -d

# Stop all containers (preserves volumes)
docker compose stop

# Destroy containers and volumes (full reset)
docker compose down -v

# View container logs
docker compose logs -f sqlserver
docker compose logs -f postgis
```

#### SQL Server Connection

```bash
# sqlcmd via Docker
docker compose exec sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P 'GreenHarvest2024!' -d GreenHarvest

# Set database to read-only (cutover day)
sqlcmd -S localhost -U sa -P 'GreenHarvest2024!' \
  -Q "ALTER DATABASE GreenHarvest SET READ_ONLY;"

# Full backup
sqlcmd -S localhost -U sa -P 'GreenHarvest2024!' \
  -Q "BACKUP DATABASE GreenHarvest TO DISK = '/var/opt/mssql/backup/GreenHarvest.bak' WITH COMPRESSION, CHECKSUM;"
```

#### PostgreSQL Connection

```bash
# psql via Docker (PostgreSQL 16)
docker compose exec postgres psql -U postgres -d greenharvest

# psql via Docker (PostGIS 16-3.4)
docker compose exec postgis psql -U postgres -d greenharvest

# Azure PostgreSQL (replace placeholders)
psql "host=<server>.postgres.database.azure.com dbname=greenharvest user=<user> password=<password> sslmode=require"
```

#### Migration Script Execution

```bash
# Execute complete migration (single transaction)
psql -U postgres -d greenharvest -f Migration/Scripts/001_create_schema.sql

# Execute validation queries
psql -U postgres -d greenharvest -f Migration/Validation/validation_queries.sql

# Execute rollback (emergency)
psql -U postgres -d greenharvest -f Migration/Scripts/rollback.sql
```

#### Validation Commands

```bash
# Row count comparison (quick check)
psql -U postgres -d greenharvest -c "
SELECT 'crop_types' AS tbl, COUNT(*) FROM crop_management.crop_types
UNION ALL SELECT 'member_accounts', COUNT(*) FROM members.member_accounts
UNION ALL SELECT 'fields', COUNT(*) FROM crop_management.fields
UNION ALL SELECT 'harvests', COUNT(*) FROM crop_management.harvests
UNION ALL SELECT 'commodity_prices', COUNT(*) FROM trading.commodity_prices
UNION ALL SELECT 'fertilizer_stock', COUNT(*) FROM inventory.fertilizer_stock
ORDER BY tbl;"

# PostGIS verification
psql -U postgres -d greenharvest -c "SELECT PostGIS_Full_Version();"

# Function test
psql -U postgres -d greenharvest -c "SELECT crop_management.calculate_yield_bushels(100, 'tonnes');"

# Index inventory
psql -U postgres -d greenharvest -c "
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname IN ('crop_management','members','inventory','trading','audit')
ORDER BY schemaname, tablename, indexname;"
```

#### Performance Baseline

```bash
# Enable timing
psql -U postgres -d greenharvest -c "\timing on"

# Analyze all tables
psql -U postgres -d greenharvest -c "ANALYZE;"

# Check for sequential scans
psql -U postgres -d greenharvest -c "
SELECT schemaname, relname, seq_scan, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_scan DESC;"
```

### Appendix B — Data Type Conversion Quick Reference

| SQL Server | PostgreSQL | Notes |
|---|---|---|
| `INT IDENTITY(1,1)` | `SERIAL` | Creates implicit sequence |
| `NVARCHAR(n)` | `VARCHAR(n)` | PostgreSQL is natively UTF-8 |
| `DECIMAL(p,s)` | `NUMERIC(p,s)` | Functionally identical |
| `MONEY` | `NUMERIC(19,4)` | Avoid PostgreSQL `money` type |
| `DATE` | `DATE` | No change |
| `DATETIME` | `TIMESTAMP` | Consider `TIMESTAMPTZ` for TZ awareness |
| `GEOGRAPHY` | `GEOMETRY(POLYGON, 4326)` | Requires PostGIS; SRID 4326 = WGS 84 |
| `GETDATE()` | `CURRENT_TIMESTAMP` | Standard SQL |
| `SUSER_SNAME()` | `current_user` | Session role name |
| `FOR JSON AUTO` | `row_to_json()` / `to_jsonb()` | Native JSON support |
| `+` (string concat) | `\|\|` | Operator change |
| `TOP N` | `LIMIT N` | End of query |
| `YEAR(date)` | `EXTRACT(YEAR FROM date)` | Returns `double precision`; cast to `INT` |

### Appendix C — Naming Convention Mapping

| SQL Server | PostgreSQL | Example |
|---|---|---|
| PascalCase tables | snake_case tables | `CropTypes` → `crop_types` |
| PascalCase columns | snake_case columns | `CropTypeId` → `crop_type_id` |
| `IX_Table_Column` indexes | `idx_table_column` | `IX_CropTypes_Name` → `idx_crop_types_name` |
| `FK_Child_Parent` | `fk_child_parent` | `FK_Fields_Member` → `fk_fields_member` |
| `fn_FunctionName` | `function_name` | `fn_CalculateYieldBushels` → `calculate_yield_bushels` |
| `sp_ProcedureName` | `function_name` | `sp_CalculateOptimalRotation` → `calculate_optimal_rotation` |
| `tr_TriggerName` | `trg_name` + `fn_name` | `tr_AuditHarvestChanges` → `trg_audit_harvest_changes` |
| `vw_ViewName` | `vw_view_name` | `vw_FieldProductivity` → `vw_field_productivity` |

### Appendix D — Schema Mapping

| SQL Server Schema | PostgreSQL Schema | Notes |
|---|---|---|
| `CropManagement` | `crop_management` | Core agricultural operations |
| `Members` | `members` | Co-op member management |
| `Inventory` | `inventory` | Stock tracking |
| `Trading` | `trading` | Market pricing + settlement |
| `Audit` | `audit` | Compliance change logs |
| `dbo` | *(merged into `crop_management`)* | Utility function relocated |
| `CropPlanning` | *(merged into `crop_management`)* | Rotation procedure |
| `Settlement` | *(merged into `trading`)* | Payment procedure |

### Appendix E — Dependency Graph

```
MemberAccounts ──────┐
                     ├──→ Fields ──────→ Harvests ──→ tr_AuditHarvestChanges
CropTypes ───────────┤                      │               │
                     ├──→ CommodityPrices   │               └──→ Audit.HarvestAuditLog
                     │                      │
fn_CalculateYieldBushels ───────────────────┘
                                            │
                                   vw_FieldProductivity
                                            │
                           ┌────────────────┴────────────────┐
              calculate_optimal_rotation    calculate_member_payment
```

### Appendix F — File Inventory

| File | Purpose |
|---|---|
| `assets/outputs/step-01-explore-legacy-db.md` | Comprehensive SQL Server database analysis |
| `assets/outputs/step-02-database-specification.md` | Complete database specification |
| `assets/outputs/step-03-migration-complexity.md` | Per-object complexity assessment and effort estimation |
| `assets/outputs/step-04-target-schema.md` | PostgreSQL target schema design |
| `assets/outputs/step-05-migration-scripts.md` | Complete migration scripts (7 scripts) |
| `assets/outputs/step-06-data-validation.md` | Validation queries (13 categories) |
| `assets/outputs/step-07-migration-plan.md` | **This document** |
| `Schema/` | Source SQL Server DDL (tables, procedures, functions, triggers, views) |
| `Migration/Scripts/001_create_schema.sql` | PostgreSQL DDL migration script |
| `Migration/Validation/validation_queries.sql` | PostgreSQL validation queries |
| `Data/SeedData/CropTypes.sql` | Seed data (5 crop types) |
| `Data/SampleData/Members.sql` | Sample data (3 member accounts) |
| `Specs/schema-spec/database-specification.md` | Database schema specification |
| `docker-compose.yml` | Docker environment (SQL Server 2019, PostgreSQL 16, PostGIS 16-3.4) |

---

*Document generated as part of the Spec2Cloud spec-driven database migration methodology.*
*Reference: Steps 01–06 in `assets/outputs/` for detailed analysis, scripts, and validation procedures.*
