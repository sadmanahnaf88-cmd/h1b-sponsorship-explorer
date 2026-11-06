-- =====================================================================
-- Q6a. Entry-level signal: share of data LCAs at wage Level I or II
-- Level I/II prevailing wages are what employers use for less
-- experienced positions, so these are the most realistic for new grads.
-- Caveat: the level is the employer's classification of the JOB, not
-- proof the person hired was a new grad.
-- FY2025, NYC vs national.
-- =====================================================================
SELECT
    coalesce(role_family, 'ALL DATA ROLES')                                      AS role_family,
    count(*)                                                                      AS national_lcas,
    round(100.0 * avg((wage_level IN ('I', 'II'))::INT), 1)                       AS national_pct_level_1_2,
    round(100.0 * avg((wage_level = 'I')::INT), 1)                                AS national_pct_level_1,
    count(*) FILTER (WHERE is_nyc)                                                AS nyc_lcas,
    round(100.0 * avg((wage_level IN ('I', 'II'))::INT) FILTER (WHERE is_nyc), 1) AS nyc_pct_level_1_2,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats AND wage_level IN ('I', 'II') AND is_nyc)
                                                                                  AS nyc_median_wage_level_1_2
FROM lca_certified
WHERE is_data_role AND fiscal_year = 2025 AND wage_level IS NOT NULL
GROUP BY ROLLUP (role_family)
ORDER BY grouping(role_family), role_family;
