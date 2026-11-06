-- =====================================================================
-- Q3b. Like-for-like: FY2026 so far (Q1-Q3, Oct-Jun) vs the same
-- quarters of earlier years. FY2026 data stops at June 30, 2026, so
-- comparing it with full prior years would exaggerate any decline.
-- Technique: filter on fiscal_quarter before aggregating; ratio of
-- conditional counts for "data share of all LCAs".
-- =====================================================================
SELECT
    fiscal_year,
    count(*)                                                             AS all_lcas_q1_q3,
    count(*) FILTER (WHERE is_data_role)                                 AS data_lcas_q1_q3,
    count(*) FILTER (WHERE is_data_role AND is_nyc)                      AS nyc_data_lcas_q1_q3,
    round(100.0 * count(*) FILTER (WHERE is_data_role) / count(*), 2)    AS data_share_of_all_pct,
    median(annual_wage) FILTER (WHERE is_data_role AND wage_ok_for_stats) AS median_data_wage,
    median(annual_wage) FILTER (WHERE is_data_role AND wage_ok_for_stats AND is_nyc) AS nyc_median_data_wage
FROM lca_certified
WHERE fiscal_quarter IN (1, 2, 3)
GROUP BY fiscal_year
ORDER BY fiscal_year;
