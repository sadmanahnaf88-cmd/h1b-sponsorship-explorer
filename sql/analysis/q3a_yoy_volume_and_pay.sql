-- =====================================================================
-- Q3a. Year-over-year trend in volume and pay, by role family
-- Complete fiscal years only (FY2022-FY2025).
-- Technique: LAG() window function compares each year with the previous
-- one inside the same role family (PARTITION BY role_family). A named
-- WINDOW clause avoids repeating the window definition.
-- =====================================================================
WITH yearly AS (
    SELECT role_family, fiscal_year,
           count(*)                                             AS lcas,
           count(*) FILTER (WHERE is_nyc)                       AS nyc_lcas,
           median(annual_wage) FILTER (WHERE wage_ok_for_stats) AS median_wage,
           median(annual_wage) FILTER (WHERE wage_ok_for_stats AND is_nyc) AS nyc_median_wage
    FROM lca_certified
    WHERE is_data_role AND fiscal_year BETWEEN 2022 AND 2025
    GROUP BY ALL
)
SELECT
    role_family, fiscal_year, lcas, nyc_lcas,
    round(100.0 * nyc_lcas / lcas, 1)                                 AS nyc_share_pct,
    round(100.0 * (lcas / LAG(lcas) OVER w - 1), 1)                   AS lcas_yoy_pct,
    median_wage,
    round(100.0 * (median_wage / LAG(median_wage) OVER w - 1), 1)     AS wage_yoy_pct,
    nyc_median_wage
FROM yearly
WINDOW w AS (PARTITION BY role_family ORDER BY fiscal_year)
ORDER BY role_family, fiscal_year;
