---
title: "Spec-Driven Database Migration"
description: "Migrate SQL Server to PostgreSQL using spec-driven approach with GreenHarvest agricultural system"
authors: ["marconsilva"]
category: "Spec-Driven Development"
industry: "Cross-Industry"
services: ["Azure Database for PostgreSQL", "Azure Functions"]
languages: ["Python", "SQL"]
frameworks: []
modernizationTools: ["Spec2Cloud"]
agenticTools: []
tags: ["database-migration", "sql-server", "postgresql", "stored-procedures", "business-rules"]
extensions: ["github.copilot"]
thumbnail: ""
video: ""
version: "1.0.0"
screenshots:
  - title: "Source Schema Tables (SQL Server)"
    path: "assets/screenshots/01-source-schema-tables.html"
    description: "All 6 core SQL Server tables across CropManagement, Members, Inventory, and Trading schemas with indexes and foreign keys."
  - title: "Stored Procedures – Business Logic"
    path: "assets/screenshots/02-stored-procedures.html"
    description: "sp_CalculateOptimalRotation (crop planning) and sp_CalculateMemberPayment (settlement) with embedded business rules."
  - title: "Trigger, Scalar Function & View"
    path: "assets/screenshots/03-trigger-and-function.html"
    description: "tr_AuditHarvestChanges audit trigger, fn_CalculateYieldBushels unit conversion UDF, and vw_FieldProductivity view."
  - title: "PostgreSQL Migration Script"
    path: "assets/screenshots/04-postgresql-migration.html"
    description: "Spec2Cloud-generated 001_create_schema.sql showing GEOGRAPHY→PostGIS, computed→GENERATED ALWAYS, and UDF→PL/pgSQL conversions."
  - title: "Validation Queries & Seed Data"
    path: "assets/screenshots/05-validation-and-seed-data.html"
    description: "Row counts, computed column checks, FK integrity validation, plus CropTypes seed data and sample Members."
  - title: "Docker Compose Infrastructure"
    path: "assets/screenshots/06-docker-compose.html"
    description: "Three-service stack: SQL Server 2019, PostgreSQL 16, and PostGIS 16-3.4 with named volumes."
---


# Spec-Driven Database Migration

## Overview

This lab demonstrates migrating a SQL Server database to PostgreSQL using a spec-driven approach with the GreenHarvest agricultural cooperative system. Spec2Cloud analyzes the legacy schema, extracts business rules from stored procedures, and generates a complete migration plan.

## Source Database (SQL Server)

### Schema Tables

The GreenHarvest legacy database contains 6 core tables across the CropManagement, Members, Inventory, and Trading schemas, with indexes and foreign keys enforcing referential integrity.

> 📸 [View: Source Schema Tables (SQL Server)](assets/screenshots/01-source-schema-tables.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Stored Procedures — Business Logic

Key business logic lives in stored procedures: `sp_CalculateOptimalRotation` handles crop planning, and `sp_CalculateMemberPayment` computes cooperative settlement amounts.

> 📸 [View: Stored Procedures — Business Logic](assets/screenshots/02-stored-procedures.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Triggers, Functions & Views

The database includes the `tr_AuditHarvestChanges` audit trigger, `fn_CalculateYieldBushels` unit conversion UDF, and `vw_FieldProductivity` summary view.

> 📸 [View: Trigger, Scalar Function & View](assets/screenshots/03-trigger-and-function.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Target Database (PostgreSQL)

### Migration Script

Spec2Cloud generates the PostgreSQL migration script `001_create_schema.sql`, converting GEOGRAPHY to PostGIS, computed columns to GENERATED ALWAYS, and UDFs to PL/pgSQL.

> 📸 [View: PostgreSQL Migration Script](assets/screenshots/04-postgresql-migration.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Validation & Seed Data

Validation queries verify row counts, computed column correctness, and foreign key integrity. Seed data includes CropTypes and sample Members for testing.

> 📸 [View: Validation Queries & Seed Data](assets/screenshots/05-validation-and-seed-data.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Development Infrastructure

The Docker Compose stack runs three services: SQL Server 2019, PostgreSQL 16, and PostGIS 16-3.4 with named volumes for data persistence.

> 📸 [View: Docker Compose Infrastructure](assets/screenshots/06-docker-compose.html)
> *Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Screenshots

The `assets/screenshots/` directory contains syntax-highlighted HTML renderings of the lab's key files. Open any `.html` file in a browser to view or capture a screenshot.

| # | File | What it shows |
|---|------|---------------|
| 1 | [`01-source-schema-tables.html`](assets/screenshots/01-source-schema-tables.html) | Source Schema Tables (SQL Server) |
| 2 | [`02-stored-procedures.html`](assets/screenshots/02-stored-procedures.html) | Stored Procedures — Business Logic |
| 3 | [`03-trigger-and-function.html`](assets/screenshots/03-trigger-and-function.html) | Trigger, Scalar Function & View |
| 4 | [`04-postgresql-migration.html`](assets/screenshots/04-postgresql-migration.html) | PostgreSQL Migration Script |
| 5 | [`05-validation-and-seed-data.html`](assets/screenshots/05-validation-and-seed-data.html) | Validation Queries & Seed Data |
| 6 | [`06-docker-compose.html`](assets/screenshots/06-docker-compose.html) | Docker Compose Infrastructure |
