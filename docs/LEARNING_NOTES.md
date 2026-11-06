# Learning notes: a study guide to this project

Work through this in order. It follows the pipeline. Each section covers:
**what the step does → the techniques it uses → where to look (file:line) →
exercises.** Line numbers refer to the files as committed. If you edit a file,
search for the quoted snippet instead.

**Setup for the exercises.** Open a DuckDB shell on the project database so you can try queries:

```bash
.venv/Scripts/python -c "import duckdb; con = duckdb.connect('data/h1b.duckdb', read_only=True); print(con.sql('SHOW TABLES'))"
```

Even better, install the DuckDB CLI (`winget install DuckDB.cli`) and run `duckdb data/h1b.duckdb -readonly`.
Then you can type SQL directly. Always use `-readonly` while practicing so you can't damage the tables.

---

## Part 0: The big picture (read first)

```
DOL website ──(01_download.py)──> 17 .xlsx files (1.7 GB)
   ──(02_load.py)──> 17 .parquet files ──> DuckDB table lca_raw          2,865,776 rows
   ──(sql/01)──> lca_dedup ──> lca_base (typed, wages, flags)            2,695,890 rows
   ──(sql/02)──> employer_name_map
   ──(sql/03)──> lca_all (role, employer, industry) ──> lca_certified    2,415,525 rows
   ──(sql/analysis)──> outputs/tables/*.csv ──(06_charts.py)──> PNGs
   ──(05_powerbi_export.py)──> star schema CSVs ──> Power BI
```

**Concepts to be able to explain in an interview:**
- *Why Parquet?* It's a columnar, compressed, typed file format. The 252 MB FY2026 Excel file becomes ~22 MB of Parquet, and reading one column doesn't require reading the others.
- *Why DuckDB?* It's an in-process analytical SQL database (think "SQLite for analytics"). There's no server. It queries Parquet directly and handles 2–3M rows in seconds on a laptop.
- *Why SQL for cleaning, Python for orchestration?* SQL is declarative and set-based. It's easy to review and it's the language you'll be tested on. Python handles what SQL is bad at: downloading files, reading Excel, writing reports, and drawing charts.

---

## Part 1: Download (`src/01_download.py`)

**Techniques**
- `urllib.request` with a **HEAD request** to read `Content-Length` before downloading. It is used to skip files that are already complete (idempotent re-runs).
- **Download to `.part`, then rename** (`tmp.replace(dest)`). A crash never leaves a half-file that looks complete.
- `while chunk := r.read(1 << 20)`: the walrus operator `:=` assigns inside the loop condition. `1 << 20` = 1 MiB chunks, so the whole file is never held in memory.

**Exercises**
1. Add a progress print every 20 MB.
2. Add `LCA_Disclosure_Data_FY2021_Q1..Q4` and observe what `02_load.py`'s inventory says about columns. (Spoiler: FY2021 layouts are close, but check.)

---

## Part 2: Load (`src/02_load.py`)

**Techniques**

| Concept | Where | Explanation |
|---|---|---|
| Fast Excel reading | `read_xlsx`, line 101 | `python-calamine` (Rust) reads a 100 MB workbook in ~40 s. Doing that with pandas+openpyxl takes several minutes. |
| **Never assume columns** | the `COLUMN_MAP` dict (top of file) and `reverse = {...}`, line 114 | The map lists every raw name a canonical column has used. `reverse` is a **dict comprehension** that flips it to raw→canonical for lookup. This is how we caught FY2025 Q1's `H-1B_DEPENDENT` (hyphen). |
| Consistent text conversion | `to_text`, line 84 | Floats like `7652.0` → `"7652"`, dates → ISO strings, blanks → `None`. Everything stays text until SQL. |
| Data minimization | `PII_PATTERN`, line 81 | A regex drops personal contact columns at the source. |
| Parquet + `union_by_name` | line 149 | `read_parquet('dir/*.parquet', union_by_name = true)` stacks files **by column name**, not position. A missing column becomes NULL instead of misaligning. |
| Row-count reconciliation | `assert total == parquet_total`, line 153 | The first of many "counts must match" checks. If DuckDB and Parquet disagree, stop. |
| Generated documentation | `write_inventory` | Produces `docs/column_inventory.md`, the evidence that columns were inspected per file. |

**Exercises**
1. In DuckDB: `SELECT source_file, count(*) FROM lca_raw GROUP BY ALL ORDER BY 1;`. Compare it with the load log in `column_inventory.md`.
2. Find every raw column that appears in only some files (hint: the inventory table). Which ones and why?
3. Change `to_text` to keep floats as-is and re-load one file. What happens to ZIP codes like `07310`?

---

## Part 3: Cleaning in SQL

### 3a. `sql/01_clean_base.sql`: dedupe, types, wages

| Concept | Line | Explanation |
|---|---|---|
| **Window function `ROW_NUMBER()`** | 29 | `ROW_NUMBER() OVER (PARTITION BY case_number ORDER BY file_fy DESC, file_quarter DESC)` numbers each case's rows from newest file to oldest. `WHERE rn_latest = 1` keeps the newest. **This is the #1 dedup pattern in SQL interviews.** |
| Aggregate as a window: `MIN() OVER` | 32 | `MIN(decision_date) OVER (PARTITION BY case_number)` attaches the earliest date to *every* row of the case **without collapsing rows**. That's the difference from `GROUP BY`. |
| `SELECT * EXCLUDE (col)` | after the CTE | A DuckDB convenience: all columns except some. (Standard SQL would make you list them.) |
| **`TRY_CAST`** | 52 onwards | Returns NULL instead of failing on bad input. Then you can *count* the NULLs (validation §4). |
| String repair: `regexp_extract` + `lpad` | 76 | Extract the first 3–5 digits, left-pad with zeros to 5. This restores ZIPs that Excel turned into numbers. |
| `CASE` for derived categories | 91–96 | Fiscal year and fiscal quarter from a date. FY starts in October. |
| Fixing an Excel date mangle | 105 | `'3021-11-01'` → `'11-3021'` by detecting the pattern `^\d{4}-\d{2}-01$` and swapping the parts. |
| **`CASE` as a lookup table** | 113 | Unit → annualization factor. |
| **NULL logic & `coalesce`** | 129 | `NULL AND x` is NULL, not FALSE. One blank state made `is_nyc` NULL for 1,544 rows. `coalesce(expr, false)` fixes it. Classic interview trap. |
| Boolean flags instead of deleting | 150–164 (unit thresholds at 154) | Keep the row, add `flag_*`. Filtering happens later and visibly (`wage_ok_for_stats`). |

**Exercises**
1. Write a query that returns the case numbers appearing in 3 files, with their statuses in file order. (Hint: `string_agg(case_status, ' -> ' ORDER BY source_file)`.)
2. Rewrite the dedup with `QUALIFY` (DuckDB supports it): `SELECT * FROM lca_raw QUALIFY ROW_NUMBER() OVER (...) = 1`. Check that the counts match.
3. What's the difference between `ROW_NUMBER`, `RANK` and `DENSE_RANK` when two rows tie? Build a 4-row example with `VALUES` and see.
4. How many certified LCAs have `wage_to > wage_from`? What is the median ratio? (You should get 32.0% and 1.22.)
5. Change the hourly threshold from 500 to 300. How many more rows get flagged? Look at 10 of them. Are they real hourly wages?

### 3b. `sql/02_clean_employers.sql`: employer names

| Concept | Line | Explanation |
|---|---|---|
| **SQL macro** (a reusable function) | 20 | `CREATE MACRO normalize_employer(n) AS (...)`. Write the logic once, use it in several queries. |
| Nested `regexp_replace` | inside the macro | Read it **inside-out**: uppercase → punctuation → leading THE → suffixes → spaces. The `'g'` flag means replace *all* matches. |
| Regex alternation + repetition | suffix pattern | `(\s+(INC|LLC|...))+\s*$` strips **one or more** suffixes at the end ("… INC LLC"). |
| CTE chain | the whole file | Each `WITH` step does one thing: `names → spacing → spacing_winner → step2 → fein_counts → ...`. Readable top to bottom. |
| **`arg_max(x, y)`** | 50 | "The value of x on the row where y is largest", e.g. the most frequent spelling. The key is a `(count, name)` pair so ties break the same way every run (we found 2 spellings with equal counts flipping between runs). In standard SQL you'd use `ROW_NUMBER()` and filter `= 1`. Try it. |
| Dominance threshold with `HAVING` | 76 | Use a name's FEIN only if ≥ 80% of its rows share it. |
| Exclusion by regex | 74 | Universities and governments share state FEINs, so they're skipped. |
| `LEFT JOIN` + `coalesce` fallback | 92 + final SELECT | If there's no FEIN match, keep the layer-2 name. |
| Audit table | 96 | Every change is logged → `outputs/employer_merge_log.csv`. |

**Exercises**
1. `SELECT normalize_employer('The Goldman Sachs Group, Inc.');`. Predict the output first.
2. Find employers whose cleaned names differ only by a trailing `S` (e.g. `ACCENTURE` vs `ACCENTURES`). Should they merge? Write the rule.
3. Rewrite `spacing_winner` without `arg_max`, using `ROW_NUMBER() OVER (PARTITION BY nospace_key ORDER BY n_norm DESC)`.
4. Open `employer_merge_log.csv` and find one merge you think is **wrong**. Write it up as a new row in DECISIONS.md §6.

### 3c. `sql/03_clean_roles_final.sql`: role families and final tables

| Concept | Line | Explanation |
|---|---|---|
| **Ordered `CASE` = rule engine** | 20–70 | A `CASE` stops at the first true `WHEN`, so the order encodes priority. Exclusions (R0, line 28) come first. |
| `regexp_matches` with `\b` | throughout | `\b` = word boundary: `\bBI\b` matches "BI ANALYST" but not "BIOLOGY". |
| Traceability column | `role_rule` | Store *why* each row got its label. This is debugging and audit gold. |
| Two-step mapping | 83 | Rule → family in a second `CASE`, so the SOC fallback can branch on SOC code. |
| `LEFT JOIN ... USING` | 149 | `USING (employer_name)` joins on a same-named column and outputs it once. |
| Building a table in two passes | 160–175 | `is_tech` needs `employer_parent`, which is computed in pass 1. `CREATE OR REPLACE TABLE lca_all AS SELECT *, ... FROM lca_all` adds columns. |
| Composite boolean | 170–174 | `wage_ok_for_stats` = one readable flag that every salary query uses. |
| Final filter table | 180 | `lca_certified` = Certified + H-1B. |

**Exercises**
1. Pick 5 random rows from `lca_certified WHERE role_rule = 'R9_no_match' AND soc6 = '15-2051'`. Would you classify them differently?
2. Add a rule for **"Analytics Engineer" as its own family**. How many rows move? Which employers use the title most?
3. Move the R4 (Data Analyst) rule *below* R5 (Business/BI). Count how many rows change family, and look at examples. This is how you prove that order matters.
4. Precision/recall thinking: the spot-check measures *precision* (rows we labeled data roles that are right). How would you estimate *recall* (data roles we missed)? Sample 50 rows from `Other` with SOC 15-2051 and count.

### 3d. `src/03_clean.py`: validation

| Concept | Line | Explanation |
|---|---|---|
| Assertions as tests | 75–76 | Dedup must keep exactly one row per distinct case. A bad join would make `lca_all` bigger: the classic **fan-out bug**. |
| Report generation | `section()`, line 48 | Every check is a SQL query → printed **and** written to `validation_report.md`. |
| Small helper instead of a dependency | `md_table`, line 29 | DataFrame → markdown without installing `tabulate`. |
| Deterministic sampling | 162 | `ORDER BY hash(case_number || 'spotcheck') LIMIT 20` gives the same "random" rows on every run, so your spot-check review stays reproducible. |

**Exercises**
1. Add a check that fails if more than 1% of certified rows have a NULL `annual_wage`.
2. Add a "row count by fiscal year" check that warns if any complete year changes by more than 30% from the previous year.

---

## Part 4: Analysis queries (`sql/analysis/`)

Every file has a header with the **question**, the **unit**, the **period** and the **technique**. Run any of them:

```bash
.venv/Scripts/python src/run_sql.py sql/analysis/q3a_yoy_volume_and_pay.sql
```

| File | Main technique | What to notice |
|---|---|---|
| `q0_headline_numbers` | CTE chain, `ROW_NUMBER` per group, `FILTER` | top-N share **within each group** (line 16) |
| `q1a_top_employers_national` | **`FILTER (WHERE …)`** conditional aggregation; window over an aggregate | `sum(count(*)) OVER ()` = the grand total, computed after `GROUP BY` (line 14) |
| `q1b_top_employers_nyc` | **`RANK()`** in a CTE, then join back | compare NYC rank vs national rank |
| `q2a_salary_by_role_family` | `quantile_cont`, `UNION ALL` | stacking two aggregations into one result |
| `q2b_salary_by_wage_level` | conditional aggregation as a pivot | NYC and national as columns in one pass |
| `q2c_salary_by_city` | CTE for labels, **`HAVING`** | `WHERE` filters rows *before* grouping, `HAVING` filters groups *after* |
| `q3a_yoy_volume_and_pay` | **`LAG()`** + named `WINDOW` | YoY % = current / previous − 1, within each role family |
| `q3b_ytd_fy2026_vs_prior` | like-for-like filtering | never compare a partial year with full years |
| `q4a_industry_breakdown` | windowed sum of a filtered aggregate | NYC % of NYC total in the same query as national % |
| `q4b_outside_tech_share` | **`avg(bool::INT)` = share**, **`ROLLUP`** | `ROLLUP` adds the "all roles" row; `grouping()` sorts it last |
| `q5a/q5b_hidden_sponsors` | **two-level aggregation**, `HAVING count(*) = 4 AND min(n) >= k` | "in every year" expressed in SQL |
| `q6a_entry_level_share` | `ROLLUP`, shares | |
| `q6b_entry_level_employers_nyc` | `string_agg(DISTINCT … ORDER BY …)` | list values in one cell |

**Exercises (do these; they're interview-style)**
1. *Top 3 employers per role family in NYC, FY2025.* (Hint: `ROW_NUMBER() OVER (PARTITION BY role_family ORDER BY count(*) DESC)`, then `QUALIFY rn <= 3`.)
2. *Employers whose data-role LCAs grew every year FY2022→FY2025.* (Hint: `LAG` inside a CTE, then `HAVING bool_and(n > prev_n)`.)
3. *Month-of-year seasonality*: certified LCAs by calendar month, all years. Why is April–June so big? (Cap season.)
4. *Median vs mean*: add `avg(annual_wage)` next to the median in `q2a`. Which is higher, and why? (Right skew.)
5. *Rewrite `q2b` without `FILTER`*, using `CASE WHEN is_nyc THEN annual_wage END` inside `median()`. Same result? (It should be: aggregates ignore NULLs.)
6. *Cohort question*: of employers that sponsored a NYC data role in FY2022, what % sponsored again in FY2025? (Hint: two CTEs of distinct employers, `LEFT JOIN`, count the matches.)

---

## Part 5: Power BI star schema (`src/05_powerbi_export.py`)

| Concept | Line | Explanation |
|---|---|---|
| **Star schema** | docstring | One fact (events) plus dimensions (descriptions). Filters flow dimension → fact. |
| **Surrogate keys with `DENSE_RANK()`** | 33, 44, 54 | Integer keys are deterministic: same data → same keys. Smaller and faster than text joins. |
| **Date dimension from `generate_series`** | 76 | One row per day, with fiscal attributes pre-computed. Power BI needs a contiguous date table for time intelligence. |
| **`IS NOT DISTINCT FROM`** | 107–110 | A NULL-safe equality: `NULL = NULL` is NULL (no match), but `NULL IS NOT DISTINCT FROM NULL` is TRUE. Without it, rows with a blank city would silently drop out of the fact table. |
| **`ANTI JOIN`** | 125 | "Fact rows with no matching date": the orphan check. Standard SQL: `LEFT JOIN … WHERE d.date_key IS NULL`. |
| Grain check | 124 | fact rows = certified rows = distinct case numbers. |

**Exercises**
1. Explain to a friend why `is_tech` is on the **fact** and not on `dim_employer`. (Hint: one employer can file under different NAICS codes.)
2. Replace `IS NOT DISTINCT FROM` with `=` on line 108 in a scratch copy and run it. How many rows does the fact lose? (The assert will tell you.)
3. Design a `dim_wage_level` table (I–IV with descriptions). What changes in the fact?

Then follow `POWERBI_BUILD_GUIDE.md` and `DAX_MEASURES.md`. The DAX file explains each measure. Focus on understanding **filter context** and **`CALCULATE`**.

---

## Part 6: Charts (`src/06_charts.py`)

| Concept | Line | Explanation |
|---|---|---|
| Global style with `rcParams` | 26 | Set fonts, colors and spines once, not in every chart. |
| Escaping `$` | `money()`, 34 | Matplotlib treats text between two `$` as math. Escape it as `\$`. (We hit this bug: labels rendered as italic "114kvs99k".) |
| Display formatting helper | `display_name()`, 42 | `.title()` gives "Jpmorgan" and "Ey". Use a small acronym map instead. |
| Dot plot / dumbbell | `chart_salary_by_family`, 80 | Two dots + a connector line show a *gap* better than grouped bars. |
| Charts read the CSVs | all | Charts never recompute numbers. They read `outputs/tables`, so a chart can't disagree with the SQL. |

**Exercises**
1. Add a chart: median data-role salary by fiscal year, NYC vs national (from `q3a`).
2. Make chart 1 show the top 15 **national** employers instead, and compare the color mix.

---

## Part 6b: Reproducibility (a lesson learned the hard way)

Re-running the pipeline first produced *different* CSVs with the same numbers.
Three causes, all fixed:
1. **Ties in `ORDER BY`.** Two employers with 16 LCAs can come out in any order. Fix: always add a tie-breaker column (`ORDER BY n DESC, employer_parent`). See any `sql/analysis/*.sql` ORDER BY.
2. **Ties in `arg_max`.** See Part 3b.
3. **Line endings on Windows (CRLF vs LF).** Fix: `.gitattributes` with `* text=auto eol=lf`.

The test: run the pipeline twice and `diff -r` the outputs. They must be identical.

## Part 7: Things worth practicing until they're automatic

1. Dedup with `ROW_NUMBER() … = 1` (or `QUALIFY`).
2. Conditional aggregation: `count(*) FILTER (WHERE …)` / `sum(CASE WHEN … THEN 1 ELSE 0 END)`.
3. Share-of-total with `x / sum(x) OVER ()`.
4. YoY with `LAG()`.
5. Top-N per group with `ROW_NUMBER() OVER (PARTITION BY …)`.
6. NULL behaviour: `=`, `AND`, `coalesce`, `IS NOT DISTINCT FROM`, and the fact that aggregates skip NULLs.
7. `WHERE` vs `HAVING`.
8. Validating every join with row counts before and after.

If you can explain each of those using an example from *this* project, you're ready for most data-analyst SQL rounds.
