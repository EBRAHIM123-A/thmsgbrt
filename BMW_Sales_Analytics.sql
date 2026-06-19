-- =============================================================
-- BMW GROUP SALES ANALYTICS — COMPLETE SQL SOLUTION
-- Portfolio Project | Senior Data Analyst
-- Database: PostgreSQL / SQL Server / MySQL compatible
-- =============================================================

-- ─── SCHEMA ─────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS bmw_analytics;

-- ─── DIMENSION TABLES (Star Schema) ─────────────────────────

CREATE TABLE bmw_analytics.dim_date (
    date_id     INT          PRIMARY KEY,
    year        SMALLINT     NOT NULL,
    month       TINYINT      NOT NULL,
    quarter     TINYINT      NOT NULL,
    year_month  VARCHAR(7)   NOT NULL  -- 'YYYY-MM'
);

CREATE TABLE bmw_analytics.dim_region (
    region_id   TINYINT      PRIMARY KEY,
    region_name VARCHAR(50)  NOT NULL,   -- Europe, China, USA, RestOfWorld
    region_zone VARCHAR(30)              -- EMEA, APAC, Americas, Global
);

CREATE TABLE bmw_analytics.dim_model (
    model_id       TINYINT       PRIMARY KEY,
    model_name     VARCHAR(30)   NOT NULL,   -- 3 Series, 5 Series, X3, X5, X7, i4, iX, MINI
    vehicle_type   VARCHAR(20)   NOT NULL,   -- Sedan, SUV, Electric, Compact
    segment        VARCHAR(20),              -- Entry Premium, Mid Premium, Luxury, EV
    base_price_eur DECIMAL(10,2)
);

-- ─── FACT TABLE ──────────────────────────────────────────────

CREATE TABLE bmw_analytics.fact_sales (
    sale_id          BIGINT        PRIMARY KEY AUTO_INCREMENT,
    date_id          INT           NOT NULL REFERENCES bmw_analytics.dim_date(date_id),
    region_id        TINYINT       NOT NULL REFERENCES bmw_analytics.dim_region(region_id),
    model_id         TINYINT       NOT NULL REFERENCES bmw_analytics.dim_model(model_id),
    units_sold       INT           NOT NULL CHECK (units_sold >= 0),
    avg_price_eur    DECIMAL(10,2) NOT NULL,
    revenue_eur      DECIMAL(18,2) NOT NULL,
    bev_share        DECIMAL(6,4)  CHECK (bev_share BETWEEN -0.05 AND 1.0),
    premium_share    DECIMAL(6,4),
    gdp_growth       DECIMAL(6,4),
    fuel_price_index DECIMAL(6,4)
);

-- ─── DIMENSION DATA INSERTS ──────────────────────────────────

INSERT INTO bmw_analytics.dim_region (region_id, region_name, region_zone) VALUES
    (1, 'Europe',      'EMEA'),
    (2, 'China',       'APAC'),
    (3, 'USA',         'Americas'),
    (4, 'RestOfWorld', 'Global');

INSERT INTO bmw_analytics.dim_model (model_id, model_name, vehicle_type, segment, base_price_eur) VALUES
    (1, '3 Series', 'Sedan',    'Entry Premium', 44900),
    (2, '5 Series', 'Sedan',    'Mid Premium',   58900),
    (3, 'X3',       'SUV',      'Mid Premium',   55800),
    (4, 'X5',       'SUV',      'Mid Premium',   68900),
    (5, 'X7',       'SUV',      'Luxury',        92000),
    (6, 'i4',       'Electric', 'EV Mid',        65000),
    (7, 'iX',       'Electric', 'EV Luxury',     77900),
    (8, 'MINI',     'Compact',  'Entry',         34900);

-- ─── KPI ANALYTICAL QUERIES ──────────────────────────────────

-- KPI 1: Grand Total KPIs
SELECT
    ROUND(SUM(revenue_eur)/1e9, 2)          AS total_revenue_billion_eur,
    SUM(units_sold)                          AS total_units_sold,
    ROUND(AVG(avg_price_eur), 0)             AS fleet_avg_price_eur,
    ROUND(AVG(bev_share)*100, 2)             AS avg_bev_share_pct
FROM bmw_analytics.fact_sales;

-- KPI 2: Annual Revenue with YoY Growth
WITH annual AS (
    SELECT
        d.year,
        ROUND(SUM(f.revenue_eur)/1e9, 2)     AS revenue_b,
        SUM(f.units_sold)                     AS units_sold,
        ROUND(AVG(f.bev_share)*100, 2)        AS bev_pct
    FROM bmw_analytics.fact_sales f
    JOIN bmw_analytics.dim_date  d ON f.date_id = d.date_id
    GROUP BY d.year
)
SELECT
    year,
    revenue_b,
    units_sold,
    bev_pct,
    ROUND(
        (revenue_b - LAG(revenue_b) OVER (ORDER BY year))
        / LAG(revenue_b) OVER (ORDER BY year) * 100, 2
    ) AS yoy_rev_pct,
    SUM(revenue_b) OVER (ORDER BY year ROWS UNBOUNDED PRECEDING) AS cumul_rev_b
FROM annual
ORDER BY year;

-- KPI 3: Revenue by Region
SELECT
    r.region_name,
    ROUND(SUM(f.revenue_eur)/1e9, 2)               AS revenue_b,
    SUM(f.units_sold)                               AS units,
    ROUND(AVG(f.avg_price_eur), 0)                  AS avg_price,
    ROUND(
        SUM(f.revenue_eur) * 100.0
        / SUM(SUM(f.revenue_eur)) OVER(), 2
    )                                               AS rev_share_pct
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_region r ON f.region_id = r.region_id
GROUP BY r.region_name
ORDER BY revenue_b DESC;

-- KPI 4: Revenue by Model
SELECT
    m.model_name,
    m.vehicle_type,
    ROUND(SUM(f.revenue_eur)/1e9, 2)               AS revenue_b,
    SUM(f.units_sold)                               AS units,
    ROUND(AVG(f.avg_price_eur), 0)                  AS avg_price,
    ROUND(
        SUM(f.revenue_eur) * 100.0
        / SUM(SUM(f.revenue_eur)) OVER(), 2
    )                                               AS rev_share_pct
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_model m ON f.model_id = m.model_id
GROUP BY m.model_name, m.vehicle_type
ORDER BY revenue_b DESC;

-- KPI 5: BEV Adoption Trend
SELECT
    d.year,
    ROUND(AVG(f.bev_share)*100, 2)                 AS bev_pct,
    ROUND(
        (AVG(f.bev_share) - LAG(AVG(f.bev_share)) OVER (ORDER BY d.year)) * 100, 2
    )                                               AS yoy_change_pp
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_date d ON f.date_id = d.date_id
GROUP BY d.year
ORDER BY d.year;

-- KPI 6: Region × Year Revenue Pivot
SELECT
    d.year,
    ROUND(SUM(CASE WHEN r.region_name='China'       THEN f.revenue_eur END)/1e9, 2) AS china_b,
    ROUND(SUM(CASE WHEN r.region_name='Europe'      THEN f.revenue_eur END)/1e9, 2) AS europe_b,
    ROUND(SUM(CASE WHEN r.region_name='USA'         THEN f.revenue_eur END)/1e9, 2) AS usa_b,
    ROUND(SUM(CASE WHEN r.region_name='RestOfWorld' THEN f.revenue_eur END)/1e9, 2) AS row_b,
    ROUND(SUM(f.revenue_eur)/1e9, 2)                                                AS total_b
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_date   d ON f.date_id   = d.date_id
JOIN bmw_analytics.dim_region r ON f.region_id = r.region_id
GROUP BY d.year
ORDER BY d.year;

-- KPI 7: Top 3 Models per Region
WITH ranked AS (
    SELECT
        r.region_name,
        m.model_name,
        ROUND(SUM(f.revenue_eur)/1e9, 2)            AS rev_b,
        SUM(f.units_sold)                            AS units,
        ROW_NUMBER() OVER (
            PARTITION BY r.region_name
            ORDER BY SUM(f.revenue_eur) DESC
        )                                            AS rn
    FROM bmw_analytics.fact_sales f
    JOIN bmw_analytics.dim_region r ON f.region_id = r.region_id
    JOIN bmw_analytics.dim_model  m ON f.model_id  = m.model_id
    GROUP BY r.region_name, m.model_name
)
SELECT region_name, model_name, rev_b, units
FROM ranked
WHERE rn <= 3
ORDER BY region_name, rn;

-- KPI 8: Monthly Trend (Last 24 Months)
SELECT
    d.year,
    d.month,
    CONCAT(d.year, '-', LPAD(d.month, 2, '0'))      AS period,
    ROUND(SUM(f.revenue_eur)/1e9, 3)                AS revenue_b,
    SUM(f.units_sold)                               AS units
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_date d ON f.date_id = d.date_id
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- KPI 9: Electric vs Non-Electric Revenue Split
SELECT
    CASE WHEN m.vehicle_type = 'Electric' THEN 'Electric (BEV)'
         ELSE 'ICE / Hybrid' END                    AS powertrain,
    ROUND(SUM(f.revenue_eur)/1e9, 2)               AS revenue_b,
    SUM(f.units_sold)                               AS units,
    ROUND(
        SUM(f.revenue_eur) * 100.0
        / SUM(SUM(f.revenue_eur)) OVER(), 2
    )                                               AS rev_share_pct
FROM bmw_analytics.fact_sales f
JOIN bmw_analytics.dim_model m ON f.model_id = m.model_id
GROUP BY powertrain;

-- KPI 10: Revenue CAGR Calculation
WITH endpoints AS (
    SELECT
        d.year,
        SUM(f.revenue_eur) AS annual_rev
    FROM bmw_analytics.fact_sales f
    JOIN bmw_analytics.dim_date d ON f.date_id = d.date_id
    WHERE d.year IN (2018, 2025)
    GROUP BY d.year
)
SELECT
    MAX(CASE WHEN year = 2025 THEN annual_rev END) /
    MAX(CASE WHEN year = 2018 THEN annual_rev END) AS rev_ratio,
    ROUND(
        (POWER(
            MAX(CASE WHEN year = 2025 THEN annual_rev END) /
            MAX(CASE WHEN year = 2018 THEN annual_rev END),
            1.0/7
        ) - 1) * 100, 2
    )                                              AS revenue_cagr_pct
FROM endpoints;

-- ─── DATA LOADING (PostgreSQL COPY syntax) ──────────────────
-- COPY bmw_analytics.fact_sales_staging
-- FROM '/path/to/BMW_Sales_Raw.csv'
-- WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',');

-- ─── END OF SCRIPT ──────────────────────────────────────────
