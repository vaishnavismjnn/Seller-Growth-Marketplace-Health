create database Sellers;
use Sellers;
#Seller-level GMV and take rate
SELECT
    seller_id,
    SUM(gmv) AS total_gmv,
    SUM(commission) AS total_commission,
    ROUND(
        100.0 * SUM(commission) / NULLIF(SUM(gmv), 0),
        4
    ) AS take_rate_pct
FROM Orders
GROUP BY seller_id
ORDER BY total_gmv DESC;

#Rank sellers by GMV and calculate cumulative concentration
WITH seller_gmv AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv
    FROM Orders
    GROUP BY seller_id
),
ranked_sellers AS (
    SELECT
        seller_id,
        total_gmv,
        RANK() OVER (ORDER BY total_gmv DESC) AS gmv_rank,
        SUM(total_gmv) OVER (
            ORDER BY total_gmv DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_gmv,
        SUM(total_gmv) OVER () AS marketplace_gmv
    FROM seller_gmv
)
SELECT
    seller_id,
    total_gmv,
    gmv_rank,
    ROUND(100.0 * cumulative_gmv / NULLIF(marketplace_gmv, 0), 2)
        AS cumulative_gmv_share_pct
FROM ranked_sellers
ORDER BY gmv_rank;

#Calculate seller contribution proxy
SELECT
    seller_id,
    SUM(commission) AS total_commission,
    SUM(penalty) AS total_penalty,
    SUM(incentive) AS total_incentive,
    SUM(commission) + SUM(penalty) - SUM(incentive)
        AS contribution_proxy
FROM Seller_Payout
GROUP BY seller_id
ORDER BY contribution_proxy DESC;

#Build seller-level marketplace health using five tables
WITH order_summary AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv,
        SUM(commission) AS total_commission,
        COUNT(*) AS order_records
    FROM Orders
    GROUP BY seller_id
),
performance_summary AS (
    SELECT
        seller_id,
        AVG(sla_rate) AS avg_sla_rate,
        AVG(cancel_rate) AS avg_cancel_rate,
        AVG(return_rate) AS avg_return_rate,
        AVG(fill_rate) AS avg_fill_rate
    FROM Sellers_Performance
    GROUP BY seller_id
),
payout_summary AS (
    SELECT
        seller_id,
        SUM(penalty) AS total_penalty,
        SUM(incentive) AS total_incentive
    FROM Seller_Payout
    GROUP BY seller_id
),
product_summary AS (
    SELECT
        seller_id,
        COUNT(DISTINCT product_id) AS product_count
    FROM Sellers_Products
    GROUP BY seller_id
)
SELECT
    s.seller_id,
    s.city,
    s.tier,
    COALESCE(o.total_gmv, 0) AS total_gmv,
    COALESCE(o.total_commission, 0) AS total_commission,
    COALESCE(o.order_records, 0) AS order_records,
    p.avg_sla_rate,
    p.avg_cancel_rate,
    p.avg_return_rate,
    p.avg_fill_rate,
    COALESCE(pay.total_penalty, 0) AS total_penalty,
    COALESCE(pay.total_incentive, 0) AS total_incentive,
    COALESCE(pr.product_count, 0) AS product_count
FROM Sellers s
LEFT JOIN order_summary o ON s.seller_id = o.seller_id
LEFT JOIN performance_summary p ON s.seller_id = p.seller_id
LEFT JOIN payout_summary pay ON s.seller_id = pay.seller_id
LEFT JOIN product_summary pr ON s.seller_id = pr.seller_id;

#Identify high-GMV sellers
WITH seller_gmv AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv
    FROM Orders
    GROUP BY seller_id
)
SELECT
    seller_id,
    total_gmv,
    CASE
        WHEN gmv_rank <= 50 THEN 'High GMV'
        WHEN gmv_rank <= 500 THEN 'Medium GMV'
        ELSE 'Low GMV'
    END AS seller_segment
FROM (
    SELECT
        seller_id,
        total_gmv,
        RANK() OVER (ORDER BY total_gmv DESC) AS gmv_rank
    FROM seller_gmv
) ranked
ORDER BY total_gmv DESC;

#Compare incentive recipients and non-recipients
WITH seller_incentives AS (
    SELECT
        seller_id,
        SUM(incentive) AS total_incentive
    FROM Seller_Payout
    GROUP BY seller_id
),
seller_gmv AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv
    FROM Orders
    GROUP BY seller_id
)
SELECT
    CASE
        WHEN COALESCE(i.total_incentive, 0) > 0
            THEN 'Incentive Recipient'
        ELSE 'Non-Recipient'
    END AS incentive_group,
    COUNT(*) AS seller_count,
    ROUND(AVG(COALESCE(g.total_gmv, 0)), 2) AS avg_gmv
FROM Sellers s
LEFT JOIN seller_incentives i ON s.seller_id = i.seller_id
LEFT JOIN seller_gmv g ON s.seller_id = g.seller_id
GROUP BY incentive_group;

#Calculate seller-program effectiveness
SELECT
    Grocery AS program_category,
    SUM(cost) AS total_cost,
    SUM(incremental_gmv) AS total_incremental_gmv,
    ROUND(
        SUM(incremental_gmv) / NULLIF(SUM(cost), 0),
        4
    ) AS incremental_gmv_per_rupee
FROM Seller_Programs
GROUP BY Grocery
ORDER BY incremental_gmv_per_rupee DESC;

#Create preliminary seller risk tiers
WITH seller_gmv AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv
    FROM Orders
    GROUP BY seller_id
),
seller_quality AS (
    SELECT
        seller_id,
        AVG(sla_rate) AS avg_sla_rate,
        AVG(cancel_rate) AS avg_cancel_rate,
        AVG(return_rate) AS avg_return_rate
    FROM Sellers_Performance
    GROUP BY seller_id
),
ranked AS (
    SELECT
        g.seller_id,
        g.total_gmv,
        q.avg_sla_rate,
        q.avg_cancel_rate,
        q.avg_return_rate,
        RANK() OVER (ORDER BY g.total_gmv DESC) AS gmv_rank
    FROM seller_gmv g
    LEFT JOIN seller_quality q ON g.seller_id = q.seller_id
)
SELECT
    seller_id,
    total_gmv,
    gmv_rank,
    CASE
        WHEN avg_sla_rate IS NULL
          OR avg_cancel_rate IS NULL
          OR avg_return_rate IS NULL
            THEN 'Needs Validation'
        WHEN gmv_rank <= 50
            THEN 'High GMV - Quality Review Required'
        ELSE 'Standard Review'
    END AS seller_risk_tier
FROM ranked
ORDER BY gmv_rank;