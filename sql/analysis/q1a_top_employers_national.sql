-- =====================================================================
-- Q1a. Top sponsoring employers for data roles - NATIONAL
-- Question : Which employers file the most certified H-1B LCAs for
--            data/analytics roles across the U.S.?
-- Unit     : certified LCAs (cases), NOT people or approved visas.
-- Period   : FY2022-FY2025 (four complete fiscal years). FY2026 is
--            partial and only used in the like-for-like trend query (Q3b).
-- Technique: GROUP BY + COUNT, FILTER clause for conditional counts,
--            window function over the grouped result for share of total.
-- =====================================================================
SELECT
    employer_parent,
    count(*)                                                    AS data_lcas_fy22_25,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)          AS pct_of_all_data_lcas,
    count(*) FILTER (WHERE role_family = 'Data Scientist')      AS data_scientist,
    count(*) FILTER (WHERE role_family = 'Data Engineer')       AS data_engineer,
    count(*) FILTER (WHERE role_family = 'Data Analyst')        AS data_analyst,
    count(*) FILTER (WHERE role_family = 'Business/BI Analyst') AS business_bi_analyst,
    count(*) FILTER (WHERE role_family = 'Analytics Manager')   AS analytics_manager,
    median(annual_wage) FILTER (WHERE wage_ok_for_stats)        AS median_wage,
    bool_or(is_tech)                                            AS is_tech
FROM lca_certified
WHERE is_data_role
  AND fiscal_year BETWEEN 2022 AND 2025
GROUP BY employer_parent
ORDER BY data_lcas_fy22_25 DESC
LIMIT 25;
