"""
Step 5 - Export a star schema for Power BI as CSV files.

Star schema = one FACT table (one row per event; here one certified LCA)
surrounded by DIMENSION tables (descriptive attributes) joined on integer
keys. Power BI's engine is built for this shape: small dimensions filter a
big fact table through one-to-many relationships.

Outputs (outputs/powerbi/):
    fact_lca.csv              all certified H-1B LCAs, FY2022-FY2026 (big, git-ignored)
    fact_lca_data_roles.csv   same columns, data roles only (small, committed)
    dim_employer.csv          employer_key -> clean name, parent, big-tech flag
    dim_role.csv              role_key -> role family, SOC code/title
    dim_location.csv          location_key -> city, state, county, NYC flag, metro label
    dim_date.csv              date_key (YYYYMMDD) -> calendar + fiscal attributes
    dim_industry.csv          industry_key (NAICS code) -> sector, tech flag

All keys are built in SQL with DENSE_RANK() so the same input always gets
the same key on a re-run (deterministic ordering).
"""
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "h1b.duckdb"
OUT = ROOT / "outputs" / "powerbi"

BUILD_SQL = """
-- ---------- dimensions ----------
CREATE OR REPLACE TABLE dim_employer AS
SELECT
    DENSE_RANK() OVER (ORDER BY employer_clean) AS employer_key,
    employer_clean,
    any_value(employer_parent)                  AS employer_parent,
    bool_or(is_big_tech)                        AS is_big_tech,
    mode(industry_sector)                       AS main_industry_sector,
    mode(employer_state)                        AS hq_state
FROM lca_certified
GROUP BY employer_clean;

CREATE OR REPLACE TABLE dim_role AS
SELECT
    DENSE_RANK() OVER (ORDER BY role_family, soc_code) AS role_key,
    role_family,
    role_family <> 'Other'                            AS is_data_role,
    soc_code,
    mode(soc_title)                                   AS soc_title
FROM lca_certified
GROUP BY role_family, soc_code;

CREATE OR REPLACE TABLE dim_location AS
SELECT
    DENSE_RANK() OVER (ORDER BY worksite_state, worksite_city, worksite_county) AS location_key,
    worksite_city, worksite_county, worksite_state,
    bool_or(is_nyc)                                                       AS is_nyc,
    CASE WHEN bool_or(is_nyc) THEN 'New York City' ELSE 'Rest of U.S.' END AS nyc_vs_rest,
    CASE WHEN bool_or(is_nyc) THEN 'NEW YORK CITY, NY'
         ELSE coalesce(worksite_city, '?') || ', ' || coalesce(worksite_state, '?') END AS city_label
FROM lca_certified
GROUP BY worksite_state, worksite_city, worksite_county;

CREATE OR REPLACE TABLE dim_date AS
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER) AS date_key,
    CAST(d AS DATE)                         AS date,
    year(d)                                  AS calendar_year,
    month(d)                                 AS month_num,
    strftime(d, '%b')                        AS month_name,
    CASE WHEN month(d) >= 10 THEN year(d) + 1 ELSE year(d) END AS fiscal_year,
    CASE WHEN month(d) >= 10 THEN 1 WHEN month(d) <= 3 THEN 2
         WHEN month(d) <= 6 THEN 3 ELSE 4 END                  AS fiscal_quarter,
    'FY' || (CASE WHEN month(d) >= 10 THEN year(d) + 1 ELSE year(d) END)
        || CASE WHEN (CASE WHEN month(d) >= 10 THEN year(d) + 1 ELSE year(d) END) = 2026
                THEN ' (Q1-Q3 only)' ELSE '' END                AS fiscal_year_label
FROM generate_series(DATE '2021-10-01', DATE '2026-09-30', INTERVAL 1 DAY) AS t(d);

CREATE OR REPLACE TABLE dim_industry AS
SELECT
    coalesce(naics_code, 'UNKNOWN')                       AS industry_key,
    any_value(naics2)                                     AS naics2,
    coalesce(any_value(industry_sector), 'Unknown')       AS industry_sector,
    bool_or(is_tech_naics)                                AS is_tech_naics
FROM lca_certified
GROUP BY coalesce(naics_code, 'UNKNOWN');

-- ---------- fact ----------
CREATE OR REPLACE TABLE fact_lca AS
SELECT
    c.case_number,
    CAST(strftime(c.decision_date, '%Y%m%d') AS INTEGER) AS date_key,
    e.employer_key,
    r.role_key,
    l.location_key,
    coalesce(c.naics_code, 'UNKNOWN')                   AS industry_key,
    c.job_title,
    c.wage_level,
    (c.wage_level IN ('I', 'II'))                       AS is_entry_level,
    c.is_full_time,
    c.is_tech,
    c.annual_wage,
    c.annual_prevailing_wage,
    c.wage_ok_for_stats,
    c.total_worker_positions
FROM lca_certified c
JOIN dim_employer e ON e.employer_clean = c.employer_clean
JOIN dim_role     r ON r.role_family = c.role_family AND r.soc_code IS NOT DISTINCT FROM c.soc_code
JOIN dim_location l ON l.worksite_state IS NOT DISTINCT FROM c.worksite_state
                   AND l.worksite_city  IS NOT DISTINCT FROM c.worksite_city
                   AND l.worksite_county IS NOT DISTINCT FROM c.worksite_county;
"""


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB))
    con.execute(BUILD_SQL).fetchall()

    # Validation: the fact must have exactly one row per certified case
    # (a bad join would silently duplicate or drop rows).
    n_cert = con.sql("SELECT count(*) FROM lca_certified").fetchall()[0][0]
    n_fact = con.sql("SELECT count(*) FROM fact_lca").fetchall()[0][0]
    n_keys = con.sql("SELECT count(DISTINCT case_number) FROM fact_lca").fetchall()[0][0]
    assert n_cert == n_fact == n_keys, (n_cert, n_fact, n_keys)
    orphan_dates = con.sql("SELECT count(*) FROM fact_lca f ANTI JOIN dim_date d USING (date_key)").fetchall()[0][0]
    assert orphan_dates == 0, f"{orphan_dates} fact rows have no matching date"
    print(f"fact_lca rows = lca_certified rows = {n_fact:,}; no orphan dates")

    for t in ["dim_employer", "dim_role", "dim_location", "dim_date", "dim_industry", "fact_lca"]:
        con.execute(f"COPY {t} TO '{(OUT / (t + '.csv')).as_posix()}' (HEADER, DELIMITER ',')").fetchall()
        print(f"{t}: {con.sql(f'SELECT count(*) FROM {t}').fetchall()[0][0]:,} rows")

    con.execute(f"""
        COPY (SELECT f.* FROM fact_lca f JOIN dim_role r USING (role_key) WHERE r.is_data_role)
        TO '{(OUT / 'fact_lca_data_roles.csv').as_posix()}' (HEADER, DELIMITER ',')
    """).fetchall()
    n_data = con.sql("SELECT count(*) FROM fact_lca f JOIN dim_role r USING (role_key) WHERE r.is_data_role").fetchall()[0][0]
    print(f"fact_lca_data_roles: {n_data:,} rows")
    for p in sorted(OUT.glob("*.csv")):
        print(f"  {p.name}: {p.stat().st_size / 1e6:.1f} MB")
    con.close()


if __name__ == "__main__":
    main()
