# Step 01 — GreenHarvest Agricultural Co-op Legacy Database Analysis

> **Source System:** SQL Server 2019 (Developer Edition via Docker)
> **Database Name:** GreenHarvest
> **Analysis Date:** 2026-04-16
> **Purpose:** Comprehensive inventory and analysis of the legacy SQL Server database to inform migration to Azure Database for PostgreSQL.

---

## Table of Contents

1. [Database Object Inventory](#1-database-object-inventory)
2. [Table Definitions & Column Details](#2-table-definitions--column-details)
3. [Foreign Key Relationships & Referential Integrity Map](#3-foreign-key-relationships--referential-integrity-map)
4. [Stored Procedures & Business Rule Extraction](#4-stored-procedures--business-rule-extraction)
5. [Scalar Function — fn_CalculateYieldBushels](#5-scalar-function--fn_calculateyieldbushels)
6. [Trigger — tr_AuditHarvestChanges](#6-trigger--tr_auditharvestchanges)
7. [View — vw_FieldProductivity](#7-view--vw_fieldproductivity)
8. [Data Patterns from Seed & Sample Data](#8-data-patterns-from-seed--sample-data)
9. [SQL Server–Specific Features & Migration Considerations](#9-sql-serverspecific-features--migration-considerations)

---

## 1. Database Object Inventory

### Schemas (4)

| Schema | Purpose |
|---|---|
| `CropManagement` | Core agricultural operations — crops, fields, harvests |
| `Members` | Co-op member account management |
| `Inventory` | Agricultural input stock tracking (fertilizers, etc.) |
| `Trading` | Market commodity prices and settlement |

Additionally referenced (in trigger): `Audit` schema (for `HarvestAuditLog`).

### Complete Object Summary

| Object Type | Count | Objects |
|---|---|---|
| **Tables** | 6 | `CropManagement.CropTypes`, `CropManagement.Fields`, `CropManagement.Harvests`, `Members.MemberAccounts`, `Inventory.FertilizerStock`, `Trading.CommodityPrices` |
| **Stored Procedures** | 2 | `CropPlanning.sp_CalculateOptimalRotation`, `Settlement.sp_CalculateMemberPayment` |
| **Scalar Functions** | 1 | `dbo.fn_CalculateYieldBushels` |
| **Triggers** | 1 | `tr_AuditHarvestChanges` (on `CropManagement.Harvests`) |
| **Views** | 1 | `CropManagement.vw_FieldProductivity` |
| **Indexes** | 9 | See per-table detail below |
| **Foreign Keys** | 5 | See relationship map below |

### File Organization

```
Schema/
├── Tables/
│   ├── CropManagement/
│   │   ├── CropTypes.sql
│   │   ├── Fields.sql
│   │   └── Harvests.sql
│   ├── Members/
│   │   └── MemberAccounts.sql
│   ├── Inventory/
│   │   └── FertilizerStock.sql
│   └── Trading/
│       └── CommodityPrices.sql
├── StoredProcedures/
│   ├── CropPlanning/
│   │   └── sp_CalculateOptimalRotation.sql
│   └── Settlement/
│       └── sp_CalculateMemberPayment.sql
├── Functions/
│   └── Scalar/
│       └── fn_CalculateYieldBushels.sql
├── Triggers/
│   └── tr_AuditHarvestChanges.sql
└── Views/
    └── vw_FieldProductivity.sql
```

---

## 2. Table Definitions & Column Details

### 2.1 `CropManagement.CropTypes`

Reference data for crop varieties grown by the co-op.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `CropTypeId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | Auto-increment surrogate key |
| `Name` | `NVARCHAR(100)` | NO | — | — | Crop name (e.g., Corn, Wheat) |
| `GrowingSeason` | `NVARCHAR(50)` | NO | — | — | Season descriptor (e.g., "Spring/Summer") |
| `DaysToMaturity` | `INT` | NO | — | — | Growth cycle in days |
| `MinTemperature` | `DECIMAL(5,2)` | YES | — | — | Minimum viable temperature (°C/°F) |
| `MaxTemperature` | `DECIMAL(5,2)` | YES | — | — | Maximum viable temperature |
| `WaterRequirement` | `NVARCHAR(20)` | YES | — | — | Categorical: Low / Medium / High |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | Row creation timestamp |
| `ModifiedDate` | `DATETIME` | YES | `GETDATE()` | — | Last modification timestamp |

**Indexes:**
- `IX_CropTypes_Name` on `(Name)`
- `IX_CropTypes_Season` on `(GrowingSeason)`

---

### 2.2 `Members.MemberAccounts`

Co-op member contact and status information.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `MemberId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | Auto-increment surrogate key |
| `MemberNumber` | `NVARCHAR(20)` | NO | — | **UNIQUE** | Business key (e.g., "M001") |
| `FirstName` | `NVARCHAR(50)` | NO | — | — | |
| `LastName` | `NVARCHAR(50)` | NO | — | — | |
| `Email` | `NVARCHAR(100)` | YES | — | — | |
| `PhoneNumber` | `NVARCHAR(20)` | YES | — | — | |
| `Address` | `NVARCHAR(200)` | YES | — | — | |
| `City` | `NVARCHAR(50)` | YES | — | — | |
| `State` | `NVARCHAR(2)` | YES | — | — | Two-letter US state code |
| `ZipCode` | `NVARCHAR(10)` | YES | — | — | Supports ZIP+4 format |
| `MembershipDate` | `DATE` | NO | — | — | Date the member joined |
| `Status` | `NVARCHAR(20)` | YES | `'Active'` | — | Membership status |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | |
| `ModifiedDate` | `DATETIME` | YES | `GETDATE()` | — | |

**Indexes:**
- `IX_Members_Number` on `(MemberNumber)` — supports unique-lookup by business key
- `IX_Members_Name` on `(LastName, FirstName)` — composite for name searches

---

### 2.3 `CropManagement.Fields`

Physical fields/parcels owned or managed by co-op members.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `FieldId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | |
| `MemberId` | `INT` | NO | — | **FK → Members.MemberAccounts(MemberId)** | Owner/manager |
| `FieldName` | `NVARCHAR(100)` | NO | — | — | Human-readable field name |
| `Acreage` | `DECIMAL(10,2)` | NO | — | — | Field size in acres |
| `SoilType` | `NVARCHAR(50)` | YES | — | — | Soil classification |
| `IrrigationType` | `NVARCHAR(50)` | YES | — | — | Irrigation method |
| `GPSBoundary` | `GEOGRAPHY` | YES | — | — | ⚠️ **SQL Server spatial type** — field perimeter |
| `CurrentCropId` | `INT` | YES | — | **FK → CropManagement.CropTypes(CropTypeId)** | Currently planted crop |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | |
| `ModifiedDate` | `DATETIME` | YES | `GETDATE()` | — | |

**Indexes:**
- `IX_Fields_Member` on `(MemberId)` — FK lookup
- `IX_Fields_CurrentCrop` on `(CurrentCropId)` — FK lookup

**Foreign Keys:**
- `FK_Fields_Member` → `Members.MemberAccounts(MemberId)`
- `FK_Fields_CurrentCrop` → `CropManagement.CropTypes(CropTypeId)`

---

### 2.4 `CropManagement.Harvests`

Records of crop harvests — central transactional table.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `HarvestId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | |
| `FieldId` | `INT` | NO | — | **FK → CropManagement.Fields(FieldId)** | Source field |
| `CropTypeId` | `INT` | NO | — | **FK → CropManagement.CropTypes(CropTypeId)** | Harvested crop type |
| `HarvestDate` | `DATE` | NO | — | — | |
| `YieldBushels` | *Computed* | — | — | `PERSISTED` | ⚠️ `AS (dbo.fn_CalculateYieldBushels(Quantity, UnitType))` |
| `Quantity` | `DECIMAL(12,2)` | NO | — | — | Raw harvest quantity |
| `UnitType` | `NVARCHAR(20)` | NO | — | — | Unit of measure for Quantity |
| `MoistureContent` | `DECIMAL(5,2)` | YES | — | — | Moisture % at harvest |
| `GradeCode` | `NVARCHAR(10)` | YES | — | — | Quality grade (cast to numeric in SP) |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | |

**Indexes:**
- `IX_Harvests_Field` on `(FieldId)` — FK lookup
- `IX_Harvests_Date` on `(HarvestDate)` — temporal queries

**Foreign Keys:**
- `FK_Harvests_Field` → `CropManagement.Fields(FieldId)`
- `FK_Harvests_CropType` → `CropManagement.CropTypes(CropTypeId)`

**Key Detail — Computed Column:**
`YieldBushels` is a **PERSISTED computed column** that calls the scalar UDF `dbo.fn_CalculateYieldBushels(Quantity, UnitType)`. It is physically stored on disk and updated automatically when `Quantity` or `UnitType` change. This is a significant migration challenge (see §9).

---

### 2.5 `Inventory.FertilizerStock`

Tracks fertilizer inventory levels at the co-op.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `StockId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | |
| `ProductName` | `NVARCHAR(100)` | NO | — | — | |
| `ManufacturerName` | `NVARCHAR(100)` | YES | — | — | |
| `QuantityOnHand` | `DECIMAL(12,2)` | NO | — | — | Current stock level |
| `Unit` | `NVARCHAR(20)` | NO | — | — | Unit of measure |
| `CostPerUnit` | `MONEY` | NO | — | — | ⚠️ **SQL Server MONEY type** — 4 decimal places |
| `ReorderLevel` | `DECIMAL(12,2)` | YES | — | — | Auto-reorder threshold |
| `LastRestockDate` | `DATE` | YES | — | — | |
| `ExpirationDate` | `DATE` | YES | — | — | Product shelf life |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | |

**Indexes:**
- `IX_Fertilizer_Product` on `(ProductName)`

**Standalone Table:** No foreign keys — independent inventory tracking.

---

### 2.6 `Trading.CommodityPrices`

Market price history for crop commodities.

| Column | Data Type | Nullable | Default | Constraints | Notes |
|---|---|---|---|---|---|
| `PriceId` | `INT` | NO | — | **PK**, `IDENTITY(1,1)` | |
| `CropTypeId` | `INT` | NO | — | **FK → CropManagement.CropTypes(CropTypeId)** | |
| `MarketDate` | `DATE` | NO | — | — | Price observation date |
| `PricePerBushel` | `MONEY` | NO | — | — | ⚠️ **SQL Server MONEY type** |
| `MarketName` | `NVARCHAR(100)` | YES | — | — | Source market / exchange |
| `CreatedDate` | `DATETIME` | YES | `GETDATE()` | — | |

**Indexes:**
- `IX_Prices_CropDate` on `(CropTypeId, MarketDate)` — composite for price lookups by crop and date

**Foreign Keys:**
- `FK_Prices_CropType` → `CropManagement.CropTypes(CropTypeId)`

---

## 3. Foreign Key Relationships & Referential Integrity Map

### Entity Relationship Diagram (Text)

```
Members.MemberAccounts (MemberId PK)
    │
    │  1:N  FK_Fields_Member
    ▼
CropManagement.Fields (FieldId PK)
    │                         │
    │  1:N  FK_Harvests_Field │  N:1  FK_Fields_CurrentCrop
    ▼                         ▼
CropManagement.Harvests    CropManagement.CropTypes (CropTypeId PK)
(HarvestId PK)                ▲          ▲
    │                         │          │
    └── N:1  FK_Harvests_CropType        │
                                         │
Trading.CommodityPrices ─── N:1  FK_Prices_CropType
(PriceId PK)

Inventory.FertilizerStock (StockId PK) ── standalone, no FKs
```

### Foreign Key Inventory

| FK Constraint Name | Source Table | Source Column | Target Table | Target Column | On Delete | On Update |
|---|---|---|---|---|---|---|
| `FK_Fields_Member` | `CropManagement.Fields` | `MemberId` | `Members.MemberAccounts` | `MemberId` | NO ACTION (default) | NO ACTION |
| `FK_Fields_CurrentCrop` | `CropManagement.Fields` | `CurrentCropId` | `CropManagement.CropTypes` | `CropTypeId` | NO ACTION | NO ACTION |
| `FK_Harvests_Field` | `CropManagement.Harvests` | `FieldId` | `CropManagement.Fields` | `FieldId` | NO ACTION | NO ACTION |
| `FK_Harvests_CropType` | `CropManagement.Harvests` | `CropTypeId` | `CropManagement.CropTypes` | `CropTypeId` | NO ACTION | NO ACTION |
| `FK_Prices_CropType` | `Trading.CommodityPrices` | `CropTypeId` | `CropManagement.CropTypes` | `CropTypeId` | NO ACTION | NO ACTION |

### Dependency Order (for inserts / migration)

1. `CropManagement.CropTypes` — no dependencies
2. `Members.MemberAccounts` — no dependencies
3. `Inventory.FertilizerStock` — no dependencies
4. `CropManagement.Fields` — depends on `MemberAccounts`, `CropTypes`
5. `CropManagement.Harvests` — depends on `Fields`, `CropTypes`
6. `Trading.CommodityPrices` — depends on `CropTypes`

### Referential Integrity Notes

- All foreign keys use the default `NO ACTION` for both `ON DELETE` and `ON UPDATE` — meaning deletions/updates of referenced rows will fail if child rows exist.
- `CropManagement.CropTypes` is the most heavily referenced table (3 incoming FKs). It serves as the central reference for agricultural operations and market pricing.
- `CurrentCropId` in `Fields` is **nullable**, allowing fields with no currently planted crop.

---

## 4. Stored Procedures & Business Rule Extraction

### 4.1 `CropPlanning.sp_CalculateOptimalRotation`

**Location:** `Schema/StoredProcedures/CropPlanning/sp_CalculateOptimalRotation.sql`

**Purpose:** Recommends the best next crop to plant in a given field based on agronomic and economic factors.

**Parameters:**

| Parameter | Type | Direction | Description |
|---|---|---|---|
| `@FieldId` | `INT` | IN | Target field for rotation recommendation |
| `@CurrentYear` | `INT` | IN | Planning year (not directly used in current logic) |

**Business Rules Extracted:**

1. **Rotation Scoring Algorithm:**
   - The procedure assigns a `RotationScore` based on the field's previous crop:
     - After Corn (`CropTypeId = 1`): Score = **10** → Strong preference for switching (prefer soybeans — nitrogen fixation)
     - After Soybeans (`CropTypeId = 2`): Score = **5** → Any crop is acceptable
     - After any other crop: Score = **7** → Moderate preference to rotate
   - Excludes the current crop from candidates (`WHERE ct.CropTypeId != @LastCropId`)

2. **Market Price Integration:**
   - Fetches the **latest available price** per crop type from `Trading.CommodityPrices`
   - Uses a correlated subquery: `MAX(MarketDate)` per `CropTypeId`

3. **Composite Score Formula:**
   ```
   TotalScore = (RotationScore × 0.6) + ((PricePerBushel / 10) × 0.4)
   ```
   - **60% weight** on agronomic rotation benefit
   - **40% weight** on economic (market price) incentive
   - Returns `TOP 1` result ordered by `TotalScore DESC`

4. **Cross-Schema Dependencies:**
   - Reads from `CropManagement.Fields` (field soil type and current crop)
   - Reads from `CropManagement.CropTypes` (all available crops)
   - Reads from `Trading.CommodityPrices` (latest market prices)

**SQL Server–Specific Constructs:**
- `SET NOCOUNT ON`
- CTE (`WITH RotationRules AS`)
- `TOP 1 ... ORDER BY`
- Local variable declarations and assignment via `SELECT ... INTO @variable`

---

### 4.2 `Settlement.sp_CalculateMemberPayment`

**Location:** `Schema/StoredProcedures/Settlement/sp_CalculateMemberPayment.sql`

**Purpose:** Calculates the annual settlement payment owed to a co-op member based on their harvest yield and quality.

**Parameters:**

| Parameter | Type | Direction | Description |
|---|---|---|---|
| `@MemberId` | `INT` | IN | Member to calculate payment for |
| `@SettlementYear` | `INT` | IN | Year for settlement period |
| `@TotalPayment` | `MONEY` | **OUTPUT** | Calculated payment amount |

**Business Rules Extracted:**

1. **Total Yield Aggregation:**
   - Sums `YieldBushels` (the **persisted computed column**) across all harvests for the member's fields in the settlement year
   - Joins: `Harvests → Fields` (on `FieldId`), filtered by `Fields.MemberId` and `YEAR(HarvestDate)`

2. **Quality Grade Multiplier Tiers:**

   | Average Grade | Multiplier | Bonus |
   |---|---|---|
   | ≥ 90 | **1.150** | +15% premium |
   | ≥ 80 | **1.100** | +10% premium |
   | ≥ 70 | **1.050** | +5% premium |
   | < 70 | **1.000** | No bonus |

   - `GradeCode` (NVARCHAR) is **cast to DECIMAL** for averaging — assumes numeric grade codes
   - The average is computed across all harvests for the member in that year

3. **Payment Calculation:**
   ```
   TotalPayment = TotalYield × PricePerBushel × QualityMultiplier
   ```
   - Uses the **most recent market price** in the settlement year
   - Price is fetched for the member's **dominant crop** (highest total yield by `CropTypeId`)

4. **Key Assumptions / Risks:**
   - Uses `YEAR(h.HarvestDate)` — **non-sargable** filter on indexed `HarvestDate` column
   - `GradeCode` cast to `DECIMAL` will fail if non-numeric values are stored
   - Payment is based on the **single dominant crop's price** — harvests of other crop types are still counted in yield but priced at the dominant crop's rate

**SQL Server–Specific Constructs:**
- `MONEY OUTPUT` parameter
- `SET NOCOUNT ON`
- `RETURN 0` (explicit return code)
- `TOP 1 ... ORDER BY ... DESC`
- `YEAR()` function (T-SQL)

---

## 5. Scalar Function — fn_CalculateYieldBushels

**Location:** `Schema/Functions/Scalar/fn_CalculateYieldBushels.sql`
**Schema:** `dbo` (default schema — not in a domain schema)

**Purpose:** Converts harvest quantities from various units of measure into a standardized **bushels** measurement.

**Signature:**
```sql
dbo.fn_CalculateYieldBushels(@Quantity DECIMAL(12,2), @UnitType NVARCHAR(20)) → DECIMAL(12,2)
```

### Conversion Factor Table

| Input `@UnitType` | Conversion Factor | Formula | Notes |
|---|---|---|---|
| `'bushels'` | 1.0 (identity) | `@Quantity` | Already in bushels |
| `'tonnes'` | **36.7437** | `@Quantity × 36.7437` | Based on wheat standard (1 metric tonne ≈ 36.74 bushels of wheat at 60 lb/bushel) |
| `'hundredweight'` | **1.667** | `@Quantity × 1.667` | 1 cwt ≈ 1.667 bushels |
| `'kilograms'` | **0.0367437** | `@Quantity × 0.0367437` | Consistent with tonnes factor (÷ 1000) |
| *any other value* | 1.0 (default) | `@Quantity` | Falls through to default — silently treats unknown units as bushels |

### Key Observations

- **Single crop standard:** The conversion factors are based on **wheat** (60 lb/bushel). Different crops have different bushel weights (e.g., corn = 56 lb, soybeans = 60 lb, barley = 48 lb). The spec mentions "different conversion factors per crop type" but the current implementation uses a **single fixed factor**.
- **Used as PERSISTED computed column:** Called by `CropManagement.Harvests.YieldBushels`. Because it is PERSISTED, the result is physically stored and updated on row changes.
- **Schema placement:** Lives in `dbo`, not `CropManagement` — likely for the computed column reference to work without schema qualification issues.
- **Deterministic:** The function is deterministic (same inputs always produce same output), which is required for PERSISTED computed columns in SQL Server.

---

## 6. Trigger — tr_AuditHarvestChanges

**Location:** `Schema/Triggers/tr_AuditHarvestChanges.sql`
**Attached To:** `CropManagement.Harvests`

### Trigger Configuration

| Property | Value |
|---|---|
| **Timing** | `AFTER` |
| **Events** | `INSERT`, `UPDATE`, `DELETE` |
| **Scope** | All rows affected by the DML statement |

### Behavior

The trigger logs every change to the `Harvests` table into `Audit.HarvestAuditLog` for **regulatory compliance** (referenced as USDA reporting in the spec).

**Logic Flow:**

1. Checks `IF EXISTS (SELECT * FROM inserted)` — fires for INSERT and UPDATE operations (note: DELETE-only operations where `inserted` is empty may not be captured by this guard)
2. Performs a `FULL OUTER JOIN` between `inserted` and `deleted` pseudo-tables on `HarvestId`
3. Determines the `ChangeType`:
   - `inserted` row exists, `deleted` row does not → `'INSERT'`
   - Both exist → `'UPDATE'`
   - Only `deleted` exists → `'DELETE'` (but see note about the `IF EXISTS` guard)
4. Captures the **before state** (`OldValue`) and **after state** (`NewValue`) as **JSON** using `FOR JSON AUTO`

### Audit Log Target Table Structure

**`Audit.HarvestAuditLog`** (inferred from INSERT statement):

| Column | Inferred Type | Source |
|---|---|---|
| `HarvestId` | `INT` | `COALESCE(i.HarvestId, d.HarvestId)` |
| `ChangeType` | `NVARCHAR(...)` | `'INSERT'` / `'UPDATE'` / `'DELETE'` |
| `ChangedBy` | `NVARCHAR(...)` | `SUSER_SNAME()` — SQL Server login name |
| `ChangeDate` | `DATETIME` | `GETDATE()` |
| `OldValue` | `NVARCHAR(MAX)` | Deleted row serialized as JSON via `FOR JSON AUTO` |
| `NewValue` | `NVARCHAR(MAX)` | Inserted row serialized as JSON via `FOR JSON AUTO` |

### SQL Server–Specific Constructs

- **`SUSER_SNAME()`** — Returns the Windows/SQL login name of the current session. No direct PostgreSQL equivalent; must be replaced with `current_user` or `session_user`.
- **`FOR JSON AUTO`** — T-SQL clause that serializes query results as JSON. PostgreSQL equivalent: `row_to_json()` or `to_jsonb()`.
- **`inserted` / `deleted` pseudo-tables** — SQL Server trigger mechanism. PostgreSQL uses `NEW` / `OLD` records (row-level) or transition tables (`REFERENCING NEW TABLE AS ...`).

### Potential Issue

The `IF EXISTS (SELECT * FROM inserted)` guard means that pure `DELETE` operations (where no rows appear in `inserted`) will **not** enter the logging block. This could be a bug — DELETE changes would be silently unaudited.

---

## 7. View — vw_FieldProductivity

**Location:** `Schema/Views/vw_FieldProductivity.sql`
**Schema:** `CropManagement`

### Definition

```sql
CREATE VIEW CropManagement.vw_FieldProductivity AS
SELECT
    f.FieldId,
    f.FieldName,
    m.MemberNumber,
    m.FirstName + ' ' + m.LastName AS MemberName,
    f.Acreage,
    ct.Name AS CurrentCrop,
    SUM(h.YieldBushels) AS TotalYield,
    SUM(h.YieldBushels) / f.Acreage AS YieldPerAcre,
    COUNT(h.HarvestId) AS HarvestCount,
    MAX(h.HarvestDate) AS LastHarvestDate
FROM CropManagement.Fields f
INNER JOIN Members.MemberAccounts m ON f.MemberId = m.MemberId
LEFT JOIN CropManagement.CropTypes ct ON f.CurrentCropId = ct.CropTypeId
LEFT JOIN CropManagement.Harvests h ON f.FieldId = h.FieldId
GROUP BY f.FieldId, f.FieldName, m.MemberNumber, m.FirstName,
         m.LastName, f.Acreage, ct.Name;
```

### Join Map

```
Fields ──INNER JOIN──▶ MemberAccounts   (every field MUST have a member)
  │
  ├──LEFT JOIN──▶ CropTypes             (field may have no current crop)
  │
  └──LEFT JOIN──▶ Harvests              (field may have no harvests yet)
```

### Computed Columns in the View

| Output Column | Expression | Notes |
|---|---|---|
| `MemberName` | `FirstName + ' ' + LastName` | T-SQL string concatenation (PostgreSQL uses `||`) |
| `TotalYield` | `SUM(h.YieldBushels)` | Aggregate across all harvests for the field |
| `YieldPerAcre` | `SUM(h.YieldBushels) / f.Acreage` | Productivity metric — may return NULL if no harvests |
| `HarvestCount` | `COUNT(h.HarvestId)` | Number of harvest records |
| `LastHarvestDate` | `MAX(h.HarvestDate)` | Most recent harvest |

### Purpose

Provides a dashboard-ready summary of per-field agricultural productivity with member attribution. Used for operational reporting and likely consumed by applications or reporting tools.

---

## 8. Data Patterns from Seed & Sample Data

### 8.1 Seed Data — CropTypes

**File:** `Data/SeedData/CropTypes.sql`

| Name | GrowingSeason | DaysToMaturity | MinTemp | MaxTemp | WaterReq |
|---|---|---|---|---|---|
| Corn | Spring/Summer | 120 | 10.0 | 30.0 | High |
| Soybeans | Spring/Summer | 100 | 15.0 | 28.0 | Medium |
| Wheat | Fall/Winter | 180 | 0.0 | 25.0 | Low |
| Barley | Spring | 90 | 5.0 | 22.0 | Medium |
| Oats | Spring | 80 | 7.0 | 20.0 | Medium |

**Observations:**
- 5 crop types covering the major Midwest US grain crops
- `CropTypeId` values (via IDENTITY) will be: **1=Corn, 2=Soybeans, 3=Wheat, 4=Barley, 5=Oats** — these IDs are hard-coded in `sp_CalculateOptimalRotation` (1=Corn, 2=Soybeans)
- Temperature ranges suggest Celsius (Wheat min = 0.0°C)
- `WaterRequirement` is a categorical enum with 3 values: Low, Medium, High
- Growing seasons map to typical North American agriculture

### 8.2 Sample Data — Members

**File:** `Data/SampleData/Members.sql`

| MemberNumber | FirstName | LastName | Email | Phone | MembershipDate | Status |
|---|---|---|---|---|---|---|
| M001 | John | Smith | jsmith@email.com | 555-0101 | 2020-01-15 | Active |
| M002 | Mary | Johnson | mjohnson@email.com | 555-0102 | 2019-05-20 | Active |
| M003 | Robert | Williams | rwilliams@email.com | 555-0103 | 2021-03-10 | Active |

**Observations:**
- 3 sample members, all with `Status = 'Active'`
- `MemberNumber` follows pattern `M###` (zero-padded sequential)
- No `Address`, `City`, `State`, or `ZipCode` populated in sample data — these columns are nullable
- Membership dates span 2019–2021
- Phone numbers use `555-0xxx` format (test data pattern)

### Data Gaps

- No sample data provided for: `Fields`, `Harvests`, `FertilizerStock`, `CommodityPrices`
- No seed data for `Audit.HarvestAuditLog` (populated by trigger)

---

## 9. SQL Server–Specific Features & Migration Considerations

### 9.1 Feature Inventory

| SQL Server Feature | Where Used | PostgreSQL Equivalent | Migration Complexity |
|---|---|---|---|
| **`IDENTITY(1,1)`** | All 6 tables (PK columns) | `SERIAL` or `GENERATED ALWAYS AS IDENTITY` | 🟢 Low |
| **`GEOGRAPHY`** | `Fields.GPSBoundary` | PostGIS `GEOMETRY(POLYGON, 4326)` | 🟡 Medium — requires PostGIS extension |
| **`MONEY`** | `FertilizerStock.CostPerUnit`, `CommodityPrices.PricePerBushel`, SP output param | `NUMERIC(19,4)` or `MONEY` (PostgreSQL has MONEY but `NUMERIC` preferred) | 🟢 Low |
| **Computed column (`AS ... PERSISTED`)** | `Harvests.YieldBushels` | `GENERATED ALWAYS AS (...) STORED` | 🟡 Medium — UDF reference must be inlined or converted |
| **`GETDATE()`** | All tables (default for audit timestamps) | `CURRENT_TIMESTAMP` or `NOW()` | 🟢 Low |
| **`SUSER_SNAME()`** | `tr_AuditHarvestChanges` | `current_user` or `session_user` | 🟢 Low |
| **`FOR JSON AUTO`** | `tr_AuditHarvestChanges` | `row_to_json()` / `to_jsonb()` | 🟡 Medium |
| **`NVARCHAR(n)`** | All string columns | `VARCHAR(n)` (PostgreSQL is UTF-8 native) | 🟢 Low |
| **`DATETIME`** | Audit timestamp columns | `TIMESTAMP` (without time zone) or `TIMESTAMPTZ` | 🟢 Low |
| **`SET NOCOUNT ON`** | Both stored procedures | Not needed (no equivalent concept in PL/pgSQL) | 🟢 Low |
| **`TOP 1`** | Both stored procedures | `LIMIT 1` | 🟢 Low |
| **`inserted` / `deleted` pseudo-tables** | `tr_AuditHarvestChanges` | `NEW` / `OLD` records or transition tables | 🔴 High — requires structural rewrite |
| **Output parameters (`OUTPUT`)** | `sp_CalculateMemberPayment` | `OUT` parameters or `RETURNS` | 🟢 Low |
| **`RETURN 0`** (return code) | `sp_CalculateMemberPayment` | No direct equivalent — use `RETURNS` or exceptions | 🟢 Low |
| **String concatenation `+`** | `vw_FieldProductivity` | `||` operator | 🟢 Low |
| **`YEAR()` function** | `sp_CalculateMemberPayment` | `EXTRACT(YEAR FROM ...)` or `date_part()` | 🟢 Low |

### 9.2 High-Risk Migration Items

#### 1. Persisted Computed Column with UDF Reference

**Problem:** `Harvests.YieldBushels` is defined as:
```sql
YieldBushels AS (dbo.fn_CalculateYieldBushels(Quantity, UnitType)) PERSISTED
```
PostgreSQL's `GENERATED ALWAYS AS ... STORED` does **not** support calling user-defined functions — only immutable built-in expressions and operators.

**Migration Options:**
- (a) Inline the CASE expression directly in the generated column definition
- (b) Use a trigger to populate the column on INSERT/UPDATE
- (c) Move calculation to application layer

#### 2. Trigger Pseudo-Table Architecture

**Problem:** SQL Server provides set-based `inserted`/`deleted` pseudo-tables. PostgreSQL triggers operate **row-by-row** (`NEW`/`OLD`) or use transition tables (`REFERENCING NEW TABLE AS ...` in statement-level triggers).

**Impact:** The `FULL OUTER JOIN` pattern between `inserted` and `deleted` must be restructured.

#### 3. GEOGRAPHY → PostGIS

**Problem:** `Fields.GPSBoundary` uses SQL Server's native `GEOGRAPHY` type. Migration requires:
- Installing PostGIS extension (`CREATE EXTENSION postgis`)
- Converting to `GEOMETRY(POLYGON, 4326)` with SRID 4326
- Translating any spatial queries (none in current SQL files, but may exist in application code)

#### 4. Business Logic in Stored Procedures

**Problem:** Settlement calculations and crop rotation logic are embedded in T-SQL stored procedures with SQL Server–specific syntax (variable declarations, `TOP`, `CASE` expressions on T-SQL patterns).

**Recommended Approach (per spec):** Extract to Python services as part of the Spec2Cloud methodology, converting:
- `sp_CalculateOptimalRotation` → Python rotation recommendation service
- `sp_CalculateMemberPayment` → Python settlement calculation service

### 9.3 Docker Compose Environment

The repository provides a `docker-compose.yml` with three services for migration testing:

| Service | Image | Port | Purpose |
|---|---|---|---|
| `sqlserver` | `mcr.microsoft.com/mssql/server:2019-latest` | 1433 | Source database |
| `postgres` | `postgres:16` | 5432 | Target database (no spatial) |
| `postgis` | `postgis/postgis:16-3.4` | 5433 | Target database (with PostGIS for GEOGRAPHY migration) |

### 9.4 Migration Script Preview

The repository includes `Migration/Scripts/001_create_schema.sql` which provides the target PostgreSQL DDL. Key transformations already applied:
- `IDENTITY(1,1)` → `SERIAL`
- `NVARCHAR(n)` → `VARCHAR(n)`
- `GEOGRAPHY` → `GEOMETRY(POLYGON, 4326)`
- `MONEY` → `NUMERIC` (implicit via function returns)
- `GETDATE()` → `CURRENT_TIMESTAMP`
- `fn_CalculateYieldBushels` rewritten as PL/pgSQL `IMMUTABLE` function
- Computed column converted to `GENERATED ALWAYS AS ... STORED`
- View string concatenation `+` → `||`

Validation queries (`Migration/Validation/validation_queries.sql`) cover row counts, computed column verification, FK integrity, data type checks, and view output comparison.

---

*End of analysis. This document serves as the foundation for the Spec2Cloud migration pipeline.*
