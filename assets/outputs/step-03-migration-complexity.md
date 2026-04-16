# Step 03 — Migration Complexity Analysis

## GreenHarvest SQL Server → PostgreSQL Migration

| Attribute | Value |
|---|---|
| **Source System** | SQL Server 2012 Standard Edition |
| **Target System** | Azure Database for PostgreSQL |
| **Database Name** | GreenHarvest |
| **Analysis Date** | 2026-04-16 |
| **Total Objects in Scope** | 6 Tables, 2 Stored Procedures, 1 Function, 1 Trigger, 1 View |

---

## 1. Per-Table Complexity Assessment

### 1.1 CropTypes (`CropManagement.CropTypes`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🟢 **Low** |
| **Effort** | 1 hour |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| CropTypeId | `INT IDENTITY(1,1)` | `SERIAL` | PK, auto-increment |
| Name | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| GrowingSeason | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| DaysToMaturity | `INT` | `INT` | No change |
| MinTemperature | `DECIMAL(5,2)` | `NUMERIC(5,2)` | Direct mapping |
| MaxTemperature | `DECIMAL(5,2)` | `NUMERIC(5,2)` | Direct mapping |
| WaterRequirement | `NVARCHAR(20)` | `VARCHAR(20)` | Direct mapping |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** Straightforward column types with no computed columns, no spatial data, no UDF references. Two standard indexes (`IX_CropTypes_Name`, `IX_CropTypes_Season`) translate directly. This is a reference/lookup table with no complex dependencies.

**Risks:** None. This is a foundational table referenced by FK from Fields, Harvests, and CommodityPrices — it must be migrated first.

---

### 1.2 Fields (`CropManagement.Fields`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **High** |
| **Effort** | 4–6 hours |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| FieldId | `INT IDENTITY(1,1)` | `SERIAL` | PK |
| MemberId | `INT NOT NULL` | `INT NOT NULL` | FK → MemberAccounts |
| FieldName | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| Acreage | `DECIMAL(10,2)` | `NUMERIC(10,2)` | Direct mapping |
| SoilType | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| IrrigationType | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| GPSBoundary | `GEOGRAPHY` | `GEOMETRY(Geometry,4326)` | **⚠ Requires PostGIS** |
| CurrentCropId | `INT` | `INT` | FK → CropTypes (nullable) |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** The `GEOGRAPHY` column (`GPSBoundary`) is the primary complexity driver. This requires:
1. Enabling the PostGIS extension on the target PostgreSQL instance (`CREATE EXTENSION postgis;`).
2. Mapping SQL Server `GEOGRAPHY` (which uses geodetic coordinates) to PostGIS `GEOMETRY(Geometry, 4326)` with SRID 4326.
3. Validating spatial data integrity after migration — coordinate order (lat/lng vs lng/lat) differs between SQL Server and PostGIS.
4. Any spatial queries or index operations on this column must be rewritten to use PostGIS functions (`ST_Contains`, `ST_Distance`, etc.).

Additionally, this table has two foreign keys (`FK_Fields_Member` → MemberAccounts, `FK_Fields_CurrentCrop` → CropTypes) creating a cross-schema dependency that dictates migration ordering.

**Risks:**
- Spatial data coordinate ordering may silently corrupt boundaries if not validated.
- PostGIS extension must be provisioned on the Azure PostgreSQL instance (requires `azure.extensions` server parameter).

---

### 1.3 Harvests (`CropManagement.Harvests`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **Critical** |
| **Effort** | 6–10 hours |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| HarvestId | `INT IDENTITY(1,1)` | `SERIAL` | PK |
| FieldId | `INT NOT NULL` | `INT NOT NULL` | FK → Fields |
| CropTypeId | `INT NOT NULL` | `INT NOT NULL` | FK → CropTypes |
| HarvestDate | `DATE` | `DATE` | No change |
| YieldBushels | `AS (dbo.fn_CalculateYieldBushels(...)) PERSISTED` | `NUMERIC(12,2) GENERATED ALWAYS AS (...) STORED` | **⚠ Critical: UDF in computed column** |
| Quantity | `DECIMAL(12,2)` | `NUMERIC(12,2)` | Direct mapping |
| UnitType | `NVARCHAR(20)` | `VARCHAR(20)` | Direct mapping |
| MoistureContent | `DECIMAL(5,2)` | `NUMERIC(5,2)` | Direct mapping |
| GradeCode | `NVARCHAR(10)` | `VARCHAR(10)` | Direct mapping |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** This table has the highest complexity in the entire schema due to:

1. **Computed column with UDF dependency:** `YieldBushels` is defined as `dbo.fn_CalculateYieldBushels(Quantity, UnitType) PERSISTED`. PostgreSQL's `GENERATED ALWAYS AS ... STORED` columns **cannot reference user-defined functions** — only immutable expressions are permitted. This is a **blocking issue** that requires one of:
   - **Option A:** Inline the CASE expression directly in the generated column definition (preferred if the logic is stable).
   - **Option B:** Use a trigger to populate the column on INSERT/UPDATE.
   - **Option C:** Move the calculation to application logic and store as a regular column.

2. **Trigger dependency:** `tr_AuditHarvestChanges` fires on this table for INSERT, UPDATE, and DELETE. The trigger must be migrated and validated before this table can be considered production-ready.

3. **Downstream dependencies:** The `YieldBushels` column is referenced by `sp_CalculateMemberPayment`, `sp_CalculateOptimalRotation` (indirectly via view), and `vw_FieldProductivity`. Any change to how this value is computed has cascading effects.

**Risks:**
- PostgreSQL `GENERATED ALWAYS AS` does not support non-immutable function references — the UDF must be marked `IMMUTABLE` or inlined.
- If the function is inlined, future changes to conversion factors require DDL changes rather than function updates.
- The audit trigger must be adapted before data loads to ensure regulatory compliance from day one.

---

### 1.4 MemberAccounts (`Members.MemberAccounts`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🟢 **Low** |
| **Effort** | 1 hour |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| MemberId | `INT IDENTITY(1,1)` | `SERIAL` | PK |
| MemberNumber | `NVARCHAR(20) UNIQUE NOT NULL` | `VARCHAR(20) UNIQUE NOT NULL` | Direct mapping |
| FirstName | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| LastName | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| Email | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| PhoneNumber | `NVARCHAR(20)` | `VARCHAR(20)` | Direct mapping |
| Address | `NVARCHAR(200)` | `VARCHAR(200)` | Direct mapping |
| City | `NVARCHAR(50)` | `VARCHAR(50)` | Direct mapping |
| State | `NVARCHAR(2)` | `VARCHAR(2)` | Direct mapping |
| ZipCode | `NVARCHAR(10)` | `VARCHAR(10)` | Direct mapping |
| MembershipDate | `DATE` | `DATE` | No change |
| Status | `NVARCHAR(20) DEFAULT 'Active'` | `VARCHAR(20) DEFAULT 'Active'` | Direct mapping |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |
| ModifiedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** Pure data table with standard column types, no computed columns, no spatial data, no triggers. Two straightforward indexes. Referenced by Fields via FK — must be migrated before Fields.

**Risks:** None.

---

### 1.5 FertilizerStock (`Inventory.FertilizerStock`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🟡 **Medium** |
| **Effort** | 2 hours |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| StockId | `INT IDENTITY(1,1)` | `SERIAL` | PK |
| ProductName | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| ManufacturerName | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| QuantityOnHand | `DECIMAL(12,2)` | `NUMERIC(12,2)` | Direct mapping |
| Unit | `NVARCHAR(20)` | `VARCHAR(20)` | Direct mapping |
| CostPerUnit | `MONEY` | `NUMERIC(19,4)` | **⚠ Type change** |
| ReorderLevel | `DECIMAL(12,2)` | `NUMERIC(12,2)` | Direct mapping |
| LastRestockDate | `DATE` | `DATE` | No change |
| ExpirationDate | `DATE` | `DATE` | No change |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** The `MONEY` type on `CostPerUnit` requires conversion to `NUMERIC(19,4)`. SQL Server `MONEY` stores values with 4 decimal places in a fixed-point format, while PostgreSQL has no native `MONEY` equivalent suitable for financial calculations. The database specification also notes that reorder-level automation is handled via triggers (not included in this scope), which may need separate analysis.

**Risks:**
- `MONEY` → `NUMERIC(19,4)`: Ensure application code does not depend on SQL Server–specific `MONEY` arithmetic behavior (implicit rounding rules differ).
- The specification references reorder-level automation triggers not included in the current schema extract.

---

### 1.6 CommodityPrices (`Trading.CommodityPrices`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🟡 **Medium** |
| **Effort** | 2 hours |

**Schema Summary:**

| Column | SQL Server Type | PostgreSQL Type | Notes |
|---|---|---|---|
| PriceId | `INT IDENTITY(1,1)` | `SERIAL` | PK |
| CropTypeId | `INT NOT NULL` | `INT NOT NULL` | FK → CropTypes |
| MarketDate | `DATE` | `DATE` | No change |
| PricePerBushel | `MONEY` | `NUMERIC(19,4)` | **⚠ Type change** |
| MarketName | `NVARCHAR(100)` | `VARCHAR(100)` | Direct mapping |
| CreatedDate | `DATETIME DEFAULT GETDATE()` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | Function swap |

**Justification:** Like FertilizerStock, the primary complexity is the `MONEY` → `NUMERIC(19,4)` conversion. Additionally, `PricePerBushel` is referenced in both stored procedures (`sp_CalculateOptimalRotation` and `sp_CalculateMemberPayment`), so any precision changes could affect financial calculations downstream.

**Risks:**
- Financial calculation precision must be validated end-to-end after migration.
- Composite index `IX_Prices_CropDate(CropTypeId, MarketDate)` translates directly but query plans should be compared.

---

### Table Complexity Summary

| Table | Schema | Complexity | Key Challenges | Effort |
|---|---|---|---|---|
| CropTypes | CropManagement | 🟢 Low | None | 1h |
| MemberAccounts | Members | 🟢 Low | None | 1h |
| FertilizerStock | Inventory | 🟡 Medium | MONEY type | 2h |
| CommodityPrices | Trading | 🟡 Medium | MONEY type, financial precision | 2h |
| Fields | CropManagement | 🔴 High | GEOGRAPHY → PostGIS | 4–6h |
| Harvests | CropManagement | 🔴 Critical | Computed column with UDF, trigger | 6–10h |

---

## 2. Stored Procedure Complexity

### 2.1 sp_CalculateOptimalRotation (`CropPlanning`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **High** |
| **Effort** | 6–8 hours |

**SQL Server Features Used:**

| Feature | SQL Server | PostgreSQL Equivalent |
|---|---|---|
| `SET NOCOUNT ON` | Suppresses row-count messages | Not needed (PostgreSQL doesn't send row counts by default) |
| `DECLARE` variables | `DECLARE @var TYPE` | `DECLARE var TYPE` (no `@` prefix) |
| `SELECT @var = col` | Variable assignment from query | `SELECT col INTO var FROM ...` |
| CTE (`WITH ... AS`) | Common Table Expression | Fully supported — syntax identical |
| `SELECT TOP 1 ... ORDER BY` | Limit results | `SELECT ... ORDER BY ... LIMIT 1` |
| Correlated subquery in JOIN | `MAX(MarketDate)` subquery | Identical syntax, but consider `LATERAL` join for performance |

**Conversion Challenges:**

1. **CTE with scoring algorithm:** The `RotationRules` CTE combines a crop rotation score with a market-price weight (`RotationScore * 0.6 + (CurrentPrice / 10) * 0.4`). The CTE itself is syntactically compatible with PostgreSQL, but:
   - The `CASE` expression uses `@LastCropId` (a session variable), which must be converted to a PL/pgSQL local variable.
   - The `TOP 1` syntax must be rewritten to `LIMIT 1`.
   - Implicit `MONEY` → `DECIMAL` arithmetic in `CurrentPrice / 10` may produce different rounding behavior.

2. **Cross-schema references:** The procedure reads from `CropManagement.Fields`, `CropManagement.CropTypes`, and `Trading.CommodityPrices`. Schema naming must be preserved or remapped.

3. **Variable assignment pattern:** SQL Server's `SELECT @var = col FROM table` must be rewritten as `SELECT col INTO var FROM table` in PL/pgSQL.

**Recommended PostgreSQL Approach:**
```sql
CREATE OR REPLACE FUNCTION crop_planning.calculate_optimal_rotation(
    p_field_id INT,
    p_current_year INT
)
RETURNS TABLE (
    crop_type_id INT,
    name VARCHAR,
    rotation_score INT,
    current_price NUMERIC,
    total_score NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_crop_id INT;
    v_soil_type VARCHAR(50);
BEGIN
    -- Convert to PL/pgSQL function returning result set
    ...
END;
$$;
```

---

### 2.2 sp_CalculateMemberPayment (`Settlement`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **Critical** |
| **Effort** | 8–12 hours |

**SQL Server Features Used:**

| Feature | SQL Server | PostgreSQL Equivalent |
|---|---|---|
| `OUTPUT` parameter | `@TotalPayment MONEY OUTPUT` | `OUT` parameter or function return value |
| `MONEY` arithmetic | Implicit `MONEY` math | `NUMERIC(19,4)` — verify rounding |
| `YEAR()` function | `YEAR(h.HarvestDate)` | `EXTRACT(YEAR FROM h.HarvestDate)` |
| `CAST(col AS DECIMAL)` | Grade string → decimal | `col::NUMERIC` or `CAST(col AS NUMERIC)` |
| `SELECT TOP 1 ... ORDER BY` | Most-yielded crop | `LIMIT 1` |
| Nested correlated subquery | Subquery in WHERE clause | Identical syntax supported |
| `RETURN 0` | Return status code | Not idiomatic in PL/pgSQL; use `RETURN` or function return type |

**Conversion Challenges:**

1. **OUTPUT parameters:** SQL Server's `@TotalPayment MONEY OUTPUT` is a by-reference output parameter. PostgreSQL handles this differently:
   - **Option A:** Convert to a function with `OUT` parameter: `CREATE FUNCTION ... (p_member_id INT, p_settlement_year INT, OUT p_total_payment NUMERIC)`.
   - **Option B:** Return the value directly from a function: `RETURNS NUMERIC`.

2. **Nested subqueries with MONEY arithmetic:** The final calculation `@TotalYield * cp.PricePerBushel * @QualityMultiplier` mixes `DECIMAL` and `MONEY` types. In SQL Server, `MONEY * DECIMAL` returns `MONEY`. In PostgreSQL, all values will be `NUMERIC`, and rounding behavior must be validated to ensure financial accuracy.

3. **Computed column reference:** `SUM(h.YieldBushels)` references the computed column. If `YieldBushels` is converted to a generated column, this works transparently. If moved to a trigger-populated column, ensure the trigger fires before this procedure reads the data.

4. **YEAR() function:** Every `YEAR(h.HarvestDate)` must be converted to `EXTRACT(YEAR FROM h.HarvestDate)::INT`.

5. **Business-critical calculation:** This procedure directly affects member payments — any rounding or precision difference is a financial error. Requires thorough regression testing with production data samples.

---

### Stored Procedure Complexity Summary

| Procedure | Complexity | Key Challenges | Effort |
|---|---|---|---|
| sp_CalculateOptimalRotation | 🔴 High | CTE + scoring, TOP→LIMIT, variable assignment | 6–8h |
| sp_CalculateMemberPayment | 🔴 Critical | OUTPUT params, MONEY arithmetic, nested subqueries, financial precision | 8–12h |

---

## 3. Function Migration Complexity

### 3.1 fn_CalculateYieldBushels (Scalar UDF)

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **Critical** |
| **Effort** | 4–6 hours |

**SQL Server Definition:**
```sql
CREATE FUNCTION dbo.fn_CalculateYieldBushels(@Quantity DECIMAL(12,2), @UnitType NVARCHAR(20))
RETURNS DECIMAL(12,2) AS BEGIN
    RETURN CASE @UnitType
        WHEN 'bushels' THEN @Quantity
        WHEN 'tonnes'  THEN @Quantity * 36.7437
        WHEN 'hundredweight' THEN @Quantity * 1.667
        WHEN 'kilograms' THEN @Quantity * 0.0367437
        ELSE @Quantity
    END;
END
```

**Why This Is Critical:**

This function is **not complex in itself** — it is a simple CASE expression. The criticality arises entirely from **how it is used**: it is referenced in the `PERSISTED` computed column `Harvests.YieldBushels`.

**PostgreSQL Constraints on Generated Columns:**
- `GENERATED ALWAYS AS ... STORED` columns in PostgreSQL require the expression to reference only the current row's columns and `IMMUTABLE` functions.
- A PL/pgSQL function can be marked `IMMUTABLE` if it always returns the same output for the same input (this function qualifies).
- **However**, PostgreSQL generated columns cannot reference user-defined functions in all versions — this limitation was relaxed in PostgreSQL 16+ but requires the function to be `IMMUTABLE`.

**Migration Options:**

| Option | Approach | Pros | Cons |
|---|---|---|---|
| A | Inline CASE in generated column | No function dependency; simplest | Duplicates logic if used elsewhere |
| B | Create `IMMUTABLE` function + generated column | Clean separation; reusable | Requires PG 16+; function must be deployed first |
| C | Trigger-based population | Works on all PG versions | Performance overhead; more complex |
| D | Application-layer calculation | Removes DB logic | Requires app changes; data consistency risk |

**Recommended Approach:** **Option A** (inline) for maximum compatibility, with the function also created as `IMMUTABLE` for use in stored procedure replacements:

```sql
-- Generated column with inlined logic
yield_bushels NUMERIC(12,2) GENERATED ALWAYS AS (
    CASE unit_type
        WHEN 'bushels' THEN quantity
        WHEN 'tonnes'  THEN quantity * 36.7437
        WHEN 'hundredweight' THEN quantity * 1.667
        WHEN 'kilograms' THEN quantity * 0.0367437
        ELSE quantity
    END
) STORED

-- Standalone function for use in queries/procedures
CREATE OR REPLACE FUNCTION calculate_yield_bushels(p_quantity NUMERIC, p_unit_type VARCHAR)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE STRICT
AS $$
    SELECT CASE p_unit_type
        WHEN 'bushels' THEN p_quantity
        WHEN 'tonnes'  THEN p_quantity * 36.7437
        WHEN 'hundredweight' THEN p_quantity * 1.667
        WHEN 'kilograms' THEN p_quantity * 0.0367437
        ELSE p_quantity
    END;
$$;
```

---

## 4. Trigger Migration Complexity

### 4.1 tr_AuditHarvestChanges

| Attribute | Rating |
|---|---|
| **Complexity** | 🔴 **Critical** |
| **Effort** | 8–12 hours |

**SQL Server Features Used:**

| Feature | SQL Server | PostgreSQL Equivalent | Difficulty |
|---|---|---|---|
| `AFTER INSERT, UPDATE, DELETE` | Single multi-event trigger | Separate trigger functions per event or combined with `TG_OP` | 🟡 Medium |
| `inserted` / `deleted` pseudo-tables | Implicit per-statement tables | `NEW` / `OLD` row-level variables (or transition tables with `REFERENCING`) | 🔴 High |
| `FULL OUTER JOIN inserted/deleted` | Handles all DML types in one pass | Requires `REFERENCING OLD TABLE AS ... NEW TABLE AS ...` (PG 10+) or per-row logic | 🔴 High |
| `FOR JSON AUTO` | JSON serialization of row | `row_to_json(OLD)` / `row_to_json(NEW)` or `to_jsonb()` | 🟡 Medium |
| `SUSER_SNAME()` | Current Windows/SQL login | `current_user` or `session_user` | 🟢 Low |
| `GETDATE()` | Current timestamp | `CURRENT_TIMESTAMP` or `clock_timestamp()` | 🟢 Low |

**Conversion Challenges:**

1. **Statement-level vs. Row-level Triggers:**
   SQL Server's `inserted` and `deleted` pseudo-tables contain **all affected rows** (statement-level semantics). PostgreSQL triggers are typically **row-level** (`FOR EACH ROW`), where `NEW` and `OLD` represent a single row. To replicate the `FULL OUTER JOIN` pattern:
   - **Option A (PG 10+):** Use statement-level trigger with transition tables:
     ```sql
     CREATE TRIGGER tr_audit_harvest_changes
     AFTER INSERT OR UPDATE OR DELETE ON crop_management.harvests
     REFERENCING OLD TABLE AS deleted NEW TABLE AS inserted
     FOR EACH STATEMENT
     EXECUTE FUNCTION audit_harvest_changes();
     ```
   - **Option B:** Use row-level trigger (simpler, slight performance difference for bulk operations):
     ```sql
     -- Fires once per row, using TG_OP to determine operation type
     IF TG_OP = 'INSERT' THEN ...
     ELSIF TG_OP = 'UPDATE' THEN ...
     ELSIF TG_OP = 'DELETE' THEN ...
     ```

2. **FOR JSON AUTO Replacement:**
   SQL Server's `FOR JSON AUTO` serializes query results as JSON. PostgreSQL equivalent:
   - `row_to_json(OLD)` for row-level triggers
   - `to_jsonb(OLD)` for JSONB output (recommended)
   - For statement-level with transition tables: `(SELECT jsonb_agg(to_jsonb(d)) FROM deleted d WHERE d.harvest_id = ...)`

3. **FULL OUTER JOIN on inserted/deleted:**
   This pattern handles INSERT (row in `inserted` only), UPDATE (row in both), and DELETE (row in `deleted` only) in a single query. In PostgreSQL row-level triggers, this is unnecessary because `TG_OP` identifies the operation. In statement-level triggers with transition tables, the FULL OUTER JOIN pattern can be preserved.

4. **Audit Table Dependency:**
   The trigger references `Audit.HarvestAuditLog`, which is not in the current schema extract. This table must be created in the target before the trigger can be deployed.

**Recommended PostgreSQL Approach:**
```sql
CREATE OR REPLACE FUNCTION audit_harvest_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (NEW.harvest_id, 'INSERT', current_user, CURRENT_TIMESTAMP, NULL, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (NEW.harvest_id, 'UPDATE', current_user, CURRENT_TIMESTAMP, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.harvest_audit_log (harvest_id, change_type, changed_by, change_date, old_value, new_value)
        VALUES (OLD.harvest_id, 'DELETE', current_user, CURRENT_TIMESTAMP, to_jsonb(OLD), NULL);
        RETURN OLD;
    END IF;
END;
$$;

CREATE TRIGGER tr_audit_harvest_changes
AFTER INSERT OR UPDATE OR DELETE ON crop_management.harvests
FOR EACH ROW EXECUTE FUNCTION audit_harvest_changes();
```

---

## 5. View Migration Assessment

### 5.1 vw_FieldProductivity (`CropManagement.vw_FieldProductivity`)

| Attribute | Rating |
|---|---|
| **Complexity** | 🟡 **Medium** |
| **Effort** | 2–3 hours |

**SQL Server Features Requiring Conversion:**

| Feature | SQL Server Syntax | PostgreSQL Syntax |
|---|---|---|
| String concatenation | `m.FirstName + ' ' + m.LastName` | `m.first_name \|\| ' ' \|\| m.last_name` |
| Column aliases | Same syntax | Same syntax |
| GROUP BY | Identical | Identical |
| JOINs | Identical | Identical |

**Conversion Notes:**
- The view references the computed column `h.YieldBushels` — if the computed column migration is successful, the view works transparently.
- String concatenation operator changes from `+` to `||`.
- Schema-qualified references must be updated if naming convention changes (e.g., `CropManagement` → `crop_management`).
- The aggregation `SUM(h.YieldBushels) / f.Acreage` performs division — ensure no division-by-zero when `Acreage = 0`. (This is an existing risk in the source, not introduced by migration.)

---

## 6. SQL Server → PostgreSQL Feature Mapping

| # | SQL Server Feature | PostgreSQL Equivalent | Scope of Impact | Notes |
|---|---|---|---|---|
| 1 | `INT IDENTITY(1,1)` | `SERIAL` (or `INT GENERATED ALWAYS AS IDENTITY`) | All 6 tables | `SERIAL` creates a sequence implicitly; `GENERATED ALWAYS AS IDENTITY` is SQL-standard |
| 2 | `MONEY` | `NUMERIC(19,4)` | FertilizerStock, CommodityPrices, sp_CalculateMemberPayment | PG has a `money` type but it is locale-dependent and **not recommended** for applications |
| 3 | `GEOGRAPHY` | `GEOMETRY(Geometry, 4326)` via PostGIS | Fields.GPSBoundary | Requires `CREATE EXTENSION postgis;` and SRID management |
| 4 | `NVARCHAR(n)` | `VARCHAR(n)` | All tables (20+ columns) | PostgreSQL `VARCHAR` is UTF-8 by default; no separate Unicode type needed |
| 5 | `DATETIME` | `TIMESTAMP` (or `TIMESTAMPTZ`) | All tables (CreatedDate, ModifiedDate) | Consider `TIMESTAMPTZ` for timezone awareness |
| 6 | `GETDATE()` | `CURRENT_TIMESTAMP` | All DEFAULT clauses | Drop-in replacement; `clock_timestamp()` if wall-clock time needed in triggers |
| 7 | `PERSISTED` computed column | `GENERATED ALWAYS AS (...) STORED` | Harvests.YieldBushels | Cannot reference mutable functions; see Section 3 |
| 8 | `SET NOCOUNT ON` | Not applicable | Both stored procedures | PostgreSQL does not send row-count messages by default |
| 9 | `SELECT TOP N` | `LIMIT N` | Both stored procedures | Syntax change at end of query |
| 10 | `YEAR(date)` | `EXTRACT(YEAR FROM date)` | sp_CalculateMemberPayment | Returns `double precision`; cast to `INT` if needed |
| 11 | `@variable` | PL/pgSQL `variable` (no prefix) | Both stored procedures | Variable declarations in `DECLARE` block |
| 12 | `SELECT @var = col` | `SELECT col INTO var` | Both stored procedures | PL/pgSQL assignment pattern |
| 13 | `OUTPUT` parameter | `OUT` parameter or function return | sp_CalculateMemberPayment | Idiomatic PG uses function return values |
| 14 | `SUSER_SNAME()` | `current_user` / `session_user` | tr_AuditHarvestChanges | `session_user` is closest equivalent |
| 15 | `FOR JSON AUTO` | `to_jsonb(row)` / `row_to_json()` | tr_AuditHarvestChanges | Native JSON support in PG |
| 16 | `inserted` / `deleted` tables | `NEW` / `OLD` (row-level) or `REFERENCING` (statement-level) | tr_AuditHarvestChanges | Fundamental trigger model difference |
| 17 | `FULL OUTER JOIN` on trigger tables | `TG_OP` conditional logic | tr_AuditHarvestChanges | Row-level triggers eliminate the need for the JOIN pattern |
| 18 | `+` (string concat) | `\|\|` | vw_FieldProductivity | Operator change |
| 19 | Schema separation (`dbo`, `CropManagement`, etc.) | PostgreSQL schemas | All objects | Map 1:1; create schemas with `CREATE SCHEMA` |
| 20 | `RETURN 0` (procedure status) | Not idiomatic | sp_CalculateMemberPayment | PG functions use `RETURN` for value; no status code convention |

---

## 7. Identified Blockers and Risks

### 🚫 Blockers (Must Resolve Before Migration)

| # | Blocker | Affected Object(s) | Severity | Resolution |
|---|---|---|---|---|
| B1 | **Computed column with UDF reference** | Harvests.YieldBushels, fn_CalculateYieldBushels | 🔴 Critical | Inline CASE expression in `GENERATED ALWAYS AS` column or create `IMMUTABLE` function (PG 16+ required) |
| B2 | **PostGIS extension provisioning** | Fields.GPSBoundary | 🔴 Critical | Enable PostGIS on Azure PostgreSQL via `azure.extensions` server parameter; test spatial data fidelity |
| B3 | **Audit table not in schema extract** | tr_AuditHarvestChanges → Audit.HarvestAuditLog | 🟡 High | Obtain and migrate `Audit.HarvestAuditLog` DDL before trigger deployment |

### ⚠️ Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | **Financial precision divergence** — `MONEY` arithmetic rounds differently than `NUMERIC` | Medium | High | Run parallel calculations on production data; compare results to 4 decimal places |
| R2 | **Spatial coordinate ordering** — SQL Server GEOGRAPHY uses lat/lng; PostGIS GEOMETRY uses lng/lat | High | High | Write a validation script comparing source/target spatial values; test with known GPS coordinates |
| R3 | **Trigger JSON format difference** — `FOR JSON AUTO` output shape differs from `to_jsonb()` | Medium | Medium | If downstream consumers parse audit JSON, update parsers; if only for human review, acceptable |
| R4 | **Sequence value gaps** — `SERIAL` sequences may have gaps after failed inserts | Low | Low | Acceptable; educate team that gaps are normal in PostgreSQL |
| R5 | **YEAR() precision** — `EXTRACT(YEAR FROM ...)` returns `double precision`, not `INT` | Low | Medium | Explicitly cast: `EXTRACT(YEAR FROM date)::INT` |
| R6 | **Concurrent trigger execution order** — PG fires triggers in alphabetical order by name | Low | Low | Only one trigger on Harvests currently; document for future trigger additions |
| R7 | **Generated column limitations** — Cannot UPDATE or INSERT into generated columns | Low | Medium | Ensure ETL/migration scripts exclude `YieldBushels` from INSERT column lists |

---

## 8. Effort Estimation Per Object

| Object | Type | Complexity | Development | Testing | Documentation | **Total** |
|---|---|---|---|---|---|---|
| CropTypes | Table | 🟢 Low | 0.5h | 0.5h | — | **1h** |
| MemberAccounts | Table | 🟢 Low | 0.5h | 0.5h | — | **1h** |
| FertilizerStock | Table | 🟡 Medium | 1h | 0.5h | 0.5h | **2h** |
| CommodityPrices | Table | 🟡 Medium | 1h | 0.5h | 0.5h | **2h** |
| Fields | Table | 🔴 High | 2h | 2h | 1h | **5h** |
| Harvests | Table | 🔴 Critical | 3h | 4h | 1h | **8h** |
| fn_CalculateYieldBushels | Function | 🔴 Critical | 2h | 2h | 1h | **5h** |
| sp_CalculateOptimalRotation | Procedure | 🔴 High | 3h | 3h | 1h | **7h** |
| sp_CalculateMemberPayment | Procedure | 🔴 Critical | 4h | 5h | 1h | **10h** |
| tr_AuditHarvestChanges | Trigger | 🔴 Critical | 4h | 4h | 2h | **10h** |
| vw_FieldProductivity | View | 🟡 Medium | 1h | 1h | 0.5h | **2.5h** |
| | | | | | **Grand Total** | **53.5h** |

**Estimated Total Effort:** ~53.5 hours (approximately 7 developer-days at 8h/day)

**Effort Breakdown by Phase:**
- Development: ~22h (41%)
- Testing & Validation: ~23.5h (44%)
- Documentation: ~8h (15%)

---

## 9. Recommended Migration Order

The migration order is driven by foreign-key dependencies, computed-column dependencies, and trigger dependencies.

```
Phase 1 — Foundation (No Dependencies)
  ├── 1.1 Create PostgreSQL schemas: crop_management, members, inventory, trading, audit, crop_planning, settlement
  ├── 1.2 Enable PostGIS extension
  └── 1.3 Create fn_CalculateYieldBushels as IMMUTABLE function

Phase 2 — Independent Tables (No FK Dependencies)
  ├── 2.1 Members.MemberAccounts  →  members.member_accounts
  ├── 2.2 CropManagement.CropTypes  →  crop_management.crop_types
  └── 2.3 Inventory.FertilizerStock  →  inventory.fertilizer_stock

Phase 3 — Dependent Tables (FK on Phase 2 Tables)
  ├── 3.1 Trading.CommodityPrices  →  trading.commodity_prices  (FK → crop_types)
  └── 3.2 CropManagement.Fields  →  crop_management.fields  (FK → member_accounts, crop_types)

Phase 4 — Complex Tables (FK + Computed Columns)
  └── 4.1 CropManagement.Harvests  →  crop_management.harvests  (FK → fields, crop_types; generated column)

Phase 5 — Audit Infrastructure
  ├── 5.1 Create audit.harvest_audit_log table
  └── 5.2 Deploy tr_AuditHarvestChanges trigger

Phase 6 — Views
  └── 6.1 CropManagement.vw_FieldProductivity  →  crop_management.vw_field_productivity

Phase 7 — Stored Procedures / Functions
  ├── 7.1 sp_CalculateOptimalRotation  →  crop_planning.calculate_optimal_rotation()
  └── 7.2 sp_CalculateMemberPayment  →  settlement.calculate_member_payment()

Phase 8 — Validation & Cutover
  ├── 8.1 Row-count validation across all tables
  ├── 8.2 Financial precision regression tests (sp_CalculateMemberPayment)
  ├── 8.3 Computed column value comparison (YieldBushels)
  ├── 8.4 Spatial data fidelity checks (GPSBoundary)
  └── 8.5 Audit trigger behavior verification
```

**Dependency Graph:**

```
MemberAccounts ──┐
                 ├──→ Fields ──────→ Harvests ──→ tr_AuditHarvestChanges
CropTypes ───────┤                      │               │
                 ├──→ CommodityPrices   │               └──→ Audit.HarvestAuditLog
                 │                      │
fn_CalculateYieldBushels ───────────────┘
                                        │
                               vw_FieldProductivity
                                        │
                       ┌────────────────┴────────────────┐
           sp_CalculateOptimalRotation    sp_CalculateMemberPayment
```

---

## 10. Risk Mitigation Strategies

### 10.1 Financial Precision (MONEY → NUMERIC)

| Strategy | Action |
|---|---|
| **Parallel execution** | Run `sp_CalculateMemberPayment` on both source and target with identical inputs for 100+ member/year combinations |
| **Tolerance threshold** | Define acceptable variance (recommend: ±$0.01 per transaction) |
| **Regression dataset** | Extract 500 historical settlement records as golden dataset for automated comparison |
| **Rounding audit** | Log all intermediate calculation values during testing to identify divergence point |

### 10.2 Computed Column with UDF (YieldBushels)

| Strategy | Action |
|---|---|
| **Dual approach** | Create both the inlined generated column AND the standalone `IMMUTABLE` function |
| **Value comparison** | After data migration, run `SELECT COUNT(*) FROM harvests WHERE yield_bushels != calculate_yield_bushels(quantity, unit_type)` — expect 0 |
| **ETL guard** | Ensure migration scripts use `INSERT INTO ... (field_id, crop_type_id, ..., quantity, unit_type)` and **omit** `yield_bushels` |
| **Rollback plan** | If generated column fails, fall back to trigger-based population |

### 10.3 Spatial Data (GEOGRAPHY → PostGIS)

| Strategy | Action |
|---|---|
| **Coordinate validation** | Export 10 known field boundaries from SQL Server; compare with PostGIS output using `ST_AsText()` |
| **SRID enforcement** | Enforce SRID 4326 on all imported geometries: `ALTER TABLE ... ADD CONSTRAINT enforce_srid CHECK (ST_SRID(gps_boundary) = 4326)` |
| **Spatial index** | Create GiST index: `CREATE INDEX ix_fields_boundary ON crop_management.fields USING GIST(gps_boundary)` |
| **Null handling** | GPSBoundary is nullable — ensure NULL values migrate correctly (no empty-geometry substitution) |

### 10.4 Trigger JSON Serialization

| Strategy | Action |
|---|---|
| **Output comparison** | Capture `FOR JSON AUTO` output from SQL Server for 10 test rows; compare with `to_jsonb()` output from PostgreSQL |
| **Schema documentation** | Document expected JSON structure for downstream consumers (USDA reporting) |
| **Format adapter** | If JSON format must match exactly, create a wrapper function that formats `to_jsonb()` output to match `FOR JSON AUTO` structure |
| **Regulatory review** | Confirm with compliance team that JSONB format is acceptable for USDA audit trail |

### 10.5 General Migration Risk Mitigation

| Strategy | Action |
|---|---|
| **Blue/green deployment** | Maintain SQL Server in read-only mode during cutover; keep as fallback for 30 days |
| **Automated comparison** | Build CI pipeline that runs validation queries against both databases nightly during parallel-run period |
| **Feature flags** | Application code should support switching between SQL Server and PostgreSQL connection strings |
| **Incremental migration** | Migrate and validate one schema at a time (Members → CropManagement → Inventory → Trading → Audit) |
| **Runbook** | Document rollback procedures for each phase with estimated rollback time |

---

## Appendix: Object Inventory

| # | Object Name | Type | Source Schema | Target Schema | Complexity | Migration Phase |
|---|---|---|---|---|---|---|
| 1 | CropTypes | Table | CropManagement | crop_management | 🟢 Low | 2 |
| 2 | Fields | Table | CropManagement | crop_management | 🔴 High | 3 |
| 3 | Harvests | Table | CropManagement | crop_management | 🔴 Critical | 4 |
| 4 | MemberAccounts | Table | Members | members | 🟢 Low | 2 |
| 5 | FertilizerStock | Table | Inventory | inventory | 🟡 Medium | 2 |
| 6 | CommodityPrices | Table | Trading | trading | 🟡 Medium | 3 |
| 7 | fn_CalculateYieldBushels | Scalar Function | dbo | public | 🔴 Critical | 1 |
| 8 | sp_CalculateOptimalRotation | Stored Procedure | CropPlanning | crop_planning | 🔴 High | 7 |
| 9 | sp_CalculateMemberPayment | Stored Procedure | Settlement | settlement | 🔴 Critical | 7 |
| 10 | tr_AuditHarvestChanges | Trigger | CropManagement | crop_management | 🔴 Critical | 5 |
| 11 | vw_FieldProductivity | View | CropManagement | crop_management | 🟡 Medium | 6 |
