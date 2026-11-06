-- =====================================================================
-- Q4a. Industry breakdown (NAICS sector) for data-role LCAs, NYC vs national
-- Period: FY2022-FY2025. "Tech" = NAICS 51 / 5415 / 334 or a big-tech
-- parent (see DECISIONS.md). A sector can appear twice (Tech and
-- Non-tech) because e.g. Amazon sits in Retail but counts as tech.
-- Technique: window SUM over a FILTERed aggregate to get NYC percentages.
-- =====================================================================
WITH d AS (
    SELECT coalesce(industry_sector, 'Unknown')            AS industry_sector,
           CASE WHEN is_tech THEN 'Tech' ELSE 'Non-tech' END AS tech_group,
           is_nyc
    FROM lca_certified
    WHERE is_data_role AND fiscal_year BETWEEN 2022 AND 2025
)
SELECT
    industry_sector,
    tech_group,
    count(*)                                                    AS national_lcas,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)          AS national_pct,
    count(*) FILTER (WHERE is_nyc)                              AS nyc_lcas,
    round(100.0 * count(*) FILTER (WHERE is_nyc)
          / sum(count(*) FILTER (WHERE is_nyc)) OVER (), 1)     AS nyc_pct
FROM d
GROUP BY ALL
ORDER BY nyc_lcas DESC;
