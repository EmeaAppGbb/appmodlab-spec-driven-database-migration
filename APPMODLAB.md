---
title: "Spec-Driven Database Migration"
category: "Spec-Driven Development"
priority: "P3"
languages: ["SQL", "Python"]
duration: "5-7 hours"
repository: "appmodlab-spec-driven-database-migration"
organization: "EmeaAppGbb"
---

# Spec-Driven Database Migration

## Overview

This lab demonstrates using Spec2Cloud to generate database specifications from legacy systems and using those specs to guide migration to modern platforms. You'll reverse-engineer database schemas, document business rules in stored procedures, generate migration specifications, and execute a spec-driven migration with validation.

**Business Domain:** Agricultural supply chain and crop management for "GreenHarvest Cooperative"

## Learning Objectives

By completing this lab, you will:
- Use Spec2Cloud to reverse-engineer complex SQL Server database schemas
- Extract business rules from stored procedures, triggers, and computed columns
- Generate migration specifications that serve as both plan and acceptance criteria
- Execute a spec-driven database migration to PostgreSQL
- Validate migration completeness using spec-generated test cases

## Prerequisites

- SQL Server experience (T-SQL, stored procedures, triggers)
- Basic PostgreSQL knowledge
- Python experience (for extracted business logic)
- Docker Desktop (for SQL Server and PostgreSQL containers)

## Architecture

### Legacy Database
- **SQL Server 2012** with 120+ tables
- **80+ stored procedures** containing business logic
- **30+ triggers** for data integrity and auditing
- **Computed columns** with complex formulas
- **User-defined functions** for calculations
- **Spatial data** types (GEOGRAPHY)

### Target Architecture
- **Azure Database for PostgreSQL** with PostGIS
- **Python services** replacing stored procedures
- **PostgreSQL generated columns** replacing computed columns
- **Event handlers** replacing some triggers
- **Spec-validated migration** ensuring completeness

## Lab Instructions

### Step 1: Explore Legacy Database

**Objective:** Review schema, run key stored procedures, understand business rules.

1. Start SQL Server container:
   ```bash
   docker-compose up -d sqlserver
   ```

2. Review database objects:
   - Tables in `Schema/Tables/` directories
   - Stored procedures in `Schema/StoredProcedures/`
   - Functions in `Schema/Functions/`
   - Triggers in `Schema/Triggers/`

3. Key business logic to understand:
   - **sp_CalculateOptimalRotation** - Crop rotation algorithm
   - **sp_CalculateMemberPayment** - Settlement calculation with quality bonuses
   - **fn_CalculateYieldBushels** - Unit conversion (tonnes → bushels)
   - **tr_AuditHarvestChanges** - Regulatory compliance logging

### Step 2: Run Schema Analysis

**Objective:** Spec2Cloud extracts table definitions, relationships, constraints.

1. Review the generated schema specification at:
   `Specs/schema-spec/database-specification.md`

2. The spec documents:
   - All tables, columns, data types
   - Primary and foreign keys
   - Indexes and constraints
   - Computed column formulas
   - Spatial data usage

### Step 3: Extract Business Rules

**Objective:** Spec2Cloud analyzes stored procedures, triggers, and UDFs.

1. The specification extracts:
   - **Stored procedure logic** - Algorithms and calculations
   - **Trigger behavior** - Data integrity rules
   - **UDF implementations** - Reusable functions
   - **Computed column formulas** - Derived values

2. Example: Settlement Payment Logic
   ```
   Input: MemberId, SettlementYear
   Steps:
   1. Aggregate total yield for member
   2. Calculate average grade
   3. Apply quality multiplier (90+ = 15% bonus)
   4. Multiply by market price
   Output: Total payment amount
   ```

### Step 4: Generate Migration Spec

**Objective:** Review the complete specification with target recommendations.

1. The migration spec includes:
   - Target PostgreSQL schema DDL
   - Stored procedure → Python service mapping
   - Trigger replacement strategy
   - Data type conversion rules
   - Index migration plan

2. Key conversions:
   - `GEOGRAPHY` → PostGIS `GEOMETRY`
   - `IDENTITY` → PostgreSQL `SERIAL`
   - Computed columns → Generated columns
   - UDFs → PostgreSQL functions

### Step 5: Create Target Schema

**Objective:** Build PostgreSQL schema from specification.

1. Start PostgreSQL container:
   ```bash
   docker-compose up -d postgis
   ```

2. Run migration script:
   ```bash
   psql -h localhost -U postgres -d greenharvest -f Migration/Scripts/001_create_schema.sql
   ```

3. Verify schema creation:
   ```sql
   \dt crop_management.*
   \df crop_management.*
   SELECT * FROM crop_management.vw_field_productivity;
   ```

### Step 6: Extract Business Logic

**Objective:** Implement Python services replacing stored procedures.

1. Example: Settlement calculation in Python
   ```python
   def calculate_member_payment(member_id: int, year: int) -> Decimal:
       # Replaces sp_CalculateMemberPayment
       total_yield = get_total_yield(member_id, year)
       avg_grade = get_average_grade(member_id, year)
       
       multiplier = {
           90: 1.15, 80: 1.10, 70: 1.05
       }.get(avg_grade // 10 * 10, 1.00)
       
       price = get_market_price(year)
       return total_yield * price * multiplier
   ```

2. Unit tests validate against SQL Server output

### Step 7: Migrate Data

**Objective:** Execute data migration scripts.

1. Export from SQL Server:
   ```bash
   bcp CropManagement.CropTypes out crop_types.csv -c -S localhost -U sa
   ```

2. Import to PostgreSQL:
   ```bash
   psql -c "\COPY crop_management.crop_types FROM 'crop_types.csv' CSV HEADER"
   ```

3. Verify row counts match

### Step 8: Replace Triggers

**Objective:** Implement event handlers or PostgreSQL triggers.

1. Options for trigger replacement:
   - **PostgreSQL triggers** - For simple audit logging
   - **Application events** - For complex business logic
   - **Database hooks** - For cross-table integrity

2. Example: Audit trigger in PostgreSQL
   ```sql
   CREATE TRIGGER tr_audit_harvests
   AFTER INSERT OR UPDATE OR DELETE ON crop_management.harvests
   FOR EACH ROW EXECUTE FUNCTION log_harvest_changes();
   ```

### Step 9: Validate

**Objective:** Run spec-generated validation queries to confirm completeness.

1. Run validation queries from:
   `Migration/Validation/validation_queries.sql`

2. Validation checks:
   - ✅ Row count comparison (source = target)
   - ✅ Computed column accuracy
   - ✅ Foreign key integrity
   - ✅ Data type correctness
   - ✅ View output matches

3. Business logic validation:
   - Run settlement calculation in both systems
   - Compare results for sample members
   - Verify quality multipliers applied correctly

## Key Concepts

### Spec-Driven Migration Workflow

```
Legacy DB → Spec2Cloud Analysis → Specification → Target Implementation → Validation
```

### Business Rule Extraction Patterns

| SQL Server Pattern | PostgreSQL Equivalent |
|-------------------|----------------------|
| Computed column with UDF | Generated column with PL/pgSQL function |
| Stored procedure | Python service or PostgreSQL function |
| Trigger (audit) | PostgreSQL trigger |
| Trigger (complex logic) | Application event handler |
| Table-valued parameter | Array type parameter |

### Migration Complexity Factors

- **High:** Computed columns with UDFs, cross-database queries
- **Medium:** Stored procedures, triggers, spatial data
- **Low:** Tables, views, simple indexes

## Success Criteria

✅ SQL Server database created with 120+ tables and all objects  
✅ Stored procedures execute correctly with sample data  
✅ Triggers fire and enforce business rules  
✅ Spec2Cloud generates complete schema specification  
✅ Business rules extracted and documented from stored procedures  
✅ PostgreSQL schema created from specification  
✅ Python services replicate stored procedure logic  
✅ Data migration completes with validation queries passing  

## Resources

- [Spec2Cloud Documentation](https://spec2cloud.dev)
- [PostgreSQL Migration Guide](https://wiki.postgresql.org/wiki/Category:Migration)
- [PostGIS Documentation](https://postgis.net/documentation/)

## Troubleshooting

**Issue:** Computed column not working in PostgreSQL  
**Solution:** Use `GENERATED ALWAYS AS () STORED` syntax

**Issue:** Spatial data migration fails  
**Solution:** Ensure PostGIS extension is enabled before creating geometry columns

**Issue:** Python service returns different results  
**Solution:** Check for NULL handling differences between T-SQL and Python

---

**Estimated Duration:** 5-7 hours  
**Difficulty:** Advanced  
**Category:** Spec-Driven Development
