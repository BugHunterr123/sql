-- ============================================================================
-- SQL Dimensional Report - Week 5 Project
-- Schema Definition: Star Schema Architecture
-- ============================================================================

-- Drop existing tables if re-running (Fact table dropped first due to FK constraints)
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_region;

-- ----------------------------------------------------------------------------
-- 1. Dimension Table: dim_date
-- Stores temporal attributes for time-based dimensional analysis
-- ----------------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key INT PRIMARY KEY,
    full_date DATE NOT NULL,
    year_num INT NOT NULL,
    quarter_num INT NOT NULL,
    month_num INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    day_of_month INT NOT NULL,
    day_of_week VARCHAR(20) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 2. Dimension Table: dim_product
-- Stores product hierarchy, category, and pricing attributes
-- ----------------------------------------------------------------------------
CREATE TABLE dim_product (
    product_key INT PRIMARY KEY,
    product_id VARCHAR(20) NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    subcategory VARCHAR(50) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 3. Dimension Table: dim_customer
-- Stores customer profiles, segmentation, and geographical data
-- ----------------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_key INT PRIMARY KEY,
    customer_id VARCHAR(20) NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    customer_segment VARCHAR(50) NOT NULL,
    city VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 4. Dimension Table: dim_region
-- Stores sales territories and operational regional zones
-- ----------------------------------------------------------------------------
CREATE TABLE dim_region (
    region_key INT PRIMARY KEY,
    region_id VARCHAR(20) NOT NULL,
    region_name VARCHAR(50) NOT NULL,
    territory_manager VARCHAR(100) NOT NULL
);

-- ----------------------------------------------------------------------------
-- 5. Fact Table: fact_sales
-- Central fact table storing measurable sales transactional metrics
-- ----------------------------------------------------------------------------
CREATE TABLE fact_sales (
    sales_key INT PRIMARY KEY,
    date_key INT NOT NULL,
    product_key INT NOT NULL,
    customer_key INT NOT NULL,
    region_key INT NOT NULL,
    order_id VARCHAR(30) NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    discount_amount DECIMAL(10, 2) DEFAULT 0.00,
    total_amount DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (product_key) REFERENCES dim_product(product_key),
    FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    FOREIGN KEY (region_key) REFERENCES dim_region(region_key)
);

-- ----------------------------------------------------------------------------
-- Indexes on Foreign Keys (Recommended for Star Schema join performance)
-- ----------------------------------------------------------------------------
CREATE INDEX idx_fact_sales_date ON fact_sales(date_key);
CREATE INDEX idx_fact_sales_product ON fact_sales(product_key);
CREATE INDEX idx_fact_sales_customer ON fact_sales(customer_key);
CREATE INDEX idx_fact_sales_region ON fact_sales(region_key);
