-- =====================================================================
-- Q2a. Salary distribution by role family: NYC vs national
-- Wages: annualized offered wage (FROM value), full-time only, rows with
-- any wage-quality flag excluded (wage_ok_for_stats). Year: FY2025, the
-- most recent complete fiscal year.
-- Technique: quantile_cont() for percentiles; UNION ALL stacks two
-- aggregations (national, NYC) into one result.
-- =====================================================================
WITH base AS (
    SELECT role_family, annual_wage, is_nyc
    FROM lca_certified
    WHERE is_data_role AND wage_ok_for_stats AND fiscal_year = 2025
)
SELECT 'National' AS geography, role_family, count(*) AS n,
       quantile_cont(annual_wage, 0.10) AS p10,
       quantile_cont(annual_wage, 0.25) AS p25,
       median(annual_wage)              AS median,
       quantile_cont(annual_wage, 0.75) AS p75,
       quantile_cont(annual_wage, 0.90) AS p90
FROM base
GROUP BY role_family
UNION ALL
SELECT 'NYC', role_family, count(*),
       quantile_cont(annual_wage, 0.10), quantile_cont(annual_wage, 0.25),
       median(annual_wage),
       quantile_cont(annual_wage, 0.75), quantile_cont(annual_wage, 0.90)
FROM base
WHERE is_nyc
GROUP BY role_family
ORDER BY role_family, geography;
