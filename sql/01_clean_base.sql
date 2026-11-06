-- =====================================================================
-- 01_clean_base.sql  (run by src/03_clean.py)
-- Input : lca_raw   (one row per row in the 17 DOL Excel files, all TEXT)
-- Output: lca_dedup (one row per case_number)
--         lca_base  (typed columns + derived fields: fiscal year, NYC flag,
--                    annual wage, wage-quality flags, SOC fix, NAICS)
--
-- Every judgment call here is explained in docs/DECISIONS.md.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP A. De-duplicate case numbers.
-- Profiling showed ~170k case numbers appear in more than one file:
--   * FY2023 Q2 file repeats ~90k cases already in FY2023 Q1 (identical rows)
--   * When an employer withdraws a CERTIFIED LCA later, DOL re-publishes
--     the case in a later file with status 'Certified - Withdrawn'.
--   * FY2026 Q3 is cumulative (Oct 2025 - Jun 2026).
-- Rule: STATUS comes from the LATEST file (most up-to-date outcome);
--       TIMING (decision date -> fiscal year) comes from the EARLIEST file
--       (when the case was first decided).
-- Technique: window functions ROW_NUMBER() and FIRST_VALUE() partitioned by case.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lca_dedup AS
WITH ranked AS (
    SELECT
        *,
        -- 1 = row from the latest file for this case
        ROW_NUMBER() OVER (PARTITION BY case_number
                           ORDER BY file_fy DESC, file_quarter DESC) AS rn_latest,
        -- earliest decision date seen for this case, across all files
        MIN(decision_date) OVER (PARTITION BY case_number)            AS first_decision_date,
        COUNT(*)           OVER (PARTITION BY case_number)            AS n_file_rows
    FROM lca_raw
)
SELECT * EXCLUDE (rn_latest)
FROM ranked
WHERE rn_latest = 1;


-- ---------------------------------------------------------------------
-- STEP B. Type conversion + derived columns.
-- TRY_CAST returns NULL instead of failing on a bad value, so the
-- validation step can COUNT bad values rather than crash.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE lca_base AS
WITH typed AS (
    SELECT
        case_number,
        case_status,
        visa_class,
        TRY_CAST(received_date       AS DATE) AS received_date,
        TRY_CAST(first_decision_date AS DATE) AS decision_date,
        n_file_rows,
        source_file,
        trim(job_title)                         AS job_title,
        upper(trim(job_title))                  AS job_title_upper,
        trim(soc_code)                          AS soc_code_raw,
        soc_title,
        full_time_position = 'Y'                AS is_full_time,
        TRY_CAST(total_worker_positions AS INTEGER) AS total_worker_positions,
        TRY_CAST(new_employment         AS INTEGER) AS new_employment,
        TRY_CAST(continued_employment   AS INTEGER) AS continued_employment,
        TRY_CAST(change_employer        AS INTEGER) AS change_employer,
        employer_name,
        trade_name_dba,
        employer_fein,
        upper(trim(employer_city))              AS employer_city,
        upper(trim(employer_state))             AS employer_state,
        trim(naics_code)                        AS naics_code,
        upper(trim(worksite_city))              AS worksite_city,
        upper(trim(worksite_county))            AS worksite_county,
        upper(trim(worksite_state))             AS worksite_state,
        -- Excel stored ZIPs as numbers, dropping leading zeros (07310 -> 7310).
        -- Take the first 5 digits, then left-pad with zeros back to 5.
        lpad(regexp_extract(worksite_postal_code, '^(\d{3,5})', 1), 5, '0') AS worksite_zip,
        TRY_CAST(replace(wage_rate_from, ',', '') AS DOUBLE) AS wage_from,
        TRY_CAST(replace(wage_rate_to,   ',', '') AS DOUBLE) AS wage_to,
        wage_unit,
        TRY_CAST(replace(prevailing_wage, ',', '') AS DOUBLE) AS prevailing_wage,
        pw_unit,
        CASE WHEN pw_wage_level IN ('I','II','III','IV') THEN pw_wage_level END AS wage_level,
        h1b_dependent,
        willful_violator
    FROM lca_dedup
),
derived AS (
    SELECT
        *,
        -- Federal fiscal year runs Oct 1 - Sep 30. FY2025 = Oct 2024 .. Sep 2025.
        CASE WHEN month(decision_date) >= 10 THEN year(decision_date) + 1
             ELSE year(decision_date) END                       AS fiscal_year,
        CASE WHEN month(decision_date) >= 10 THEN 1
             WHEN month(decision_date) <= 3  THEN 2
             WHEN month(decision_date) <= 6  THEN 3
             ELSE 4 END                                          AS fiscal_quarter,

        -- SOC code repair. Two problems found in profiling:
        --  (1) Excel turned some codes into dates: '11-3021' -> '3021-11-01'.
        --      Pattern YYYY-MM-01 is rebuilt as MM-YYYY.
        --  (2) Codes come at different detail: '15-2051', '15-2051.00',
        --      '15-2051.00.00'. We keep the 6-digit SOC ('15-2051') and the
        --      O*NET detail suffix ('.01') separately.
        CASE
            WHEN regexp_matches(soc_code_raw, '^\d{4}-\d{2}-01$')
                THEN substr(soc_code_raw, 6, 2) || '-' || substr(soc_code_raw, 1, 4)
            ELSE regexp_extract(soc_code_raw, '^(\d{2}-\d{4})', 1)
        END                                                      AS soc6,
        coalesce(nullif(regexp_extract(soc_code_raw, '^\d{2}-\d{4}[.-](\d{1,2})', 1), ''), '00') AS soc_detail_raw,

        -- Annualize the offered wage. LCA wages are often a range
        -- (from - to); we use the FROM value: it is the guaranteed minimum.
        CASE wage_unit
            WHEN 'Year'      THEN 1
            WHEN 'Month'     THEN 12
            WHEN 'Bi-Weekly' THEN 26
            WHEN 'Week'      THEN 52
            WHEN 'Hour'      THEN 2080   -- 40 h x 52 weeks
        END                                                      AS wage_factor,
        CASE pw_unit
            WHEN 'Year' THEN 1 WHEN 'Month' THEN 12 WHEN 'Bi-Weekly' THEN 26
            WHEN 'Week' THEN 52 WHEN 'Hour' THEN 2080
        END                                                      AS pw_factor,

        -- NYC = the five boroughs (counties). Fallback to city names when
        -- the county field is blank or written differently.
        worksite_state = 'NY' AND (
            regexp_replace(worksite_county, '\s+COUNTY$', '') IN
                ('NEW YORK', 'KINGS', 'QUEENS', 'BRONX', 'RICHMOND')
            OR worksite_city IN ('NEW YORK', 'NEW YORK CITY', 'NYC', 'MANHATTAN',
                                 'BROOKLYN', 'BRONX', 'THE BRONX', 'QUEENS',
                                 'STATEN ISLAND', 'LONG ISLAND CITY', 'ASTORIA',
                                 'FLUSHING', 'JAMAICA')
        )                                                        AS is_nyc
    FROM typed
)
SELECT
    * EXCLUDE (soc_detail_raw),
    soc6 || '.' || lpad(soc_detail_raw, 2, '0')                  AS soc_code,
    round(wage_from * wage_factor, 0)                            AS annual_wage,
    round(wage_to   * wage_factor, 0)                            AS annual_wage_to,
    round(prevailing_wage * pw_factor, 0)                        AS annual_prevailing_wage,
    left(naics_code, 2)                                          AS naics2,
    left(naics_code, 3)                                          AS naics3,
    left(naics_code, 4)                                          AS naics4,

    -- ---- Wage-quality flags (we FLAG, we never "fix" a wage) ----
    -- Unit mistake suspected: the number is far outside what that unit
    -- can mean (e.g. "$120,000 per WEEK" is an annual salary with the wrong
    -- unit ticked). Profiling: median "weekly" wage annualized to $4.5M.
    -- Thresholds are each ~ $1M+/year when annualized.
    (wage_unit = 'Hour'      AND wage_from >= 500)
      OR (wage_unit = 'Week'      AND wage_from >= 20000)
      OR (wage_unit = 'Bi-Weekly' AND wage_from >= 40000)
      OR (wage_unit = 'Month'     AND wage_from >= 85000)
      OR (wage_unit = 'Year'      AND wage_from < 1000)          AS flag_unit_suspect,
    -- Implausible annual values for a full-time professional role.
    (wage_from * wage_factor) < 30000                            AS flag_wage_too_low,
    (wage_from * wage_factor) > 1000000                          AS flag_wage_too_high,
    -- By law the offered wage must be >= the prevailing wage. Offered wage
    -- below 95% of prevailing (after annualizing both) signals a data error.
    (wage_from * wage_factor) < 0.95 * (prevailing_wage * pw_factor) AS flag_below_prevailing
FROM derived;
