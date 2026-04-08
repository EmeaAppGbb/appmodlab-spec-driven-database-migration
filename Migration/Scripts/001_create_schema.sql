-- PostgreSQL Migration Script
-- Generated from Spec2Cloud analysis

-- Create schemas
CREATE SCHEMA IF NOT EXISTS crop_management;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS members;
CREATE SCHEMA IF NOT EXISTS trading;

-- Enable PostGIS for spatial data
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create crop_types table
CREATE TABLE crop_management.crop_types (
    crop_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    growing_season VARCHAR(50) NOT NULL,
    days_to_maturity INT NOT NULL,
    min_temperature NUMERIC(5,2),
    max_temperature NUMERIC(5,2),
    water_requirement VARCHAR(20),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_crop_types_name ON crop_management.crop_types(name);
CREATE INDEX idx_crop_types_season ON crop_management.crop_types(growing_season);

-- Create member_accounts table
CREATE TABLE members.member_accounts (
    member_id SERIAL PRIMARY KEY,
    member_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone_number VARCHAR(20),
    address VARCHAR(200),
    city VARCHAR(50),
    state VARCHAR(2),
    zip_code VARCHAR(10),
    membership_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'Active',
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_members_number ON members.member_accounts(member_number);
CREATE INDEX idx_members_name ON members.member_accounts(last_name, first_name);

-- Create fields table with PostGIS geometry
CREATE TABLE crop_management.fields (
    field_id SERIAL PRIMARY KEY,
    member_id INT NOT NULL REFERENCES members.member_accounts(member_id),
    field_name VARCHAR(100) NOT NULL,
    acreage NUMERIC(10,2) NOT NULL,
    soil_type VARCHAR(50),
    irrigation_type VARCHAR(50),
    gps_boundary GEOMETRY(POLYGON, 4326),  -- PostGIS geometry type
    current_crop_id INT,
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_fields_crop FOREIGN KEY (current_crop_id) 
        REFERENCES crop_management.crop_types(crop_type_id)
);

CREATE INDEX idx_fields_member ON crop_management.fields(member_id);
CREATE INDEX idx_fields_current_crop ON crop_management.fields(current_crop_id);

-- Create function for yield calculation (replaces SQL Server UDF)
CREATE OR REPLACE FUNCTION crop_management.calculate_yield_bushels(
    quantity NUMERIC,
    unit_type VARCHAR
)
RETURNS NUMERIC AS $$
BEGIN
    RETURN CASE unit_type
        WHEN 'bushels' THEN quantity
        WHEN 'tonnes' THEN quantity * 36.7437
        WHEN 'hundredweight' THEN quantity * 1.667
        WHEN 'kilograms' THEN quantity * 0.0367437
        ELSE quantity
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create harvests table with generated column
CREATE TABLE crop_management.harvests (
    harvest_id SERIAL PRIMARY KEY,
    field_id INT NOT NULL REFERENCES crop_management.fields(field_id),
    crop_type_id INT NOT NULL REFERENCES crop_management.crop_types(crop_type_id),
    harvest_date DATE NOT NULL,
    quantity NUMERIC(12,2) NOT NULL,
    unit_type VARCHAR(20) NOT NULL,
    yield_bushels NUMERIC(12,2) GENERATED ALWAYS AS (
        crop_management.calculate_yield_bushels(quantity, unit_type)
    ) STORED,
    moisture_content NUMERIC(5,2),
    grade_code VARCHAR(10),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_harvests_field ON crop_management.harvests(field_id);
CREATE INDEX idx_harvests_date ON crop_management.harvests(harvest_date);

-- Create view (same logic as SQL Server)
CREATE VIEW crop_management.vw_field_productivity AS
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
