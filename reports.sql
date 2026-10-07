-- ============================================================================
-- SQL Dimensional Report - Week 5 Project
-- Analytical Reporting Queries
-- ============================================================================

-- ============================================================================
-- REPORT 1: STAR SCHEMA VERIFICATION (Base Dimensional Join)
-- ============================================================================
-- Description: Joins the central fact table with all surrounding dimension tables
-- to present a denormalized, business-ready transactional view.

SELECT 
    f.sales_key,
    d.full_date,
    d.month_name,
    d.year_num,
    p.product_name,
    p.category,
    c.customer_name,
    c.customer_segment,
    r.region_name,
    f.quantity,
    f.unit_price,
    f.discount_amount,
    f.total_amount
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_product p ON f.product_key = p.product_key
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_region r ON f.region_key = r.region_key
ORDER BY f.sales_key;


-- ============================================================================
-- REPORT 2: WINDOW FUNCTION RANKINGS
-- ============================================================================
-- Requirement 3: Use RANK(), DENSE_RANK(), and ROW_NUMBER() on sales performance.

-- ----------------------------------------------------------------------------
-- 2.1: Overall Product Ranking by Total Revenue
-- Demonstrates differences between ROW_NUMBER, RANK, and DENSE_RANK
-- ----------------------------------------------------------------------------
SELECT 
    p.product_id,
    p.product_name,
    p.category,
    SUM(f.quantity) AS total_units_sold,
    SUM(f.total_amount) AS total_revenue,
    ROW_NUMBER() OVER (ORDER BY SUM(f.total_amount) DESC) AS row_num,
    RANK() OVER (ORDER BY SUM(f.total_amount) DESC) AS rank_pos,
    DENSE_RANK() OVER (ORDER BY SUM(f.total_amount) DESC) AS dense_rank_pos
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------
-- 2.2: Partitioned Ranking - Top Customers Within Each Region
-- Uses DENSE_RANK() with PARTITION BY to rank customers locally per region
-- ----------------------------------------------------------------------------
SELECT 
    r.region_name,
    c.customer_name,
    c.customer_segment,
    SUM(f.total_amount) AS total_spent,
    DENSE_RANK() OVER (
        PARTITION BY r.region_name 
        ORDER BY SUM(f.total_amount) DESC
    ) AS regional_customer_rank
FROM fact_sales f
JOIN dim_region r ON f.region_key = r.region_key
JOIN dim_customer c ON f.customer_key = c.customer_key
GROUP BY r.region_name, c.customer_name, c.customer_segment
ORDER BY r.region_name, regional_customer_rank;


-- ============================================================================
-- REPORT 3: CTE-BASED MONTH-OVER-MONTH (MoM) SALES ANALYSIS
-- ============================================================================
-- Requirement 4: Common Table Expression (CTE) calculating monthly totals,
-- previous month comparison via LAG(), and percentage growth metrics.

WITH MonthlyRevenueCTE AS (
    -- Step 1: Aggregate sales revenue and order count per calendar month
    SELECT 
        d.year_num AS sales_year,
        d.month_num AS sales_month,
        d.month_name AS month_name,
        SUM(f.total_amount) AS current_month_sales,
        COUNT(DISTINCT f.order_id) AS total_orders
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    GROUP BY d.year_num, d.month_num, d.month_name
),
MoMCalculationCTE AS (
    -- Step 2: Use LAG() to fetch previous month's revenue and compute variance
    SELECT 
        sales_year,
        sales_month,
        month_name,
        current_month_sales,
        total_orders,
        LAG(current_month_sales, 1) OVER (
            ORDER BY sales_year, sales_month
        ) AS previous_month_sales,
        current_month_sales - LAG(current_month_sales, 1) OVER (
            ORDER BY sales_year, sales_month
        ) AS mom_growth_amount,
        ROUND(
            (
                (current_month_sales - LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month)) 
                / LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month)
            ) * 100.0, 
            2
        ) AS mom_growth_percentage
    FROM MonthlyRevenueCTE
)
-- Step 3: Present clean output with business trend indicator
SELECT 
    sales_year,
    sales_month,
    month_name,
    current_month_sales,
    COALESCE(previous_month_sales, 0.00) AS previous_month_sales,
    COALESCE(mom_growth_amount, 0.00) AS mom_growth_amount,
    COALESCE(mom_growth_percentage, 0.00) AS mom_growth_pct,
    CASE 
        WHEN previous_month_sales IS NULL THEN 'Baseline Month'
        WHEN mom_growth_amount > 0 THEN 'Growth (+)'
        WHEN mom_growth_amount < 0 THEN 'Decline (-)'
        ELSE 'Flat'
    END AS performance_trend
FROM MoMCalculationCTE
ORDER BY sales_year, sales_month;


-- ============================================================================
-- REPORT 4: MULTI-LEVEL AGGREGATION USING ROLLUP
-- ============================================================================
-- Requirement 5: Generate subtotals and grand totals from the sales data.

-- ----------------------------------------------------------------------------
-- 4.1: Sales Subtotals and Grand Totals by Region and Product Category
-- Standard ANSI SQL syntax: GROUP BY ROLLUP(region_name, category)
-- (Produces: Region x Category breakdown -> Region Subtotal -> Grand Total)
-- ----------------------------------------------------------------------------
SELECT 
    COALESCE(r.region_name, '--> ALL REGIONS (Grand Total)') AS region_name,
    COALESCE(p.category, '--> All Categories (Subtotal)') AS product_category,
    SUM(f.quantity) AS total_units_sold,
    SUM(f.total_amount) AS total_revenue
FROM fact_sales f
JOIN dim_region r ON f.region_key = r.region_key
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY ROLLUP (r.region_name, p.category)
ORDER BY r.region_name NULLS LAST, p.category NULLS LAST;

-- Note for MySQL 8 users: The equivalent MySQL syntax is:
-- SELECT 
--     COALESCE(r.region_name, '--> ALL REGIONS (Grand Total)') AS region_name,
--     COALESCE(p.category, '--> All Categories (Subtotal)') AS product_category,
--     SUM(f.quantity) AS total_units_sold,
--     SUM(f.total_amount) AS total_revenue
-- FROM fact_sales f
-- JOIN dim_region r ON f.region_key = r.region_key
-- JOIN dim_product p ON f.product_key = p.product_key
-- GROUP BY r.region_name, p.category WITH ROLLUP;


-- ----------------------------------------------------------------------------
-- 4.2: Time Hierarchy Rollup (Year -> Quarter -> Month)
-- Generates subtotals per quarter, subtotals per year, and grand total
-- ----------------------------------------------------------------------------
SELECT 
    COALESCE(CAST(d.year_num AS VARCHAR(10)), 'All Years') AS sales_year,
    COALESCE(CAST(d.quarter_num AS VARCHAR(10)), 'All Quarters') AS sales_quarter,
    COALESCE(d.month_name, 'All Months') AS sales_month,
    SUM(f.total_amount) AS total_revenue
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY ROLLUP (d.year_num, d.quarter_num, d.month_name);


-- ============================================================================
-- REPORT 5: QUERY PLAN & EXPLAIN OPTIMIZATION DEMONSTRATION
-- ============================================================================
-- Requirement 6: Use EXPLAIN to inspect query execution plan and optimization.

-- ----------------------------------------------------------------------------
-- 5.1: Explain Plan on Multi-Table Star Schema Join
-- Shows how the query planner utilizes Foreign Key Indexes (idx_fact_sales_*)
-- ----------------------------------------------------------------------------
EXPLAIN
SELECT 
    d.month_name,
    p.category,
    r.region_name,
    SUM(f.total_amount) AS total_revenue
FROM fact_sales f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_product p ON f.product_key = p.product_key
JOIN dim_region r ON f.region_key = r.region_key
WHERE d.year_num = 2024 AND r.region_name = 'West'
GROUP BY d.month_name, p.category, r.region_name;

-- ----------------------------------------------------------------------------
-- 5.2: Explain Plan on Product Filtering Query
-- ----------------------------------------------------------------------------
EXPLAIN
SELECT 
    f.order_id,
    p.product_name,
    f.total_amount
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
WHERE f.product_key = 101;
