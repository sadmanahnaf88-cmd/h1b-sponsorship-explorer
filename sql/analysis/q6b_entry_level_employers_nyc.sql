-- =====================================================================
-- Q6b. NYC employers with the most Level I/II data-role LCAs
-- (FY2024 + FY2025, the two most recent complete years).
-- The "where could a new grad apply" list.
-- Technique: string_agg(DISTINCT ...) to list role families per employer.
-- =====================================================================
SELECT
    employer_parent,
    count(*)                                                   AS level_1_2_data_lcas,
    count(*) FILTER (WHERE wage_level = 'I')                   AS level_1,
    string_agg(DISTINCT role_family, ', ' ORDER BY role_family) AS role_families,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats)       AS median_wage,
    mode(industry_sector)                                      AS industry_sector,
    bool_or(is_tech)                                           AS is_tech
FROM lca_certified
WHERE is_data_role
  AND is_nyc
  AND wage_level IN ('I', 'II')
  AND fiscal_year IN (2024, 2025)
GROUP BY employer_parent
ORDER BY level_1_2_data_lcas DESC, employer_parent
LIMIT 25;
