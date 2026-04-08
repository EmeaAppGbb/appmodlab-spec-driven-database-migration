# GreenHarvest Database Schema Specification

## Overview
- **Source System:** SQL Server 2012 Standard Edition
- **Target System:** Azure Database for PostgreSQL
- **Database Name:** GreenHarvest
- **Total Objects:** 120+ tables, 80+ stored procedures, 30+ triggers

## Schema Structure

### CropManagement Schema
Tables: CropTypes, Fields, PlantingSchedules, Harvests
- Primary business logic for agricultural operations
- Complex relationships between crops, fields, and harvests
- Computed columns for yield calculations

### Inventory Schema
Tables: FertilizerStock, PesticideInventory, SeedInventory
- Inventory management for agricultural inputs
- Reorder level automation via triggers

### Members Schema
Tables: MemberAccounts, MemberTransactions, MemberSettlements
- Cooperative member management
- Financial settlement tracking

### Trading Schema
Tables: CommodityPrices, MarketTransactions
- Market price tracking
- Settlement calculations based on grade/quality matrices

## Business Rules Encoded in Database

### Stored Procedures
1. **sp_CalculateOptimalRotation**
   - Logic: Determines best crop for next season based on:
     - Previous crop history
     - Soil type and nutrients
     - Current market prices
     - Rotation scoring algorithm
   
2. **sp_CalculateMemberPayment**
   - Logic: Settlement payment calculation
     - Total yield aggregation
     - Quality/grade multipliers (90+ = 15% bonus)
     - Market price correlation
     - Pro-rated payments

### Computed Columns
- **Harvests.YieldBushels** - Calculated via fn_CalculateYieldBushels()
  - Converts tonnes, hundredweight, kg to bushels
  - Different conversion factors per crop type

### Triggers
- **tr_AuditHarvestChanges**
  - Logs all harvest changes for regulatory compliance
  - Captures before/after state as JSON
  - Required for USDA reporting

## Migration Challenges

1. **Computed Columns with UDF References**
   - PostgreSQL doesn't support PERSISTED computed columns
   - Solution: Convert to generated columns or application logic

2. **Triggers with Implicit Dependencies**
   - SQL Server trigger execution order undefined
   - PostgreSQL requires explicit ordering

3. **User-Defined Types**
   - Table-valued parameters in stored procedures
   - Solution: Replace with PostgreSQL array types

4. **GEOGRAPHY Data Type**
   - Fields.GPSBoundary uses SQL Server spatial types
   - Solution: Migrate to PostGIS extension

5. **Business Logic in Stored Procedures**
   - 80+ procedures containing critical business rules
   - Solution: Extract to Python services using Spec2Cloud

## Spec2Cloud Analysis Output

### Automated Extraction
✅ Schema structure (tables, columns, constraints)
✅ Index definitions
✅ Foreign key relationships
✅ Stored procedure logic breakdown
✅ Trigger behavior analysis
✅ UDF functionality mapping
✅ Computed column formulas

### Generated Artifacts
- PostgreSQL DDL scripts
- Python service stubs for stored procedures
- Data migration scripts
- Validation test queries
- Business rule documentation

## Target PostgreSQL Architecture

```sql
-- Example: Harvests table in PostgreSQL
CREATE TABLE crop_management.harvests (
    harvest_id SERIAL PRIMARY KEY,
    field_id INT NOT NULL REFERENCES crop_management.fields(field_id),
    crop_type_id INT NOT NULL REFERENCES crop_management.crop_types(crop_type_id),
    harvest_date DATE NOT NULL,
    quantity NUMERIC(12,2) NOT NULL,
    unit_type VARCHAR(20) NOT NULL,
    yield_bushels NUMERIC(12,2) GENERATED ALWAYS AS (
        calculate_yield_bushels(quantity, unit_type)
    ) STORED,
    moisture_content NUMERIC(5,2),
    grade_code VARCHAR(10),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

```python
# Example: Python service for settlement calculation
def calculate_member_payment(member_id: int, settlement_year: int) -> Decimal:
    total_yield = get_member_total_yield(member_id, settlement_year)
    average_grade = get_average_grade(member_id, settlement_year)
    
    quality_multiplier = {
        range(90, 101): 1.15,
        range(80, 90): 1.10,
        range(70, 80): 1.05
    }.get(next((r for r in ranges if average_grade in r), None), 1.00)
    
    market_price = get_latest_market_price(settlement_year)
    
    return total_yield * market_price * quality_multiplier
```

## Validation Strategy

### Data Validation
- Row count comparison (source vs target)
- Sample data integrity checks
- Foreign key constraint verification

### Logic Validation
- Stored procedure output comparison
- Computed column value verification
- Trigger behavior testing

### Performance Validation
- Query execution time comparison
- Index effectiveness analysis
- Concurrent load testing
