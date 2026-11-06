-- =====================================================================
-- Q0. Headline numbers used in README / FINDINGS (FY2022-FY2025)
-- One row per geography: how big the data-role market is, how
-- concentrated it is, and how much of it is outside tech.
-- Technique: CTE chain; ROW_NUMBER() to rank employers within each
-- geography; FILTER to sum only the top-10 / top-1 rows.
-- =====================================================================
WITH emp AS (                       -- data LCAs per employer, per geography
    SELECT CASE WHEN is_nyc THEN 'NYC' ELSE 'Rest of U.S.' END AS geography,
           employer_parent, count(*) AS n
    FROM lca_certified
    WHERE is_data_role AND fiscal_year BETWEEN 2022 AND 2025
    GROUP BY ALL
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY geography ORDER BY n DESC) AS rk
    FROM emp
),
concentration AS (
    SELECT geography,
           sum(n)                                                  AS data_lcas,
           count(*)                                                AS sponsoring_employers,
           round(100.0 * sum(n) FILTER (WHERE rk <= 10) / sum(n), 1) AS top10_share_pct,
           round(100.0 * sum(n) FILTER (WHERE rk = 1)  / sum(n), 1)  AS top1_share_pct,
           count(*) FILTER (WHERE n = 1)                           AS employers_with_just_one_lca
    FROM ranked
    GROUP BY geography
),
mix AS (
    SELECT CASE WHEN is_nyc THEN 'NYC' ELSE 'Rest of U.S.' END            AS geography,
           count(*)                                                          AS all_lcas,
           round(100.0 * avg(is_data_role::INT), 2)                          AS data_share_of_all_pct,
           round(100.0 * avg((NOT is_tech)::INT) FILTER (WHERE is_data_role), 1) AS data_pct_non_tech,
           round(100.0 * avg((NOT is_tech AND coalesce(naics4, '') NOT IN ('5416', '5412', '5613'))::INT)
                 FILTER (WHERE is_data_role), 1)                             AS data_pct_non_tech_non_consulting,
           round(100.0 * avg((naics2 = '52')::INT) FILTER (WHERE is_data_role), 1) AS data_pct_finance_insurance
    FROM lca_certified
    WHERE fiscal_year BETWEEN 2022 AND 2025
    GROUP BY 1
)
SELECT *
FROM concentration
JOIN mix USING (geography)
ORDER BY geography;
