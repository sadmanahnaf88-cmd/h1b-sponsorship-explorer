-- =====================================================================
-- Q5b. "Hidden sponsors" - NYC
-- Same definition as Q5a (non-tech, not consulting/accounting/staffing),
-- NYC worksites only, with a lower bar (>= 2 data LCAs in
-- each of the 4 complete years) because NYC volumes are smaller.
-- Adds median wage and entry-level share so the list is actionable.
-- Technique: CTE chain; the consistent-employer list is joined back to
-- the detail table to compute per-employer stats.
-- =====================================================================
WITH per_year AS (
    SELECT employer_parent, fiscal_year, count(*) AS lcas
    FROM lca_certified
    WHERE is_data_role AND is_nyc AND NOT is_tech
      -- not consulting/accounting/staffing (their business is placing or advising)
      AND coalesce(naics4, '') NOT IN ('5416', '5412', '5613')
      AND fiscal_year BETWEEN 2022 AND 2025
    GROUP BY ALL
),
consistent AS (
    SELECT employer_parent, sum(lcas) AS data_lcas_fy22_25, min(lcas) AS min_in_any_year
    FROM per_year
    GROUP BY employer_parent
    HAVING count(*) = 4 AND min(lcas) >= 2
)
SELECT
    k.employer_parent,
    mode(c.industry_sector)                                    AS industry_sector,
    any_value(k.data_lcas_fy22_25)                             AS data_lcas_fy22_25,
    any_value(k.min_in_any_year)                               AS min_in_any_year,
    mode(c.role_family)                                        AS most_common_role,
    median(c.annual_wage) FILTER (WHERE c.wage_ok_for_stats)   AS median_wage,
    round(100.0 * avg((c.wage_level IN ('I', 'II'))::INT), 0)  AS pct_level_1_2
FROM consistent k
JOIN lca_certified c
  ON c.employer_parent = k.employer_parent
 AND c.is_data_role AND c.is_nyc
 AND c.fiscal_year BETWEEN 2022 AND 2025
GROUP BY k.employer_parent
ORDER BY data_lcas_fy22_25 DESC, k.employer_parent
LIMIT 30;
