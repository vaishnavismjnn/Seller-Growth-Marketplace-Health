#Marketplace Health This view combines seller profiles, order totals, payout summaries, and product coverage
CREATE OR REPLACE VIEW vw_seller_health AS
WITH order_summary AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv,
        SUM(commission) AS total_commission,
        COUNT(*) AS order_records
    FROM Orders
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
    ROUND(
        100 * COALESCE(o.total_commission, 0) /
        NULLIF(o.total_gmv, 0), 4
    ) AS take_rate_pct,
    COALESCE(o.order_records, 0) AS order_records,
    COALESCE(p.total_penalty, 0) AS total_penalty,
    COALESCE(p.total_incentive, 0) AS total_incentive,
    COALESCE(pr.product_count, 0) AS product_count
FROM Sellers s
LEFT JOIN order_summary o ON s.seller_id = o.seller_id
LEFT JOIN payout_summary p ON s.seller_id = p.seller_id
LEFT JOIN product_summary pr ON s.seller_id = pr.seller_id;
select * from vw_seller_health ;

#Seller Concentration This view ranks sellers and calculates their cumulative share of marketplace GMV.
CREATE OR REPLACE VIEW vw_seller_concentration AS
WITH seller_gmv AS (
    SELECT
        seller_id,
        SUM(gmv) AS total_gmv
    FROM Orders
    GROUP BY seller_id
),
ranked AS (
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
    ROUND(
        100 * cumulative_gmv / NULLIF(marketplace_gmv, 0), 2
    ) AS cumulative_gmv_share_pct,
    CASE
        WHEN gmv_rank <= 10 THEN 'Top 10'
        WHEN gmv_rank <= 50 THEN 'Top 50'
        ELSE 'Other Sellers'
    END AS concentration_group
FROM ranked;
select * from vw_seller_concentration;

#Seller Quality & CX
CREATE OR REPLACE VIEW vw_seller_quality AS
SELECT
    seller_id,
    AVG(sla_rate) AS avg_sla_rate,
    AVG(fill_rate) AS avg_fill_rate,
    AVG(cancel_rate) AS avg_cancel_rate,
    AVG(return_rate) AS avg_return_rate,
    AVG(rating) AS avg_rating
FROM Sellers_Performance
GROUP BY seller_id;
select * from vw_seller_quality;

#Incentive ROI
CREATE OR REPLACE VIEW vw_incentive_roi AS
SELECT
    `Grocery` AS program_category,
    COUNT(*) AS program_records,
    SUM(cost) AS total_cost,
    SUM(incremental_gmv) AS total_incremental_gmv,
    ROUND(
        SUM(incremental_gmv) / NULLIF(SUM(cost), 0),
        4
    ) AS incremental_gmv_per_rupee
FROM Seller_Programs
GROUP BY `Grocery`;
select * from vw_incentive_roi ;

CREATE OR REPLACE VIEW vw_seller_tickets AS
SELECT
    seller_id,
    COUNT(*) AS ticket_count,
    COUNT(DISTINCT ticket_id) AS unique_ticket_count,
    AVG(resolution_hours) AS avg_resolution_time
FROM Sellers_Tickets
GROUP BY seller_id;
select * from vw_seller_tickets;

CREATE OR REPLACE VIEW vw_category_opportunity AS
SELECT
    city,
    AVG(demand_index) AS avg_demand_index
FROM Category_Market
GROUP BY city;
select * from  vw_category_opportunity;