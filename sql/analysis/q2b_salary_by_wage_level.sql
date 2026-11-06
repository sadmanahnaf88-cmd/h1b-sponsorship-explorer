-- =====================================================================
-- Q2b. Salary by DOL wage level (I = entry ... IV = fully competent)
-- How much does pay rise per level, and what is the NYC premium at each?
-- Technique: conditional aggregation (median(...) FILTER (WHERE ...)) to
-- put NYC and national in separate columns in a single pass.
-- =====================================================================
SELECT
    role_family,
    wage_level,
    count(*)                                              AS n_national,
    median(annual_wage)                                   AS median_national,
    count(*) FILTER (WHERE is_nyc)                        AS n_nyc,
    median(annual_wage) FILTER (WHERE is_nyc)             AS median_nyc,
    round(100.0 * (median(annual_wage) FILTER (WHERE is_nyc)
                   / median(annual_wage) - 1), 1)         AS nyc_premium_pct
FROM lca_certified
WHERE is_data_role
  AND wage_ok_for_stats
  AND wage_level IS NOT NULL
  AND fiscal_year = 2025
GROUP BY role_family, wage_level
ORDER BY role_family, wage_level;
