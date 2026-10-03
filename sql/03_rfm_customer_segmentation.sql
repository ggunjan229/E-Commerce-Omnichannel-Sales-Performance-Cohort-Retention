-- ============================================================
-- DESCRIPTION: Ranks customers into 5 quintiles (NTILE) and clusters into 6 cohorts
-- ============================================================

WITH dataset_max_date AS (
    SELECT MAX(order_purchase_timestamp) AS reference_date FROM fact_orders
),
rfm_base AS (
    SELECT 
        c.customer_unique_id,
        EXTRACT(DAY FROM ((SELECT reference_date FROM dataset_max_date) - MAX(o.order_purchase_timestamp)))::int AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(i.price + i.freight_value) AS monetary_value
    FROM fact_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    JOIN fact_order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary_value,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score
    FROM rfm_base
),
rfm_segmented AS (
    SELECT 
        customer_unique_id,
        recency_days,
        frequency,
        monetary_value,
        r_score,
        f_score,
        m_score,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score < 2 THEN 'Recent New Customers'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk / Churning'
            WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost Customers'
            ELSE 'Promising'
        END AS segment_name
    FROM rfm_scored
)
SELECT 
    segment_name,
    COUNT(customer_unique_id) AS total_customers,
    ROUND(COUNT(customer_unique_id) * 100.0 / SUM(COUNT(customer_unique_id)) OVER(), 2) AS segment_share_pct,
    ROUND(AVG(recency_days), 1) AS avg_recency_days,
    ROUND(AVG(frequency), 2) AS avg_order_frequency,
    ROUND(AVG(monetary_value), 2) AS avg_monetary_spend_brl,
    ROUND(SUM(monetary_value), 2) AS total_segment_revenue_brl
FROM rfm_segmented
GROUP BY segment_name
ORDER BY total_segment_revenue_brl DESC;

/* 
================================================================
POSTGRESQL EXECUTION RESULT:
----------------------------------------------------------------
 segment_name         | total_customers | segment_share_pct | avg_recency_days | avg_order_frequency | avg_monetary_spend_brl | total_segment_revenue_brl 
----------------------+-----------------+-------------------+------------------+---------------------+------------------------+---------------------------
 At Risk / Churning   | 21886           | 23.44             | 442.0            | 1.05                | 242.30                 | 5302889.98
 Champions            | 14855           | 15.91             | 139.2            | 1.08                | 309.34                 | 4595278.36
 Loyal Customers      | 19273           | 20.64             | 214.0            | 1.05                | 179.51                 | 3459686.61
 Promising            | 14517           | 15.55             | 204.6            | 1.00                | 62.11                  | 901619.88
 Lost Customers       | 15458           | 16.56             | 443.7            | 1.00                | 55.86                  | 863459.72
 Recent New Customers | 7369            | 7.89              | 137.6            | 1.00                | 40.28                  | 296839.20
(6 rows affected)
================================================================
KEY BUSINESS TAKEAWAYS:
1. Champions drive the highest average spend (R$ 309.34), accounting for over R$ 4.59M in gross sales.
2. At-Risk / Churning represents the single largest revenue pool (R$ 5.30M) with an average recency of 442 days, marking it as the primary win-back candidate.
3. Order frequency sits between 1.00 and 1.08 across all tiers, showing that repeat buying in this marketplace is rare and requires structured post-purchase retention loops.
*/