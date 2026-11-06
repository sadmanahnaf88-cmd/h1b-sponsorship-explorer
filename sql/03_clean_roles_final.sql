-- =====================================================================
-- 03_clean_roles_final.sql  (run by src/03_clean.py)
-- Input : lca_base, employer_name_map, ref_naics_sector
-- Output: lca_all        - every de-duplicated case, all statuses, all visa
--                          classes, with role family / employer / industry
--         lca_certified  - the analysis table: Certified + H-1B only
--
-- Role families are assigned by an ordered list of rules (first match wins).
-- The rule that fired is stored in `role_rule` so every classification can
-- be traced and spot-checked. See docs/DECISIONS.md "Role families".
-- =====================================================================

-- Regex note: (?i) is not needed because we match on job_title_upper.
-- \b = word boundary, so '\bBI\b' matches "BI ANALYST" but not "BIOLOGY".

CREATE OR REPLACE TABLE lca_all AS
WITH roles AS (
    SELECT
        b.*,
        CASE
            -- R0: exclusions - titles that contain data words but are NOT
            --     data/analytics roles for this project's purpose.
            WHEN regexp_matches(job_title_upper,
                 'PRODUCT MANAGE|PROJECT MANAGE|PROGRAM MANAGE|DATABASE ADMIN|\bDBA\b|DATA CENTER|'
              || 'MACHINE LEARNING ENGINEER|\bML ENGINEER|\bAI ENGINEER|\bAI/ML ENGINEER|'
              || 'CLINICAL DATA MANAGER|QUANTITATIVE (ANALYST|RESEARCHER|DEVELOPER)|'
              || 'STATISTICAL PROGRAMMER|DATA ENTRY')
                THEN 'R0_excluded_title'

            -- R1: managers of data/analytics teams
            WHEN regexp_matches(job_title_upper, '\bMANAGER\b|\bMGR\b|DIRECTOR|HEAD OF|VICE PRESIDENT|\bVP\b')
             AND regexp_matches(job_title_upper,
                 'DATA SCIENCE|DATA ENGINEERING|ANALYTICS|BUSINESS INTELLIGENCE|\bBI\b|INSIGHTS|'
              || 'DATA AND ANALYTICS|DATA & ANALYTICS|DATA STRATEGY|DATA GOVERNANCE|DATA PLATFORM|DATA MANAGEMENT')
                THEN 'R1_manager_title'

            -- R2: data scientists (incl. statisticians, applied/ML scientists)
            WHEN regexp_matches(job_title_upper,
                 'DATA SCIEN|APPLIED SCIENTIST|MACHINE LEARNING SCIENTIST|\bML SCIENTIST|DECISION SCIENTIST|'
              || 'STATISTICIAN|DATA AND APPLIED SCIENTIST')
                THEN 'R2_scientist_title'

            -- R3: data engineers (pipelines, warehouses, data architecture)
            WHEN regexp_matches(job_title_upper,
                 'DATA ENGINEER|BIG DATA|\bETL\b|DATA WAREHOUS|DATA ARCHITECT|ANALYTICS ENGINEER|'
              || 'DATA PIPELINE|DATA INTEGRATION|DATABASE ENGINEER|DATABASE DEVELOPER|DATABASE ARCHITECT|DATA MODELER')
                THEN 'R3_engineer_title'

            -- R4: data analysts (checked BEFORE business analyst so that
            --     "Business Data Analyst" counts as a data analyst)
            WHEN regexp_matches(job_title_upper,
                 'DATA ANALY|ANALYTICS (ANALYST|SPECIALIST|CONSULTANT|ASSOCIATE)|DATA ANALYTICS|'
              || 'REPORTING ANALYST|INSIGHTS? ANALYST|PRODUCT ANALYST|MARKETING ANALYTICS|PEOPLE ANALYTICS|'
              || 'ANALYST.*ANALYTICS|ANALYTICS.*ANALYST')
                THEN 'R4_analyst_title'

            -- R5: business / BI analysts
            WHEN regexp_matches(job_title_upper,
                 'BUSINESS INTELLIGENCE|BUSINESS INTEL|\bBI\b|POWER BI|TABLEAU|BUSINESS ANALYST|BUSINESS SYSTEMS ANALYST')
                THEN 'R5_business_bi_title'

            -- R6: SOC fallback, ONLY for generic titles ("Analyst",
            --     "Senior Associate", "Consultant II"...) where the title
            --     alone says nothing. The employer's SOC choice decides.
            WHEN regexp_matches(job_title_upper,
                 '^((SR\.?|SENIOR|LEAD|PRINCIPAL|STAFF|JUNIOR|JR\.?)\s+)*(ANALYST|ASSOCIATE|CONSULTANT|SPECIALIST|SCIENTIST|RESEARCHER|RESEARCH ANALYST)(\s+([IVX]+|[0-9]))?$')
             AND soc_code IN ('15-2051.00', '15-2041.00', '15-2041.01', '15-2051.01', '15-1199.08',
                              '15-1243.01', '15-1199.07')
                THEN 'R6_soc_fallback'
            ELSE 'R9_no_match'
        END AS role_rule
    FROM lca_base b
),
families AS (
    SELECT
        *,
        CASE role_rule
            WHEN 'R1_manager_title'     THEN 'Analytics Manager'
            WHEN 'R2_scientist_title'   THEN 'Data Scientist'
            WHEN 'R3_engineer_title'    THEN 'Data Engineer'
            WHEN 'R4_analyst_title'     THEN 'Data Analyst'
            WHEN 'R5_business_bi_title' THEN 'Business/BI Analyst'
            WHEN 'R6_soc_fallback' THEN
                CASE WHEN soc_code IN ('15-2051.00', '15-2041.00', '15-2041.01') THEN 'Data Scientist'
                     WHEN soc_code IN ('15-2051.01', '15-1199.08')               THEN 'Business/BI Analyst'
                     ELSE 'Data Engineer' END
            ELSE 'Other'
        END AS role_family
    FROM roles
)
SELECT
    f.*,
    role_family <> 'Other'                                   AS is_data_role,
    coalesce(m.employer_clean, normalize_employer(f.employer_name)) AS employer_clean,
    s.sector_name                                            AS industry_sector,

    -- Manual parent roll-up for well-known multi-entity employers
    -- (e.g. "AMAZON COM SERVICES" + "AMAZON WEB SERVICES" -> AMAZON).
    CASE
        WHEN m.employer_clean LIKE 'AMAZON%'                    THEN 'AMAZON'
        WHEN m.employer_clean LIKE 'GOOGLE%'                    THEN 'GOOGLE'
        WHEN m.employer_clean LIKE 'META PLATFORMS%'
          OR m.employer_clean LIKE 'FACEBOOK%'                  THEN 'META'
        WHEN m.employer_clean LIKE 'MICROSOFT%'                 THEN 'MICROSOFT'
        WHEN m.employer_clean = 'APPLE'                         THEN 'APPLE'
        WHEN m.employer_clean LIKE 'JPMORGAN%'
          OR m.employer_clean LIKE 'JP MORGAN%'                 THEN 'JPMORGAN CHASE'
        WHEN m.employer_clean LIKE 'GOLDMAN SACHS%'             THEN 'GOLDMAN SACHS'
        WHEN m.employer_clean LIKE 'MORGAN STANLEY%'            THEN 'MORGAN STANLEY'
        WHEN m.employer_clean LIKE 'CITIBANK%'
          OR m.employer_clean LIKE 'CITIGROUP%'                 THEN 'CITI'
        WHEN m.employer_clean LIKE 'DELOITTE%'                  THEN 'DELOITTE'
        WHEN m.employer_clean LIKE 'ERNST AND YOUNG%'           THEN 'EY'
        WHEN m.employer_clean LIKE 'PRICEWATERHOUSECOOPERS%'    THEN 'PWC'
        WHEN m.employer_clean LIKE 'KPMG%'                      THEN 'KPMG'
        WHEN m.employer_clean LIKE 'BLOOMBERG%'                 THEN 'BLOOMBERG'
        WHEN m.employer_clean LIKE 'INTERNATIONAL BUSINESS MACHINES%'
          OR m.employer_clean = 'IBM'                           THEN 'IBM'
        WHEN m.employer_clean LIKE 'COGNIZANT%'                 THEN 'COGNIZANT'
        WHEN m.employer_clean LIKE 'TATA CONSULTANCY%'          THEN 'TATA CONSULTANCY SERVICES'
        WHEN m.employer_clean LIKE 'INFOSYS%'                   THEN 'INFOSYS'
        WHEN m.employer_clean LIKE 'CAPITAL ONE%'               THEN 'CAPITAL ONE'
        WHEN m.employer_clean LIKE 'WALMART%'
          OR m.employer_clean LIKE 'WAL MART%'                  THEN 'WALMART'
        WHEN m.employer_clean LIKE 'ACCENTURE%'                 THEN 'ACCENTURE'
        WHEN m.employer_clean LIKE 'ORACLE%'                    THEN 'ORACLE'
        WHEN m.employer_clean LIKE 'SALESFORCE%'                THEN 'SALESFORCE'
        WHEN m.employer_clean LIKE 'TIKTOK%'
          OR m.employer_clean LIKE 'BYTEDANCE%'                 THEN 'TIKTOK / BYTEDANCE'
        WHEN m.employer_clean LIKE 'NVIDIA%'                    THEN 'NVIDIA'
        WHEN m.employer_clean LIKE 'UBER TECHNOLOGIES%'         THEN 'UBER'
        WHEN m.employer_clean LIKE 'NETFLIX%'                   THEN 'NETFLIX'
        WHEN m.employer_clean LIKE 'MCKINSEY%'                  THEN 'MCKINSEY'
        ELSE coalesce(m.employer_clean, normalize_employer(f.employer_name))
    END                                                      AS employer_parent
FROM families f
LEFT JOIN employer_name_map m USING (employer_name)
LEFT JOIN ref_naics_sector  s ON s.naics2 = f.naics2;


-- Tech flags need employer_parent, so they are added in a second pass.
-- "Tech" = tech NAICS (51 Information, 5415 IT services, 334 computer
-- hardware) OR a big-tech parent. Needed because e.g. Amazon files under
-- retail NAICS 4541 and would otherwise count as "outside tech".
CREATE OR REPLACE TABLE lca_all AS
SELECT
    *,
    employer_parent IN ('AMAZON', 'GOOGLE', 'META', 'MICROSOFT', 'APPLE', 'NETFLIX',
                        'NVIDIA', 'SALESFORCE', 'ORACLE', 'IBM', 'UBER',
                        'TIKTOK / BYTEDANCE')                AS is_big_tech,
    (naics2 = '51' OR naics4 = '5415' OR naics3 = '334')    AS is_tech_naics,
    (naics2 = '51' OR naics4 = '5415' OR naics3 = '334'
     OR employer_parent IN ('AMAZON', 'GOOGLE', 'META', 'MICROSOFT', 'APPLE', 'NETFLIX',
                            'NVIDIA', 'SALESFORCE', 'ORACLE', 'IBM', 'UBER',
                            'TIKTOK / BYTEDANCE'))           AS is_tech,
    -- One flag that says "use this row in salary statistics"
    is_full_time
      AND annual_wage IS NOT NULL
      AND NOT coalesce(flag_unit_suspect, false)
      AND NOT coalesce(flag_wage_too_low, false)
      AND NOT coalesce(flag_wage_too_high, false)
      AND NOT coalesce(flag_below_prevailing, false)         AS wage_ok_for_stats
FROM lca_all;


-- The analysis table: H-1B visa class, final status Certified.
-- ('Certified - Withdrawn' = employer withdrew after certification -> excluded.)
CREATE OR REPLACE TABLE lca_certified AS
SELECT *
FROM lca_all
WHERE case_status = 'Certified'
  AND visa_class  = 'H-1B';
