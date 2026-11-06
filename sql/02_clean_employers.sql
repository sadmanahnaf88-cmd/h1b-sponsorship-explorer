-- =====================================================================
-- 02_clean_employers.sql  (run by src/03_clean.py)
-- Input : lca_base
-- Output: employer_name_map  (raw employer_name -> employer_clean)
--         employer_merge_log (every merge we made, for auditing)
--
-- Three layers, each logged (see docs/DECISIONS.md, "Employer names"):
--   1. Text normalization: uppercase, & -> AND, drop punctuation,
--      drop legal suffixes (INC, LLC, CORP ...), drop leading THE.
--   2. Spacing merge: names equal after removing ALL spaces
--      ('JP MORGAN CHASE' vs 'JPMORGAN CHASE') -> most frequent spelling.
--   3. FEIN merge (FY2024+ only): names that share the same federal
--      employer ID number are the same legal entity -> most frequent name.
-- We do NOT merge different legal entities of one parent here (e.g. Amazon
-- Web Services vs Amazon.com Services); that is a separate, manual
-- `employer_parent` roll-up in 03_clean_roles_final.sql.
-- =====================================================================

-- ---------- Layer 1: text normalization (a SQL macro = reusable function)
CREATE OR REPLACE MACRO normalize_employer(n) AS (
    trim(regexp_replace(          -- 5. collapse repeated spaces
      regexp_replace(             -- 4. strip legal suffixes at the end (repeat-safe pattern)
        regexp_replace(           -- 3. strip a leading "THE "
          regexp_replace(         -- 2. anything not A-Z/0-9 -> space
            replace(upper(trim(n)), '&', ' AND '),   -- 1. uppercase, & -> AND
          '[^A-Z0-9 ]', ' ', 'g'),
        '^\s*THE\s+', ''),
      '(\s+(INC|INCORPORATED|LLC|L L C|LLP|L L P|LP|L P|LTD|LIMITED|CORP|CORPORATION|CO|COMPANY|PLC|PC|P C|PLLC|NA|N A|USA|US|U S|U S A|GROUP|HOLDINGS))+\s*$', ''),
    '\s+', ' ', 'g'))
);

CREATE OR REPLACE TABLE employer_name_map AS
WITH
names AS (                       -- every distinct raw name + its row count
    SELECT employer_name, normalize_employer(employer_name) AS norm1, count(*) AS n
    FROM lca_base
    WHERE employer_name IS NOT NULL
    GROUP BY ALL
),
-- ---------- Layer 2: spacing merge
spacing AS (
    SELECT *,
           replace(norm1, ' ', '') AS nospace_key
    FROM names
),
spacing_winner AS (              -- the most frequent spelling per no-space key
    SELECT nospace_key,
           arg_max(norm1, n_norm) AS norm2      -- arg_max = value of norm1 where n_norm is largest
    FROM (SELECT nospace_key, norm1, sum(n) AS n_norm FROM spacing GROUP BY ALL)
    GROUP BY nospace_key
),
step2 AS (
    SELECT s.employer_name, s.norm1, w.norm2, s.n
    FROM spacing s JOIN spacing_winner w USING (nospace_key)
),
-- ---------- Layer 3: FEIN merge
fein_counts AS (                 -- how often each normalized name uses each FEIN
    SELECT normalize_employer(employer_name) AS norm1,
           regexp_replace(employer_fein, '[^0-9]', '', 'g') AS fein,
           count(*) AS n
    FROM lca_base
    WHERE employer_fein IS NOT NULL
    GROUP BY ALL
),
name_main_fein AS (              -- a name's main FEIN, only if it is clearly dominant (>= 80%)
    SELECT norm1, arg_max(fein, n) AS fein, max(n) / sum(n) AS share
    FROM fein_counts
    WHERE length(fein) = 9 AND fein NOT IN ('000000000', '999999999', '123456789')
    GROUP BY norm1
    HAVING max(n) / sum(n) >= 0.8
),
fein_winner AS (                 -- most frequent norm2 name per FEIN
    SELECT f.fein, arg_max(s.norm2, s.n_total) AS norm3
    FROM name_main_fein f
    JOIN (SELECT norm1, norm2, sum(n) AS n_total FROM step2 GROUP BY ALL) s USING (norm1)
    GROUP BY f.fein
)
SELECT
    s.employer_name,
    s.norm1,
    s.norm2,
    coalesce(fw.norm3, s.norm2) AS employer_clean,
    f.fein                      AS employer_fein_main,
    s.n                         AS n_rows
FROM step2 s
LEFT JOIN name_main_fein f ON f.norm1 = s.norm1
LEFT JOIN fein_winner   fw ON fw.fein = f.fein;

-- ---------- Audit log: every raw name whose final name differs from layer 1
CREATE OR REPLACE TABLE employer_merge_log AS
SELECT
    employer_clean,
    norm1                    AS merged_from,
    CASE WHEN norm2 <> norm1 AND employer_clean = norm2 THEN 'spacing'
         WHEN employer_clean <> norm2                  THEN 'fein'
         ELSE 'spacing' END  AS merge_rule,
    sum(n_rows)              AS n_rows
FROM employer_name_map
WHERE employer_clean <> norm1
GROUP BY ALL
ORDER BY n_rows DESC;
