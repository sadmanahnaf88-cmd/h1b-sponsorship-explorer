-- =====================================================================
-- Q4b. Headline number: share of data-role LCAs from NON-tech employers,
-- by role family, NYC vs national (FY2022-FY2025).
-- Technique: avg(condition::INT) = share of rows where condition is true.
-- ROLLUP adds a grand-total row (shown with role_family = NULL).
-- =====================================================================
SELECT
    coalesce(role_family, 'ALL DATA ROLES')                        AS role_family,
    count(*)                                                        AS national_lcas,
    round(100.0 * avg((NOT is_tech)::INT), 1)                       AS national_pct_non_tech,
    count(*) FILTER (WHERE is_nyc)                                  AS nyc_lcas,
    round(100.0 * avg((NOT is_tech)::INT) FILTER (WHERE is_nyc), 1) AS nyc_pct_non_tech
FROM lca_certified
WHERE is_data_role AND fiscal_year BETWEEN 2022 AND 2025
GROUP BY ROLLUP (role_family)
ORDER BY grouping(role_family), role_family;
