-- =====================================================================
-- Q5a. "Hidden sponsors" - NATIONAL
-- Employers OUTSIDE tech that sponsor data roles CONSISTENTLY.
-- Definition (DECISIONS.md):
--   * not tech (is_tech = false)
--   * not management consulting (NAICS 5416), accounting/Big-4 (5412)
--     or staffing (5613): those firms place or advise; we want companies
--     whose OWN business (bank, retailer, insurer, hospital...) hires data people
--   * at least 5 certified data-role LCAs in EACH of FY2022..FY2025
-- Technique: two-level aggregation - first per employer-year, then per
-- employer; HAVING count(*) = 4 AND min(...) >= 5 means "every year".
-- =====================================================================
WITH per_year AS (
    SELECT employer_parent, fiscal_year,
           count(*)                AS lcas,
           mode(industry_sector)   AS industry_sector
    FROM lca_certified
    WHERE is_data_role
      AND NOT is_tech
      -- not consulting/accounting/staffing (their business is placing or advising)
      AND coalesce(naics4, '') NOT IN ('5416', '5412', '5613')
      AND fiscal_year BETWEEN 2022 AND 2025
    GROUP BY ALL
)
SELECT
    employer_parent,
    mode(industry_sector)                              AS industry_sector,
    sum(lcas)                                          AS data_lcas_fy22_25,
    min(lcas)                                          AS min_in_any_year,
    max(lcas) FILTER (WHERE fiscal_year = 2022)        AS fy2022,
    max(lcas) FILTER (WHERE fiscal_year = 2025)        AS fy2025
FROM per_year
GROUP BY employer_parent
HAVING count(*) = 4 AND min(lcas) >= 5
ORDER BY data_lcas_fy22_25 DESC
LIMIT 30;
