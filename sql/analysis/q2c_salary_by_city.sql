-- =====================================================================
-- Q2c. Data-role salaries in the cities with the most data LCAs (FY2025)
-- The five NYC boroughs are combined into one "NEW YORK CITY" label.
-- Technique: CTE builds a clean label; HAVING drops small cities so the
-- medians are not based on a handful of rows.
-- =====================================================================
WITH labeled AS (
    SELECT
        CASE WHEN is_nyc THEN 'NEW YORK CITY' ELSE worksite_city END
            || ', ' || worksite_state                         AS city,
        role_family, annual_wage, wage_ok_for_stats
    FROM lca_certified
    WHERE is_data_role AND fiscal_year = 2025
)
SELECT
    city,
    count(*)                                                        AS data_lcas_fy25,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats)            AS median_all_data_roles,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats AND role_family = 'Data Analyst')        AS median_data_analyst,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats AND role_family = 'Business/BI Analyst') AS median_business_bi,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats AND role_family = 'Data Scientist')      AS median_data_scientist,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats AND role_family = 'Data Engineer')       AS median_data_engineer
FROM labeled
GROUP BY city
HAVING count(*) >= 300
ORDER BY data_lcas_fy25 DESC
LIMIT 15;
