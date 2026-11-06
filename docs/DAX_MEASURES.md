# DAX measures: ready to paste

Create these in Power BI Desktop: **Modeling → New measure**, then paste one
block at a time. Put them all in a dedicated table so they're easy to find:
**Home → Enter data** → name it `_Measures` → load an empty table, then create
each measure with `_Measures` selected.

They assume the model from `POWERBI_BUILD_GUIDE.md`: fact table `fact_lca`
(or `fact_lca_data_roles`; if you load that one, rename it to `fact_lca` so
these measures work as written) related to `dim_date`, `dim_employer`,
`dim_role`, `dim_location` and `dim_industry`.

> **DAX in one paragraph.** A *measure* is a formula evaluated inside the
> **filter context** of each visual cell. For example, in a bar for "Data
> Analyst / FY2025", the formula only sees those rows. `CALCULATE` is the one
> function that *changes* the filter context: it adds, replaces, or removes
> filters, then evaluates. Almost every measure below is "a base measure
> wrapped in `CALCULATE` with a different filter".

---

## 1. Base counts

```DAX
Total LCAs = COUNTROWS ( fact_lca )
```
Counts certified LCAs (rows) in the current filter context. **This is the
main unit of the project.** Each row is one application, not one person.

```DAX
Total Positions = SUM ( fact_lca[total_worker_positions] )
```
Worker positions requested. Usually larger than LCAs, because one LCA can
request several. Show it only as a secondary number (see DECISIONS.md §3).

```DAX
Sponsoring Employers = DISTINCTCOUNT ( fact_lca[employer_key] )
```
How many distinct (cleaned) employers filed in the current context.

```DAX
Sponsoring Parent Companies = DISTINCTCOUNT ( dim_employer[employer_parent] )
```
Same, after the parent roll-up (Amazon's 25 legal entities count once).
`DISTINCTCOUNT` on a dimension column works because the fact filters the
dimension through the relationship. Note: this needs the relationship's
cross-filter direction set to *Both*, or use the version below, which works
with the default single direction:

```DAX
Sponsoring Parent Companies (safe) =
CALCULATE (
    DISTINCTCOUNT ( dim_employer[employer_parent] ),
    fact_lca
)
```
Passing the fact table as a filter argument makes the dimension see only
employers that have rows in the current context.

## 2. Salary

```DAX
Median Salary =
CALCULATE (
    MEDIAN ( fact_lca[annual_wage] ),
    fact_lca[wage_ok_for_stats] = TRUE ()
)
```
Median annualized offered wage, excluding part-time and flagged rows, the same
rule as the SQL. **Use the median, not the average:** salaries are right-skewed,
and a handful of $900k rows would pull an average up.

```DAX
Salary P25 =
CALCULATE ( PERCENTILE.INC ( fact_lca[annual_wage], 0.25 ), fact_lca[wage_ok_for_stats] = TRUE () )

Salary P75 =
CALCULATE ( PERCENTILE.INC ( fact_lca[annual_wage], 0.75 ), fact_lca[wage_ok_for_stats] = TRUE () )
```
The 25th and 75th percentiles. P75 − P25 (the interquartile range) shows how
spread out offers are. Use them for the error bars or the tooltip on a salary chart.

```DAX
Median Prevailing Wage =
CALCULATE ( MEDIAN ( fact_lca[annual_prevailing_wage] ), fact_lca[wage_ok_for_stats] = TRUE () )

Offer vs Prevailing % = DIVIDE ( [Median Salary], [Median Prevailing Wage] ) - 1
```
How far above the legal minimum (the prevailing wage) employers offer. `DIVIDE`
returns blank instead of an error when the denominator is 0. Always prefer it to `/`.

## 3. NYC vs national

```DAX
NYC LCAs =
CALCULATE ( [Total LCAs], dim_location[is_nyc] = TRUE () )
```
Adds the filter "worksite is NYC" on top of whatever the visual already filters.

```DAX
National LCAs =
CALCULATE ( [Total LCAs], REMOVEFILTERS ( dim_location ) )
```
`REMOVEFILTERS` drops any location filter (e.g. a city slicer), so this is
always the U.S. total for the other filters in play (year, role...).

```DAX
NYC Share % = DIVIDE ( [NYC LCAs], [National LCAs] )
```
NYC's share of all LCAs in the current context. Format as a percentage.

```DAX
Median Salary NYC =
CALCULATE ( [Median Salary], dim_location[is_nyc] = TRUE () )

Median Salary National =
CALCULATE ( [Median Salary], REMOVEFILTERS ( dim_location ) )

NYC Salary Premium % = DIVIDE ( [Median Salary NYC], [Median Salary National] ) - 1
```
Reproduces finding #2 (e.g. Data Engineer ≈ +19% in FY2025).

## 4. Year over year

```DAX
LCAs Prior Year =
VAR CurrentFY = SELECTEDVALUE ( dim_date[fiscal_year] )
RETURN
    CALCULATE (
        [Total LCAs],
        REMOVEFILTERS ( dim_date ),
        dim_date[fiscal_year] = CurrentFY - 1
    )
```
`SELECTEDVALUE` returns the fiscal year when exactly one is in context
(e.g. on an FY axis), otherwise blank. We **remove all date filters** and
put back "the previous fiscal year". We don't use the built-in
`SAMEPERIODLASTYEAR`, because that works on *calendar* dates and our years are
federal fiscal years (October to September).

```DAX
LCAs YoY % = DIVIDE ( [Total LCAs] - [LCAs Prior Year], [LCAs Prior Year] )
```
Blank for the first year (no prior year), which is what you want.

```DAX
Median Salary Prior Year =
VAR CurrentFY = SELECTEDVALUE ( dim_date[fiscal_year] )
RETURN
    CALCULATE ( [Median Salary], REMOVEFILTERS ( dim_date ), dim_date[fiscal_year] = CurrentFY - 1 )

Median Salary YoY % = DIVIDE ( [Median Salary] - [Median Salary Prior Year], [Median Salary Prior Year] )
```

```DAX
LCAs Same Period Prior Year =
VAR CurrentFY = SELECTEDVALUE ( dim_date[fiscal_year] )
VAR QuartersInContext = VALUES ( dim_date[fiscal_quarter] )
RETURN
    CALCULATE (
        [Total LCAs],
        REMOVEFILTERS ( dim_date ),
        dim_date[fiscal_year] = CurrentFY - 1,
        dim_date[fiscal_quarter] IN QuartersInContext
    )
```
**Like-for-like comparison for the partial FY2026.** `VALUES` captures which
fiscal quarters are visible (Q1–Q3 when FY2026 is selected), and the prior year
is restricted to the same quarters. Pair it with a page filter of
fiscal_quarter ∈ {1, 2, 3} to reproduce `q3b`.

## 5. Mix and shares

```DAX
Data Role LCAs = CALCULATE ( [Total LCAs], dim_role[is_data_role] = TRUE () )

Data Role Share % = DIVIDE ( [Data Role LCAs], CALCULATE ( [Total LCAs], REMOVEFILTERS ( dim_role ) ) )
```
Share of all LCAs that are data roles. Only meaningful with the full
`fact_lca` (the data-roles-only fact is 100% by construction).

```DAX
Non-Tech Share % =
DIVIDE ( CALCULATE ( [Total LCAs], fact_lca[is_tech] = FALSE () ), [Total LCAs] )
```
Finding #1. `is_tech` lives on the fact row because it depends on both the
employer and the NAICS code of that specific filing.

```DAX
Entry Level Share % =
DIVIDE ( CALCULATE ( [Total LCAs], fact_lca[is_entry_level] = TRUE () ),
         CALCULATE ( [Total LCAs], NOT ISBLANK ( fact_lca[wage_level] ) ) )
```
Finding #3: Level I/II share. The denominator excludes rows with no wage
level recorded (6.8% of certified LCAs), matching `q6a`.

## 6. Ranking and "hidden sponsors"

```DAX
Employer Rank =
IF (
    HASONEVALUE ( dim_employer[employer_parent] ),
    RANKX ( ALLSELECTED ( dim_employer[employer_parent] ), [Total LCAs], , DESC, DENSE )
)
```
Rank of an employer among those visible after slicers (`ALLSELECTED`
respects slicers but ignores the table's own row grouping). `HASONEVALUE`
blanks the total row. Use it in a table, plus a visual-level filter
"Employer Rank ≤ 25".

```DAX
Fiscal Years Active =
CALCULATE ( DISTINCTCOUNT ( dim_date[fiscal_year] ), fact_lca )
```
Fiscal years in which this employer filed at least one LCA in the current context.

```DAX
Min LCAs In Any Year =
MINX ( VALUES ( dim_date[fiscal_year] ), [Total LCAs] )
```
`MINX` iterates over each fiscal year in context and returns the smallest
yearly count. Iterators ("X" functions) evaluate an expression row by row
over a table, like a loop.

```DAX
Is Consistent Sponsor =
VAR YearsInScope = 4   -- FY2022..FY2025: set the page's year slicer to these
RETURN IF ( [Fiscal Years Active] = YearsInScope && [Min LCAs In Any Year] >= 2, 1, 0 )
```
Reproduces the NYC hidden-sponsor rule (`q5b`): add as a visual-level filter
`= 1` on an employer table, with a page filter of fiscal_year 2022–2025,
is_nyc = TRUE, is_tech = FALSE.

## 7. Labels and helpers

```DAX
Selected FY Label =
IF ( HASONEVALUE ( dim_date[fiscal_year_label] ), VALUES ( dim_date[fiscal_year_label] ), "FY2022 – FY2026" )
```
Dynamic title text, e.g. "FY2026 (Q1-Q3 only)". Use it in a card or as a
visual title via **Format → Title → fx**.

```DAX
Caveat Text = "Certified LCAs (applications), not approved H-1B visas or hires."
```
Put it in a small card on every page. Recruiters notice this kind of care.

---

### Formatting checklist
- `%` measures → Format: Percentage, 1 decimal.
- Salary measures → Currency, 0 decimals (display units: Thousands gives "$114K").
- Counts → Whole number with a thousands separator.
