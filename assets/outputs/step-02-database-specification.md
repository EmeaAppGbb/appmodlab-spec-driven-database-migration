# GreenHarvest Agricultural Co-op — Database Specification

> **Generated:** 2026-04-16  
> **Source System:** SQL Server 2012 Standard Edition  
> **Database Name:** GreenHarvest  
> **Spec Version:** 2.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Complete Table Catalog](#2-complete-table-catalog)
3. [Primary Keys & IDENTITY Columns](#3-primary-keys--identity-columns)
4. [Foreign Key Relationships](#4-foreign-key-relationships)
5. [Index Inventory](#5-index-inventory)
6. [Stored Procedure Specifications](#6-stored-procedure-specifications)
7. [Scalar Function Specification](#7-scalar-function-specification)
8. [Trigger Specification](#8-trigger-specification)
9. [View Definitions](#9-view-definitions)
10. [Cross-Reference Matrix](#10-cross-reference-matrix)
11. [Data Volume Estimates](#11-data-volume-estimates)
12. [SQL Server–Specific Feature Catalog](#12-sql-serverspecific-feature-catalog)

---

## 1. Executive Summary

The **GreenHarvest** database supports the core operations of a multi-member agricultural cooperative. It manages member accounts, crop planning and harvest tracking, commodity-price trading, fertilizer inventory, and end-of-year financial settlements. The schema is organized into five logical schemas:

| Schema | Purpose |
|---|---|
| **Members** | Cooperative member registration and contact details |
| **CropManagement** | Fields, crop types, harvests, and planning data |
| **Trading** | Market commodity pricing |
| **Inventory** | Fertilizer and input-supply stock management |
| **Audit** | Regulatory-compliance change logs (referenced by trigger) |
| **dbo** | Shared utility functions |

Key design characteristics:
- **6 tables** defined across 4 primary schemas, plus 1 implied audit table.
- **2 stored procedures** encoding settlement-payment and crop-rotation business rules.
- **1 scalar function** used in a PERSISTED computed column for unit-to-bushel conversion.
- **1 AFTER trigger** capturing INSERT / UPDATE / DELETE events as JSON for USDA regulatory compliance.
- **1 view** aggregating field-level productivity metrics.
- SQL Server–specific features include `GEOGRAPHY`, `MONEY`, `PERSISTED` computed columns, `SUSER_SNAME()`, and `FOR JSON AUTO`.

---

## 2. Complete Table Catalog

### 2.1 Members.MemberAccounts

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | MemberId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | MemberNumber | NVARCHAR(20) | NO | — | UNIQUE |
| 3 | FirstName | NVARCHAR(50) | NO | — | — |
| 4 | LastName | NVARCHAR(50) | NO | — | — |
| 5 | Email | NVARCHAR(100) | YES | — | — |
| 6 | PhoneNumber | NVARCHAR(20) | YES | — | — |
| 7 | Address | NVARCHAR(200) | YES | — | — |
| 8 | City | NVARCHAR(50) | YES | — | — |
| 9 | State | NVARCHAR(2) | YES | — | — |
| 10 | ZipCode | NVARCHAR(10) | YES | — | — |
| 11 | MembershipDate | DATE | NO | — | — |
| 12 | Status | NVARCHAR(20) | YES | `'Active'` | — |
| 13 | CreatedDate | DATETIME | YES | `GETDATE()` | — |
| 14 | ModifiedDate | DATETIME | YES | `GETDATE()` | — |

**Source:** `Schema/Tables/Members/MemberAccounts.sql`

---

### 2.2 CropManagement.CropTypes

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | CropTypeId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | Name | NVARCHAR(100) | NO | — | — |
| 3 | GrowingSeason | NVARCHAR(50) | NO | — | — |
| 4 | DaysToMaturity | INT | NO | — | — |
| 5 | MinTemperature | DECIMAL(5,2) | YES | — | — |
| 6 | MaxTemperature | DECIMAL(5,2) | YES | — | — |
| 7 | WaterRequirement | NVARCHAR(20) | YES | — | — |
| 8 | CreatedDate | DATETIME | YES | `GETDATE()` | — |
| 9 | ModifiedDate | DATETIME | YES | `GETDATE()` | — |

**Source:** `Schema/Tables/CropManagement/CropTypes.sql`

---

### 2.3 CropManagement.Fields

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | FieldId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | MemberId | INT | NO | — | **FK → Members.MemberAccounts(MemberId)** |
| 3 | FieldName | NVARCHAR(100) | NO | — | — |
| 4 | Acreage | DECIMAL(10,2) | NO | — | — |
| 5 | SoilType | NVARCHAR(50) | YES | — | — |
| 6 | IrrigationType | NVARCHAR(50) | YES | — | — |
| 7 | GPSBoundary | GEOGRAPHY | YES | — | SQL Server spatial type |
| 8 | CurrentCropId | INT | YES | — | **FK → CropManagement.CropTypes(CropTypeId)** |
| 9 | CreatedDate | DATETIME | YES | `GETDATE()` | — |
| 10 | ModifiedDate | DATETIME | YES | `GETDATE()` | — |

**Source:** `Schema/Tables/CropManagement/Fields.sql`

---

### 2.4 CropManagement.Harvests

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | HarvestId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | FieldId | INT | NO | — | **FK → CropManagement.Fields(FieldId)** |
| 3 | CropTypeId | INT | NO | — | **FK → CropManagement.CropTypes(CropTypeId)** |
| 4 | HarvestDate | DATE | NO | — | — |
| 5 | YieldBushels | _Computed_ | — | `dbo.fn_CalculateYieldBushels(Quantity, UnitType)` | **PERSISTED** computed column |
| 6 | Quantity | DECIMAL(12,2) | NO | — | — |
| 7 | UnitType | NVARCHAR(20) | NO | — | — |
| 8 | MoistureContent | DECIMAL(5,2) | YES | — | — |
| 9 | GradeCode | NVARCHAR(10) | YES | — | — |
| 10 | CreatedDate | DATETIME | YES | `GETDATE()` | — |

**Notes:**
- `YieldBushels` is a **PERSISTED computed column** whose value is physically stored on disk and recalculated on write. It invokes the scalar UDF `dbo.fn_CalculateYieldBushels`.
- The persisted column's effective return type is `DECIMAL(12,2)` (matching the UDF).

**Source:** `Schema/Tables/CropManagement/Harvests.sql`

---

### 2.5 Trading.CommodityPrices

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | PriceId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | CropTypeId | INT | NO | — | **FK → CropManagement.CropTypes(CropTypeId)** |
| 3 | MarketDate | DATE | NO | — | — |
| 4 | PricePerBushel | MONEY | NO | — | SQL Server MONEY type |
| 5 | MarketName | NVARCHAR(100) | YES | — | — |
| 6 | CreatedDate | DATETIME | YES | `GETDATE()` | — |

**Source:** `Schema/Tables/Trading/CommodityPrices.sql`

---

### 2.6 Inventory.FertilizerStock

| # | Column | Data Type | Nullable | Default | Constraints |
|---|--------|-----------|----------|---------|-------------|
| 1 | StockId | INT | NO | IDENTITY(1,1) | **PK** |
| 2 | ProductName | NVARCHAR(100) | NO | — | — |
| 3 | ManufacturerName | NVARCHAR(100) | YES | — | — |
| 4 | QuantityOnHand | DECIMAL(12,2) | NO | — | — |
| 5 | Unit | NVARCHAR(20) | NO | — | — |
| 6 | CostPerUnit | MONEY | NO | — | SQL Server MONEY type |
| 7 | ReorderLevel | DECIMAL(12,2) | YES | — | — |
| 8 | LastRestockDate | DATE | YES | — | — |
| 9 | ExpirationDate | DATE | YES | — | — |
| 10 | CreatedDate | DATETIME | YES | `GETDATE()` | — |

**Source:** `Schema/Tables/Inventory/FertilizerStock.sql`

---

### 2.7 Audit.HarvestAuditLog (Implied by Trigger)

The `tr_AuditHarvestChanges` trigger writes to this table. The implied schema is:

| # | Column | Inferred Data Type | Nullable | Description |
|---|--------|--------------------|----------|-------------|
| 1 | HarvestId | INT | NO | FK to Harvests (logical) |
| 2 | ChangeType | NVARCHAR(10) | NO | `'INSERT'`, `'UPDATE'`, or `'DELETE'` |
| 3 | ChangedBy | NVARCHAR(128) | NO | Value of `SUSER_SNAME()` |
| 4 | ChangeDate | DATETIME | NO | Value of `GETDATE()` |
| 5 | OldValue | NVARCHAR(MAX) | YES | JSON snapshot from `deleted` via `FOR JSON AUTO` |
| 6 | NewValue | NVARCHAR(MAX) | YES | JSON snapshot from `inserted` via `FOR JSON AUTO` |

**Note:** The DDL for this table is not present in the repository; it is inferred from the trigger body.

---

## 3. Primary Keys & IDENTITY Columns

Every table uses a single-column, auto-incrementing integer primary key seeded at 1 with increment 1.

| Table | PK Column | IDENTITY Seed | IDENTITY Increment |
|-------|-----------|---------------|-------------------|
| Members.MemberAccounts | MemberId | 1 | 1 |
| CropManagement.CropTypes | CropTypeId | 1 | 1 |
| CropManagement.Fields | FieldId | 1 | 1 |
| CropManagement.Harvests | HarvestId | 1 | 1 |
| Trading.CommodityPrices | PriceId | 1 | 1 |
| Inventory.FertilizerStock | StockId | 1 | 1 |

**Design pattern:** All primary keys are surrogate `INT IDENTITY(1,1)` columns. The only natural key is `MemberAccounts.MemberNumber` (enforced via `UNIQUE`).

---

## 4. Foreign Key Relationships

| Constraint Name | Child Table | Child Column | Parent Table | Parent Column | On Delete | On Update |
|-----------------|-------------|--------------|--------------|---------------|-----------|-----------|
| FK_Fields_Member | CropManagement.Fields | MemberId | Members.MemberAccounts | MemberId | NO ACTION (default) | NO ACTION (default) |
| FK_Fields_CurrentCrop | CropManagement.Fields | CurrentCropId | CropManagement.CropTypes | CropTypeId | NO ACTION (default) | NO ACTION (default) |
| FK_Harvests_Field | CropManagement.Harvests | FieldId | CropManagement.Fields | FieldId | NO ACTION (default) | NO ACTION (default) |
| FK_Harvests_CropType | CropManagement.Harvests | CropTypeId | CropManagement.CropTypes | CropTypeId | NO ACTION (default) | NO ACTION (default) |
| FK_Prices_CropType | Trading.CommodityPrices | CropTypeId | CropManagement.CropTypes | CropTypeId | NO ACTION (default) | NO ACTION (default) |

**Cascade rules:** No explicit `ON DELETE CASCADE` or `ON UPDATE CASCADE` is defined for any foreign key. All relationships default to `NO ACTION`, meaning deletes or updates of referenced rows will be rejected if child rows exist.

**FK graph (parent → child):**

```
Members.MemberAccounts
  └── CropManagement.Fields

CropManagement.CropTypes
  ├── CropManagement.Fields  (CurrentCropId, nullable)
  ├── CropManagement.Harvests
  └── Trading.CommodityPrices

CropManagement.Fields
  └── CropManagement.Harvests
```

---

## 5. Index Inventory

| Index Name | Table | Column(s) | Type | Unique |
|------------|-------|-----------|------|--------|
| _PK (clustered)_ | Members.MemberAccounts | MemberId | Clustered (PK) | Yes |
| _UQ_ | Members.MemberAccounts | MemberNumber | Unique | Yes |
| IX_Members_Number | Members.MemberAccounts | MemberNumber | Non-clustered | No |
| IX_Members_Name | Members.MemberAccounts | LastName, FirstName | Non-clustered | No |
| _PK (clustered)_ | CropManagement.CropTypes | CropTypeId | Clustered (PK) | Yes |
| IX_CropTypes_Name | CropManagement.CropTypes | Name | Non-clustered | No |
| IX_CropTypes_Season | CropManagement.CropTypes | GrowingSeason | Non-clustered | No |
| _PK (clustered)_ | CropManagement.Fields | FieldId | Clustered (PK) | Yes |
| IX_Fields_Member | CropManagement.Fields | MemberId | Non-clustered | No |
| IX_Fields_CurrentCrop | CropManagement.Fields | CurrentCropId | Non-clustered | No |
| _PK (clustered)_ | CropManagement.Harvests | HarvestId | Clustered (PK) | Yes |
| IX_Harvests_Field | CropManagement.Harvests | FieldId | Non-clustered | No |
| IX_Harvests_Date | CropManagement.Harvests | HarvestDate | Non-clustered | No |
| _PK (clustered)_ | Trading.CommodityPrices | PriceId | Clustered (PK) | Yes |
| IX_Prices_CropDate | Trading.CommodityPrices | CropTypeId, MarketDate | Non-clustered (composite) | No |
| _PK (clustered)_ | Inventory.FertilizerStock | StockId | Clustered (PK) | Yes |
| IX_Fertilizer_Product | Inventory.FertilizerStock | ProductName | Non-clustered | No |

**Total:** 6 clustered (PK) + 1 unique + 10 non-clustered = **17 indexes**

---

## 6. Stored Procedure Specifications

### 6.1 Settlement.sp_CalculateMemberPayment

| Attribute | Value |
|-----------|-------|
| **Schema** | Settlement |
| **Full Name** | `Settlement.sp_CalculateMemberPayment` |
| **Source** | `Schema/StoredProcedures/Settlement/sp_CalculateMemberPayment.sql` |
| **Return Code** | `0` (success) |

#### Parameters

| Parameter | Data Type | Direction | Description |
|-----------|-----------|-----------|-------------|
| @MemberId | INT | IN | Cooperative member identifier |
| @SettlementYear | INT | IN | Calendar year for settlement |
| @TotalPayment | MONEY | OUTPUT | Calculated payment amount |

#### Local Variables

| Variable | Data Type | Purpose |
|----------|-----------|---------|
| @TotalYield | DECIMAL(12,2) | Sum of YieldBushels for the member in the settlement year |
| @AverageGrade | DECIMAL(5,2) | Mean of GradeCode cast to decimal |
| @QualityMultiplier | DECIMAL(5,3) | Quality bonus factor |

#### Business Rules — Quality Multiplier Matrix

| Average Grade | Multiplier | Effective Bonus |
|---------------|------------|-----------------|
| ≥ 90 | 1.150 | +15 % |
| 80 – 89 | 1.100 | +10 % |
| 70 – 79 | 1.050 | +5 % |
| < 70 | 1.000 | 0 % |

#### Calculation Logic

1. **Yield aggregation:** Sum `YieldBushels` from `CropManagement.Harvests` joined to `CropManagement.Fields` for the given `@MemberId` where `YEAR(HarvestDate) = @SettlementYear`.
2. **Grade averaging:** Average `GradeCode` (cast to DECIMAL) across the same harvest set.
3. **Quality multiplier:** Apply tiered bonus per the matrix above.
4. **Price lookup:** Find the most recent `PricePerBushel` from `Trading.CommodityPrices` in the settlement year, matched to the member's **dominant crop** (highest total yield by CropTypeId).
5. **Final formula:** `@TotalPayment = @TotalYield × PricePerBushel × @QualityMultiplier`

#### Tables Accessed

| Table | Access | Join/Filter |
|-------|--------|-------------|
| CropManagement.Harvests | READ | JOIN on FieldId; filter on YEAR(HarvestDate) |
| CropManagement.Fields | READ | JOIN on FieldId; filter on MemberId |
| Trading.CommodityPrices | READ | Subquery MAX(MarketDate) in year; filter CropTypeId |

---

### 6.2 CropPlanning.sp_CalculateOptimalRotation

| Attribute | Value |
|-----------|-------|
| **Schema** | CropPlanning |
| **Full Name** | `CropPlanning.sp_CalculateOptimalRotation` |
| **Source** | `Schema/StoredProcedures/CropPlanning/sp_CalculateOptimalRotation.sql` |
| **Return Type** | Result set (single row) |

#### Parameters

| Parameter | Data Type | Direction | Description |
|-----------|-----------|-----------|-------------|
| @FieldId | INT | IN | Target field for rotation recommendation |
| @CurrentYear | INT | IN | Planning year (used contextually; not directly filtered in current code) |

#### Local Variables

| Variable | Data Type | Purpose |
|----------|-----------|---------|
| @LastCropId | INT | Current crop on the field |
| @SoilType | NVARCHAR(50) | Soil classification of the field |
| @RecommendedCropId | INT | Declared but unused in current implementation |

#### Result Set Columns

| Column | Data Type | Description |
|--------|-----------|-------------|
| CropTypeId | INT | Recommended next crop |
| Name | NVARCHAR(100) | Crop name |
| RotationScore | INT | Agronomic rotation score |
| CurrentPrice | MONEY | Latest market price per bushel |
| TotalScore | DECIMAL | Weighted composite score |

#### Business Rules — Rotation Scoring

| Previous Crop (CropTypeId) | Rotation Score | Rationale |
|---------------------------|----------------|-----------|
| 1 (Corn) | 10 | After corn, strongly prefer soybeans (nitrogen fixation) |
| 2 (Soybeans) | 5 | After soybeans, any crop acceptable |
| Any other | 7 | Neutral rotation preference |

#### Composite Score Formula

```
TotalScore = (RotationScore × 0.6) + ((CurrentPrice / 10) × 0.4)
```

- 60 % weight on agronomic rotation suitability.
- 40 % weight on market profitability signal.
- The candidate with the highest `TotalScore` is returned (`TOP 1 … ORDER BY TotalScore DESC`).
- The field's current crop is **excluded** from candidates.

#### Tables Accessed

| Table | Access | Join/Filter |
|-------|--------|-------------|
| CropManagement.Fields | READ | Lookup CurrentCropId, SoilType |
| CropManagement.CropTypes | READ | All crop candidates except current |
| Trading.CommodityPrices | READ | Latest price per crop (MAX MarketDate subquery) |

---

## 7. Scalar Function Specification

### 7.1 dbo.fn_CalculateYieldBushels

| Attribute | Value |
|-----------|-------|
| **Schema** | dbo |
| **Full Name** | `dbo.fn_CalculateYieldBushels` |
| **Source** | `Schema/Functions/Scalar/fn_CalculateYieldBushels.sql` |
| **Return Type** | DECIMAL(12,2) |
| **Deterministic** | Yes |

#### Parameters

| Parameter | Data Type | Description |
|-----------|-----------|-------------|
| @Quantity | DECIMAL(12,2) | Raw harvest quantity |
| @UnitType | NVARCHAR(20) | Unit of measure code |

#### Conversion Factor Table

| @UnitType Value | Conversion Factor | Calculation | Notes |
|-----------------|-------------------|-------------|-------|
| `'bushels'` | 1.0 | `@Quantity × 1` | Identity — no conversion |
| `'tonnes'` | 36.7437 | `@Quantity × 36.7437` | Metric tonne to bushels (wheat basis) |
| `'hundredweight'` | 1.667 | `@Quantity × 1.667` | CWT to bushels |
| `'kilograms'` | 0.0367437 | `@Quantity × 0.0367437` | kg to bushels (= 1/27.2155 approx) |
| _Any other value_ | 1.0 | `@Quantity × 1` | **Fallback:** treated as bushels |

**Usage:** This function is referenced in the `PERSISTED` computed column `Harvests.YieldBushels`. Because it is deterministic and PERSISTED, SQL Server stores the computed value physically and recalculates it only on INSERT/UPDATE of `Quantity` or `UnitType`.

---

## 8. Trigger Specification

### 8.1 tr_AuditHarvestChanges

| Attribute | Value |
|-----------|-------|
| **Target Table** | CropManagement.Harvests |
| **Timing** | AFTER |
| **Events** | INSERT, UPDATE, DELETE |
| **Source** | `Schema/Triggers/tr_AuditHarvestChanges.sql` |

#### Destination Table

`Audit.HarvestAuditLog` (see §2.7 for implied schema).

#### Event-to-ChangeType Mapping

| DML Event | `inserted` Rows? | `deleted` Rows? | ChangeType Written |
|-----------|-------------------|------------------|--------------------|
| INSERT | Yes | No | `'INSERT'` |
| UPDATE | Yes | Yes | `'UPDATE'` |
| DELETE | No | Yes | `'DELETE'` |

**Detection logic:** The trigger uses `FULL OUTER JOIN` between `inserted` and `deleted` on `HarvestId`, then determines the change type via:
```sql
CASE 
    WHEN i.HarvestId IS NOT NULL AND d.HarvestId IS NULL THEN 'INSERT'
    WHEN i.HarvestId IS NOT NULL AND d.HarvestId IS NOT NULL THEN 'UPDATE'
    ELSE 'DELETE'
END
```

#### Audit Record Contents

| Field | Source | Notes |
|-------|--------|-------|
| ChangedBy | `SUSER_SNAME()` | Windows/SQL Server login name of the session |
| ChangeDate | `GETDATE()` | Server-local timestamp |
| OldValue | `(SELECT * FROM deleted … FOR JSON AUTO)` | Full row snapshot before change; NULL on INSERT |
| NewValue | `(SELECT * FROM inserted … FOR JSON AUTO)` | Full row snapshot after change; NULL on DELETE |

#### Guard Clause

The trigger body is wrapped in `IF EXISTS (SELECT * FROM inserted)` which means **pure DELETE** events (where `inserted` is empty) will **not** be logged by the current implementation. This is a potential bug — DELETE audit rows may be missed.

---

## 9. View Definitions

### 9.1 CropManagement.vw_FieldProductivity

| Attribute | Value |
|-----------|-------|
| **Schema** | CropManagement |
| **Full Name** | `CropManagement.vw_FieldProductivity` |
| **Source** | `Schema/Views/vw_FieldProductivity.sql` |

#### Output Columns

| Column | Expression | Data Type (Effective) |
|--------|------------|-----------------------|
| FieldId | f.FieldId | INT |
| FieldName | f.FieldName | NVARCHAR(100) |
| MemberNumber | m.MemberNumber | NVARCHAR(20) |
| MemberName | m.FirstName + ' ' + m.LastName | NVARCHAR(101) |
| Acreage | f.Acreage | DECIMAL(10,2) |
| CurrentCrop | ct.Name | NVARCHAR(100) |
| TotalYield | SUM(h.YieldBushels) | DECIMAL(12,2) (aggregate) |
| YieldPerAcre | SUM(h.YieldBushels) / f.Acreage | DECIMAL (derived) |
| HarvestCount | COUNT(h.HarvestId) | INT |
| LastHarvestDate | MAX(h.HarvestDate) | DATE |

#### Source Tables & Join Conditions

| Alias | Table | Join Type | Join Condition |
|-------|-------|-----------|----------------|
| f | CropManagement.Fields | — | Base table |
| m | Members.MemberAccounts | INNER JOIN | `f.MemberId = m.MemberId` |
| ct | CropManagement.CropTypes | LEFT JOIN | `f.CurrentCropId = ct.CropTypeId` |
| h | CropManagement.Harvests | LEFT JOIN | `f.FieldId = h.FieldId` |

#### GROUP BY Clause

```sql
GROUP BY f.FieldId, f.FieldName, m.MemberNumber, m.FirstName, m.LastName, f.Acreage, ct.Name
```

**Notes:**
- Fields with no harvest records will still appear (LEFT JOINs to Harvests and CropTypes).
- `YieldPerAcre` may return NULL if no harvests exist (division by acreage with NULL numerator).
- Fields without a current crop will show `NULL` for `CurrentCrop`.

---

## 10. Cross-Reference Matrix

### 10.1 Table Dependency Matrix

The matrix below shows which objects **reference** (R) or **write to** (W) each table.

| Object ↓ \ Table → | MemberAccounts | CropTypes | Fields | Harvests | CommodityPrices | FertilizerStock | HarvestAuditLog |
|---------------------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **FK_Fields_Member** | R | | | | | | |
| **FK_Fields_CurrentCrop** | | R | | | | | |
| **FK_Harvests_Field** | | | R | | | | |
| **FK_Harvests_CropType** | | R | | | | | |
| **FK_Prices_CropType** | | R | | | | | |
| **sp_CalculateMemberPayment** | | | R | R | R | | |
| **sp_CalculateOptimalRotation** | | R | R | | R | | |
| **fn_CalculateYieldBushels** | | | | _(via computed col)_ | | | |
| **tr_AuditHarvestChanges** | | | | R | | | W |
| **vw_FieldProductivity** | R | R | R | R | | | |

### 10.2 Schema-Level Dependency Graph

```
Members ──────────────┐
                      │
CropManagement ◄──────┤  (Fields references MemberAccounts)
  │                   │
  ├─ CropTypes ◄──────┤  (Fields, Harvests, CommodityPrices reference CropTypes)
  ├─ Fields ◄─────────┘
  ├─ Harvests ──────────► Audit  (via trigger)
  └─ vw_FieldProductivity (reads Members, CropTypes, Fields, Harvests)
                      
Trading ──────────────► CropManagement  (CommodityPrices references CropTypes)

Inventory              (FertilizerStock is standalone — no FK dependencies)
```

---

## 11. Data Volume Estimates

Estimates derived from seed and sample data scripts.

### 11.1 Seed Data — CropManagement.CropTypes

| CropTypeId | Name | GrowingSeason | DaysToMaturity | MinTemp (°C) | MaxTemp (°C) | WaterReq |
|------------|------|---------------|----------------|--------------|--------------|----------|
| 1 | Corn | Spring/Summer | 120 | 10.0 | 30.0 | High |
| 2 | Soybeans | Spring/Summer | 100 | 15.0 | 28.0 | Medium |
| 3 | Wheat | Fall/Winter | 180 | 0.0 | 25.0 | Low |
| 4 | Barley | Spring | 90 | 5.0 | 22.0 | Medium |
| 5 | Oats | Spring | 80 | 7.0 | 20.0 | Medium |

**Row count:** 5

### 11.2 Sample Data — Members.MemberAccounts

| MemberNumber | FirstName | LastName | Email | Phone | MembershipDate | Status |
|---|---|---|---|---|---|---|
| M001 | John | Smith | jsmith@email.com | 555-0101 | 2020-01-15 | Active |
| M002 | Mary | Johnson | mjohnson@email.com | 555-0102 | 2019-05-20 | Active |
| M003 | Robert | Williams | rwilliams@email.com | 555-0103 | 2021-03-10 | Active |

**Row count:** 3

### 11.3 Estimated Production Volumes

Based on the existing specification overview (120+ tables, 80+ stored procedures, 30+ triggers in the full system), the repository sample represents a **subset** of the full database. Estimated row counts for a mid-size cooperative:

| Table | Estimated Rows | Growth Rate |
|-------|---------------|-------------|
| Members.MemberAccounts | 200–500 | Low (< 50/year) |
| CropManagement.CropTypes | 10–30 | Very low (reference data) |
| CropManagement.Fields | 500–2,000 | Low |
| CropManagement.Harvests | 5,000–20,000 | Seasonal (1,000–5,000/year) |
| Trading.CommodityPrices | 10,000–50,000 | Daily (250+/year per crop) |
| Inventory.FertilizerStock | 50–200 | Low |
| Audit.HarvestAuditLog | 10,000–100,000 | Mirrors Harvests activity |

---

## 12. SQL Server–Specific Feature Catalog

The following features require special attention during migration to other platforms (e.g., PostgreSQL).

### 12.1 GEOGRAPHY Data Type

| Table | Column | Usage |
|-------|--------|-------|
| CropManagement.Fields | GPSBoundary | Stores geospatial boundary polygons for field mapping |

**Migration note:** PostgreSQL equivalent requires PostGIS extension (`geometry` or `geography` type).

### 12.2 MONEY Data Type

| Table | Column |
|-------|--------|
| Trading.CommodityPrices | PricePerBushel |
| Inventory.FertilizerStock | CostPerUnit |

**Characteristics:** Fixed-point 8-byte type with 4 decimal places. Range: -922,337,203,685,477.5808 to +922,337,203,685,477.5807.

**Migration note:** PostgreSQL has no native `MONEY` type suitable for calculation. Use `NUMERIC(19,4)` for equivalent precision.

### 12.3 PERSISTED Computed Columns

| Table | Column | Expression |
|-------|--------|------------|
| CropManagement.Harvests | YieldBushels | `dbo.fn_CalculateYieldBushels(Quantity, UnitType)` |

**Behavior:** Value is physically stored on disk and maintained by the engine on INSERT/UPDATE. The referenced scalar UDF must be deterministic.

**Migration note:** PostgreSQL supports `GENERATED ALWAYS AS … STORED` columns (v12+), but the expression cannot call user-defined functions. Requires inlining the CASE logic or using a trigger-based approach.

### 12.4 SUSER_SNAME()

| Object | Usage |
|--------|-------|
| tr_AuditHarvestChanges | Captures the Windows/SQL login of the session user for audit trail |

**Migration note:** PostgreSQL equivalent is `current_user` or `session_user`. If Windows authentication is used, the value format changes from `DOMAIN\user` to a PostgreSQL role name.

### 12.5 FOR JSON AUTO

| Object | Usage |
|--------|-------|
| tr_AuditHarvestChanges | Serializes `inserted` and `deleted` pseudo-table rows to JSON for audit storage |

**Behavior:** `FOR JSON AUTO` automatically structures output based on the table(s) in the SELECT. Each row becomes a JSON object; multiple rows produce a JSON array.

**Migration note:** PostgreSQL equivalent is `row_to_json()` or `to_jsonb()`. Trigger functions would use `NEW` and `OLD` record variables instead of pseudo-tables.

### 12.6 IDENTITY Columns

All six tables use `INT IDENTITY(1,1)` for auto-incrementing primary keys.

**Migration note:** PostgreSQL equivalents: `SERIAL` (deprecated style) or `INT GENERATED ALWAYS AS IDENTITY` (standard SQL).

### 12.7 GETDATE()

Used as the default value for `CreatedDate` and `ModifiedDate` columns across all tables.

**Migration note:** PostgreSQL equivalent is `CURRENT_TIMESTAMP` or `now()`.

### 12.8 NVARCHAR (Unicode Strings)

All string columns use `NVARCHAR` (Unicode). PostgreSQL `TEXT` and `VARCHAR` are natively UTF-8, so no special handling is required beyond length constraints.

---

## Appendix A — Object Inventory Summary

| Category | Count | Objects |
|----------|-------|---------|
| Schemas | 6 | Members, CropManagement, Trading, Inventory, Audit, dbo |
| Tables (explicit) | 6 | MemberAccounts, CropTypes, Fields, Harvests, CommodityPrices, FertilizerStock |
| Tables (implied) | 1 | HarvestAuditLog |
| Stored Procedures | 2 | sp_CalculateMemberPayment, sp_CalculateOptimalRotation |
| Scalar Functions | 1 | fn_CalculateYieldBushels |
| Triggers | 1 | tr_AuditHarvestChanges |
| Views | 1 | vw_FieldProductivity |
| Foreign Keys | 5 | FK_Fields_Member, FK_Fields_CurrentCrop, FK_Harvests_Field, FK_Harvests_CropType, FK_Prices_CropType |
| Indexes | 17 | 6 clustered + 1 unique + 10 non-clustered |

## Appendix B — File-to-Object Map

| File Path | Database Object |
|-----------|-----------------|
| `Schema/Tables/Members/MemberAccounts.sql` | Members.MemberAccounts + 2 indexes |
| `Schema/Tables/CropManagement/CropTypes.sql` | CropManagement.CropTypes + 2 indexes |
| `Schema/Tables/CropManagement/Fields.sql` | CropManagement.Fields + 2 indexes |
| `Schema/Tables/CropManagement/Harvests.sql` | CropManagement.Harvests + 2 indexes |
| `Schema/Tables/Trading/CommodityPrices.sql` | Trading.CommodityPrices + 1 index |
| `Schema/Tables/Inventory/FertilizerStock.sql` | Inventory.FertilizerStock + 1 index |
| `Schema/StoredProcedures/Settlement/sp_CalculateMemberPayment.sql` | Settlement.sp_CalculateMemberPayment |
| `Schema/StoredProcedures/CropPlanning/sp_CalculateOptimalRotation.sql` | CropPlanning.sp_CalculateOptimalRotation |
| `Schema/Functions/Scalar/fn_CalculateYieldBushels.sql` | dbo.fn_CalculateYieldBushels |
| `Schema/Triggers/tr_AuditHarvestChanges.sql` | tr_AuditHarvestChanges |
| `Schema/Views/vw_FieldProductivity.sql` | CropManagement.vw_FieldProductivity |
| `Data/SeedData/CropTypes.sql` | Seed data for CropManagement.CropTypes (5 rows) |
| `Data/SampleData/Members.sql` | Sample data for Members.MemberAccounts (3 rows) |
