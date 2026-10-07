"""
Verification Script for SQL Dimensional Report
Runs queries against an in-memory database and prints formatted tabular output.
"""
import sqlite3

def run_verification():
    conn = sqlite3.connect(":memory:")
    cursor = conn.cursor()

    # Enable foreign keys in SQLite
    cursor.execute("PRAGMA foreign_keys = ON;")

    # 1. Execute schema.sql
    with open("schema.sql", "r", encoding="utf-8") as f:
        schema_sql = f.read()
    cursor.executescript(schema_sql)
    print(" Schema initialized successfully.")

    # 2. Execute data.sql
    with open("data.sql", "r", encoding="utf-8") as f:
        data_sql = f.read()
    cursor.executescript(data_sql)
    print(" Sample data loaded successfully.\n")

    def print_table(title, headers, rows):
        print("=" * 80)
        print(f" {title}")
        print("=" * 80)
        col_widths = [len(h) for h in headers]
        for row in rows:
            for i, val in enumerate(row):
                val_str = str(val) if val is not None else "NULL"
                col_widths[i] = max(col_widths[i], len(val_str))
        
        header_row = " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers))
        sep_row = "-+-".join("-" * col_widths[i] for i in range(len(headers)))
        print(header_row)
        print(sep_row)
        for row in rows:
            print(" | ".join((str(val) if val is not None else "NULL").ljust(col_widths[i]) for i, val in enumerate(row)))
        print(f"Total rows: {len(rows)}\n")

    # REPORT 1: Star Schema Verification (First 8 rows)
    q1 = """
    SELECT 
        f.sales_key,
        d.full_date,
        p.product_name,
        c.customer_name,
        r.region_name,
        f.quantity,
        printf('$%.2f', f.unit_price) AS unit_price,
        printf('$%.2f', f.discount_amount) AS discount,
        printf('$%.2f', f.total_amount) AS total_amount
    FROM fact_sales f
    JOIN dim_date d ON f.date_key = d.date_key
    JOIN dim_product p ON f.product_key = p.product_key
    JOIN dim_customer c ON f.customer_key = c.customer_key
    JOIN dim_region r ON f.region_key = r.region_key
    ORDER BY f.sales_key
    LIMIT 8;
    """
    cursor.execute(q1)
    print_table("REPORT 1: Star Schema Join (Sample First 8 Rows)", 
                ["Sales Key", "Date", "Product", "Customer", "Region", "Qty", "Unit Price", "Discount", "Total Amount"],
                cursor.fetchall())

    # REPORT 2.1: Product Rankings (RANK, DENSE_RANK, ROW_NUMBER)
    q2_1 = """
    SELECT 
        p.product_id,
        p.product_name,
        p.category,
        SUM(f.quantity) AS total_units,
        printf('$%.2f', SUM(f.total_amount)) AS total_revenue,
        ROW_NUMBER() OVER (ORDER BY SUM(f.total_amount) DESC) AS row_num,
        RANK() OVER (ORDER BY SUM(f.total_amount) DESC) AS rank_pos,
        DENSE_RANK() OVER (ORDER BY SUM(f.total_amount) DESC) AS dense_rank_pos
    FROM fact_sales f
    JOIN dim_product p ON f.product_key = p.product_key
    GROUP BY p.product_id, p.product_name, p.category
    ORDER BY SUM(f.total_amount) DESC;
    """
    cursor.execute(q2_1)
    print_table("REPORT 2.1: Product Revenue Rankings (ROW_NUMBER, RANK, DENSE_RANK)",
                ["Product ID", "Product Name", "Category", "Units Sold", "Total Revenue", "ROW_NUM", "RANK", "DENSE_RANK"],
                cursor.fetchall())

    # REPORT 2.2: Partitioned Customer Rankings per Region
    q2_2 = """
    SELECT 
        r.region_name,
        c.customer_name,
        c.customer_segment,
        printf('$%.2f', SUM(f.total_amount)) AS total_spent,
        DENSE_RANK() OVER (
            PARTITION BY r.region_name 
            ORDER BY SUM(f.total_amount) DESC
        ) AS regional_rank
    FROM fact_sales f
    JOIN dim_region r ON f.region_key = r.region_key
    JOIN dim_customer c ON f.customer_key = c.customer_key
    GROUP BY r.region_name, c.customer_name, c.customer_segment
    ORDER BY r.region_name, regional_rank;
    """
    cursor.execute(q2_2)
    print_table("REPORT 2.2: Top Customers Partitioned By Region",
                ["Region", "Customer Name", "Segment", "Total Spent", "Regional Rank"],
                cursor.fetchall())

    # REPORT 3: CTE-based Month-over-Month (MoM) Growth Analysis
    q3 = """
    WITH MonthlyRevenueCTE AS (
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
        SELECT 
            sales_year,
            sales_month,
            month_name,
            current_month_sales,
            total_orders,
            LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month) AS previous_month_sales,
            current_month_sales - LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month) AS mom_growth_amount,
            ROUND(
                ((current_month_sales - LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month)) 
                * 100.0 / LAG(current_month_sales, 1) OVER (ORDER BY sales_year, sales_month)), 
                2
            ) AS mom_growth_percentage
        FROM MonthlyRevenueCTE
    )
    SELECT 
        sales_year,
        month_name,
        printf('$%.2f', current_month_sales) AS current_sales,
        CASE WHEN previous_month_sales IS NULL THEN 'N/A' ELSE printf('$%.2f', previous_month_sales) END AS prev_sales,
        CASE WHEN mom_growth_amount IS NULL THEN 'N/A' ELSE printf('$%.2f', mom_growth_amount) END AS mom_growth,
        CASE WHEN mom_growth_percentage IS NULL THEN 'N/A' ELSE printf('%.2f%%', mom_growth_percentage) END AS mom_growth_pct,
        CASE 
            WHEN previous_month_sales IS NULL THEN 'Baseline'
            WHEN mom_growth_amount > 0 THEN 'Growth (+)'
            WHEN mom_growth_amount < 0 THEN 'Decline (-)'
            ELSE 'Flat'
        END AS performance_trend
    FROM MoMCalculationCTE
    ORDER BY sales_year, sales_month;
    """
    cursor.execute(q3)
    print_table("REPORT 3: Month-over-Month (MoM) Sales Performance Report (with CTE & LAG)",
                ["Year", "Month", "Current Month Sales", "Prev Month Sales", "MoM Growth ($)", "MoM Growth (%)", "Trend"],
                cursor.fetchall())

    # REPORT 4: Subtotals and Grand Totals (Rollup Demonstration)
    # Using standard grouping set equivalent for SQLite
    q4 = """
    -- Detailed Category Breakdown by Region
    SELECT 
        r.region_name AS region_name,
        p.category AS product_category,
        SUM(f.quantity) AS total_units,
        printf('$%.2f', SUM(f.total_amount)) AS total_revenue
    FROM fact_sales f
    JOIN dim_region r ON f.region_key = r.region_key
    JOIN dim_product p ON f.product_key = p.product_key
    GROUP BY r.region_name, p.category

    UNION ALL

    -- Subtotal per Region
    SELECT 
        r.region_name || ' (Subtotal)',
        '--- ALL CATEGORIES ---',
        SUM(f.quantity),
        printf('$%.2f', SUM(f.total_amount))
    FROM fact_sales f
    JOIN dim_region r ON f.region_key = r.region_key
    GROUP BY r.region_name

    UNION ALL

    -- Grand Total
    SELECT 
        '*** GRAND TOTAL ***',
        '*** ALL CATEGORIES ***',
        SUM(f.quantity),
        printf('$%.2f', SUM(f.total_amount))
    FROM fact_sales f
    ORDER BY 1, 2;
    """
    cursor.execute(q4)
    print_table("REPORT 4: Multi-Level Aggregation (Subtotals and Grand Totals)",
                ["Region", "Category", "Units Sold", "Total Revenue"],
                cursor.fetchall())

    # REPORT 5: EXPLAIN QUERY PLAN
    q5 = """
    EXPLAIN QUERY PLAN
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
    """
    cursor.execute(q5)
    print_table("REPORT 5: EXPLAIN Query Execution Plan",
                ["ID", "Parent", "NotUsed", "Detail / Operation"],
                cursor.fetchall())

    conn.close()

if __name__ == "__main__":
    run_verification()
