-- URBAN RETAIL CO. INVENTORY OPTIMIZATION SOLUTION

-- 1. CORE INVENTORY METRICS
-- Inventory Health Dashboard
SELECT 
    p.Category,
    s.Region,
    COUNT(*) AS product_count,
    SUM(i.Inventory_Level * p.Cost_Price) AS inventory_value,
    SUM(i.Units_Sold) AS total_sales,
    ROUND(SUM(i.Units_Sold)/NULLIF(SUM(i.Inventory_Level),0),2) AS turnover_rate,
    SUM(CASE WHEN i.Inventory_Level < i.Demand_Forecast THEN 1 ELSE 0 END) AS understocked_items,
    SUM(CASE WHEN i.Inventory_Level > (i.Demand_Forecast * 1.5) THEN 1 ELSE 0 END) AS overstocked_items
FROM inventory_facts i
JOIN products p ON i.Product_ID = p.Product_ID
JOIN stores s ON i.Store_ID = s.Store_ID
WHERE i.Date = (SELECT MAX(Date) FROM inventory_facts)
GROUP BY p.Category, s.Region
ORDER BY understocked_items DESC;

-- 2. DEMAND & FORECAST ANALYSIS
-- Forecast Accuracy Report
SELECT 
    p.Category,
    ROUND(AVG(ABS(i.Demand_Forecast - i.Units_Sold)),2) AS avg_forecast_error,
    ROUND(AVG(i.Demand_Forecast),2) AS avg_forecast,
    ROUND(AVG(i.Units_Sold),2) AS avg_actual,
    ROUND((AVG(ABS(i.Demand_Forecast - i.Units_Sold))/NULLIF(AVG(i.Demand_Forecast),0)*100,2) AS error_pct
FROM inventory_facts i
JOIN products p ON i.Product_ID = p.Product_ID
GROUP BY p.Category
ORDER BY avg_forecast_error DESC;

-- 3. REORDER POINT OPTIMIZATION
-- Dynamic Reorder Recommendations
WITH sales_trends AS (
    SELECT 
        Store_ID,
        Product_ID,
        AVG(Units_Sold) AS avg_daily_sales,
        STDDEV(Units_Sold) AS sales_volatility,
        AVG(DATEDIFF(Date, LAG(Date) OVER (PARTITION BY Store_ID, Product_ID ORDER BY Date))) AS avg_lead_time
    FROM inventory_facts
    WHERE Date >= DATE_SUB((SELECT MAX(Date) FROM inventory_facts), INTERVAL 90 DAY)
    GROUP BY Store_ID, Product_ID
)
SELECT 
    s.Store_ID,
    s.Region,
    p.Product_ID,
    p.Category,
    t.avg_daily_sales,
    ROUND(t.avg_daily_sales * 7,2) AS base_reorder_point,
    ROUND(t.avg_daily_sales * 7 + (t.sales_volatility * 2),2) AS safety_stock_reorder,
    ROUND(t.avg_lead_time,1) AS avg_lead_time_days
FROM sales_trends t
JOIN products p ON t.Product_ID = p.Product_ID
JOIN stores s ON t.Store_ID = s.Store_ID
ORDER BY s.Region, p.Category;

-- 4. SEASONAL TRENDS
-- Seasonal Demand Analysis
SELECT 
    e.Seasonality,
    p.Category,
    ROUND(AVG(i.Units_Sold),2) AS avg_daily_sales,
    ROUND(AVG(i.Units_Sold * i.Price),2) AS avg_daily_revenue,
    ROUND((AVG(i.Units_Sold) - 
          LAG(AVG(i.Units_Sold)) OVER (PARTITION BY p.Category ORDER BY e.Seasonality)) / 
          NULLIF(LAG(AVG(i.Units_Sold)) OVER (PARTITION BY p.Category ORDER BY e.Seasonality),0)*100,2) AS growth_pct
FROM inventory_facts i
JOIN products p ON i.Product_ID = p.Product_ID
JOIN environment_facts e ON i.Date = e.Date AND i.Store_ID = e.Store_ID
GROUP BY e.Seasonality, p.Category
ORDER BY p.Category, e.Seasonality;

-- 5. PROMOTION EFFECTIVENESS
-- Promotion Impact Report
SELECT 
    p.Category,
    e.Holiday_Promotion,
    COUNT(DISTINCT i.Date) AS promo_days,
    ROUND(AVG(i.Units_Sold),2) AS avg_units,
    ROUND(AVG(i.Units_Sold * i.Price),2) AS avg_revenue,
    ROUND(AVG(i.Discount),2) AS avg_discount,
    ROUND((AVG(CASE WHEN e.Holiday_Promotion = 1 THEN i.Units_Sold ELSE NULL END) - 
          AVG(CASE WHEN e.Holiday_Promotion = 0 THEN i.Units_Sold ELSE NULL END)) / 
          NULLIF(AVG(CASE WHEN e.Holiday_Promotion = 0 THEN i.Units_Sold ELSE NULL END),0)*100,2) AS lift_pct
FROM inventory_facts i
JOIN products p ON i.Product_ID = p.Product_ID
JOIN environment_facts e ON i.Date = e.Date AND i.Store_ID = e.Store_ID
GROUP BY p.Category, e.Holiday_Promotion
ORDER BY p.Category, lift_pct DESC;

-- 6. DATA QUALITY CHECKS
-- Data Completeness Verification
SELECT 
    'inventory_facts' AS table_name,
    COUNT(*) AS row_count,
    MIN(Date) AS earliest_date,
    MAX(Date) AS latest_date,
    COUNT(DISTINCT Product_ID) AS unique_products,
    COUNT(DISTINCT Store_ID) AS unique_stores
FROM inventory_facts
UNION ALL
SELECT 
    'products',
    COUNT(*),
    NULL,
    NULL,
    COUNT(DISTINCT Product_ID),
    NULL
FROM products
UNION ALL
SELECT 
    'stores',
    COUNT(*),
    NULL,
    NULL,
    NULL,
    COUNT(DISTINCT Store_ID)
FROM stores
UNION ALL
SELECT 
    'environment_facts',
    COUNT(*),
    MIN(Date),
    MAX(Date),
    NULL,
    COUNT(DISTINCT Store_ID)
FROM environment_facts;