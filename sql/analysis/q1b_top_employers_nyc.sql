-- =====================================================================
-- Q1b. Top sponsoring employers for data roles - NEW YORK CITY
-- Same as Q1a but restricted to worksites in the five boroughs
-- (is_nyc flag, built in sql/01_clean_base.sql), with each employer's
-- NATIONAL rank alongside so you can see who is NYC-heavy.
-- Technique: CTE + RANK() window function, then JOIN back.
-- =====================================================================
WITH national AS (
    SELECT employer_parent,
           RANK() OVER (ORDER BY count(*) DESC) AS national_rank
    FROM lca_certified
    WHERE is_data_role AND fiscal_year BETWEEN 2022 AND 2025
    GROUP BY employer_parent
)
SELECT
    c.employer_parent,
    count(*)                                                    AS nyc_data_lcas_fy22_25,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)          AS pct_of_nyc_data_lcas,
    any_value(n.national_rank)                                  AS national_rank,
    mode(c.role_family)                                         AS most_common_role,
    median(c.annual_wage) FILTER (WHERE c.wage_ok_for_stats)    AS median_wage,
    mode(c.industry_sector)                                     AS industry_sector,
    bool_or(c.is_tech)                                          AS is_tech
FROM lca_certified c
JOIN national n USING (employer_parent)
WHERE c.is_data_role
  AND c.is_nyc
  AND c.fiscal_year BETWEEN 2022 AND 2025
GROUP BY c.employer_parent
ORDER BY nyc_data_lcas_fy22_25 DESC, c.employer_parent   -- tie-breaker keeps output stable
LIMIT 25;
