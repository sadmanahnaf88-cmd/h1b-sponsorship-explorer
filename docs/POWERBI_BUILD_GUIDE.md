# Power BI build guide

A step-by-step plan for building the H-1B Sponsorship Explorer report in
Power BI Desktop from the CSVs in `outputs/powerbi/`. Budget 3–5 hours the
first time. Measures come from `DAX_MEASURES.md`.

---

## 0. Which fact table?

| File | Rows | Use when |
|---|---:|---|
| `fact_lca_data_roles.csv` (24 MB, in git) | 202,909 | **Start here.** Everything about data roles. Fast to load. |
| `fact_lca.csv` (275 MB, git-ignored, rebuild with `python src/05_powerbi_export.py`) | 2,415,525 | You also want "data roles as a share of ALL LCAs". |

If you use the data-roles file, rename the query to `fact_lca` in Power Query
so the DAX works unchanged.

## 1. Load the data (Power Query)

1. **Home → Get data → Text/CSV** → load each of the 6 files (5 dims + 1 fact).
2. In **Transform data** (Power Query), set the column types **explicitly**.
   Don't trust auto-detect:

| Table | Column | Type | Why |
|---|---|---|---|
| all dims & fact | `*_key` (except below) | Whole number | relationship keys |
| `dim_industry`, `fact_lca` | `industry_key` | **Text** | NAICS codes vary in length ("5416", "541511") and include "UNKNOWN". As numbers they'd break. |
| `fact_lca` | `case_number` | Text | |
| `fact_lca` | `annual_wage`, `annual_prevailing_wage` | Decimal number | |
| `fact_lca` | `is_entry_level`, `is_full_time`, `is_tech`, `wage_ok_for_stats` | True/False | |
| `dim_date` | `date` | Date | |
| `dim_location`, `dim_role`, `dim_employer` | `is_*` columns | True/False | |

3. **Close & Apply.**

## 2. Build the star schema (Model view)

Create five relationships, all **one-to-many, single direction, dimension → fact**:

```
dim_date[date_key]         1 ──< * fact_lca[date_key]
dim_employer[employer_key] 1 ──< * fact_lca[employer_key]
dim_role[role_key]         1 ──< * fact_lca[role_key]
dim_location[location_key] 1 ──< * fact_lca[location_key]
dim_industry[industry_key] 1 ──< * fact_lca[industry_key]
```

Then:
- Select `dim_date` → **Table tools → Mark as date table** → column `date`.
- Hide every `*_key` column in the fact (right-click → Hide in report view). Report users should slice by dimension attributes, never by keys.
- Sort `dim_date[month_name]` by `month_num` (Column tools → Sort by column).
- Create the `_Measures` table and paste the measures from `DAX_MEASURES.md`.

*Why a star schema?* Each filter flows one way, from a small dimension to the
big fact. It is fast, unambiguous, and it's what interviewers expect you to
explain. Avoid bi-directional relationships unless you can say why you need one.

## 3. Global design

- **Canvas:** 16:9, 1280×720. Background: off-white `#FCFCFB`. Use one font (Segoe UI) throughout.
- **Colors:** blue `#2A78D6` = NYC, orange `#EB6834` = national/rest of U.S. Use them consistently on every page so readers learn them once. Gray `#52514E` for secondary text.
- **Header band** on every page: title (left), `Selected FY Label` card, and the `Caveat Text` card in small gray type.
- **Slicer row** directly under the header, in the same position on every page, synced across pages (**View → Sync slicers**):
  - Fiscal year (`dim_date[fiscal_year_label]`, dropdown, multi-select)
  - Role family (`dim_role[role_family]`, buttons/tiles)
  - Geography (`dim_location[nyc_vs_rest]`, buttons: New York City / Rest of U.S.)
  - Wage level (`fact_lca[wage_level]`, dropdown)

## 4. Pages

### Page 1: Overview ("Who sponsors data roles?")
| Position | Visual | Fields |
|---|---|---|
| Top row | 4 **cards** | `Total LCAs`, `Median Salary`, `NYC Share %`, `Non-Tech Share %` |
| Left, large | **Clustered bar** (top 15 employers) | Y: `dim_employer[employer_parent]`; X: `Total LCAs`; visual filter: `Employer Rank` ≤ 15; conditional color by `is_tech` (fx → field value, or two measures) |
| Right | **Line chart** | X: `dim_date[fiscal_year]`; Y: `Total LCAs`; legend: `dim_role[role_family]` |
| Bottom-right | **Donut** or 100% bar | `Total LCAs` by `role_family` (or use a bar; donuts with 5+ slices are hard to read) |

**Story:** "Amazon dominates, but most of the top 15 in NYC are banks, insurers
and consultancies." Click the "New York City" geography button to show it.

### Page 2: Salaries
| Visual | Fields |
|---|---|
| **Clustered bar** | Y: `role_family`; X: `Median Salary NYC`, `Median Salary National` (the two series = the two brand colors) |
| **Matrix** | Rows: `role_family`; Columns: `fact_lca[wage_level]`; Values: `Median Salary`, `NYC Salary Premium %`. Add conditional formatting (background color scale) on the premium |
| **Table: top cities** | `dim_location[city_label]`, `Total LCAs`, `Median Salary`; filter Top N = 15 by `Total LCAs` |
| **Box-plot substitute** | Clustered column: `Salary P25`, `Median Salary`, `Salary P75` by `role_family` (Power BI has no native box plot) |

Page filter: `fact_lca[wage_ok_for_stats] = True` (belt and braces: the measures already apply it).

### Page 3: Trends
| Visual | Fields |
|---|---|
| **Line chart** | X: `fiscal_year`; Y: `Total LCAs`; small multiples: `role_family` |
| **Column chart** | X: `fiscal_year`; Y: `LCAs YoY %` (diverging color: negative = orange, positive = blue) |
| **Like-for-like table** | Rows: `fiscal_year`; Values: `Total LCAs`, `LCAs Same Period Prior Year`, `Data Role Share %`, `Median Salary`. Page filter: `fiscal_quarter` is 1, 2, 3 |
| **Text box** | "FY2026 includes Oct 2025–Jun 2026 only. Compare like-for-like." |

### Page 4: Industries & hidden sponsors
| Visual | Fields |
|---|---|
| **Treemap** or bar | `dim_industry[industry_sector]` by `Total LCAs` (bars are more precise; a treemap looks nicer, so pick one) |
| **100% stacked bar** | Y: `nyc_vs_rest`; X: `Total LCAs`; legend: `fact_lca[is_tech]` (shows 55% vs 44% non-tech) |
| **Table: hidden sponsors** | `employer_parent`, `industry_sector` (from `dim_employer[main_industry_sector]`), `Total LCAs`, `Min LCAs In Any Year`, `Median Salary`, `Entry Level Share %`. Filters: `is_tech` = False, `Is Consistent Sponsor` = 1, years FY2022–FY2025 |

### Page 5: Entry-level finder (the page you'd actually use)
| Visual | Fields |
|---|---|
| **Bar** | `role_family` by `Entry Level Share %` |
| **Table** | `employer_parent`, `Total LCAs`, `Median Salary`, `role_family`. Filters: `is_entry_level` = True, geography = NYC, FY2024–FY2025. Sort by `Total LCAs` |
| **Slicer** | `dim_employer[employer_parent]` search box ("did company X sponsor analysts?") |
| **Drill-through target** | Create a drill-through page "Employer detail" with `employer_parent` as the drill-through field: job titles (`fact_lca[job_title]`), wage levels, salary by year |

### Optional page 6: About the data
A text page with the caveats from the README, the definitions of "data role"
and "tech", and a link to the GitHub repo. Hiring managers read this.

## 5. Finishing touches
- **Tooltips:** create a tooltip page (Page information → Allow use as tooltip, size Tooltip) showing `Median Salary`, `Entry Level Share %` and the top 3 job titles. Assign it to the employer bar chart.
- **Bookmarks:** "NYC view" and "National view" bookmarks driving the geography slicer, plus two buttons in the header.
- **Accessibility:** set alt text on every visual (Format → General → Alt text), and check tab order (View → Selection pane → Tab order).
- **Performance:** with the full 2.4M-row fact, open View → Performance analyzer. Each visual should load in under ~1 s. If not, remove `job_title` from visuals: it's the highest-cardinality column.

## 6. Validate against the SQL (do this before publishing)
Set slicers and compare against the CSVs in `outputs/tables/`:

| Check | Slicers | Expected | Source |
|---|---|---|---|
| Data-role LCAs, FY22–25, national | FY2022–FY2025, all roles | 167,799 | `q4b`, last row |
| Same, NYC | + NYC | 10,768 | `q4b` |
| Non-tech share, NYC | FY22–25, NYC | 54.9% | `q4b` |
| Median salary, Data Engineer, NYC, FY2025 | FY2025, Data Engineer, NYC | $150,000 | `q2a` |
| Entry-level share, Data Analyst, FY2025 | FY2025, Data Analyst | 76.0% | `q6a` |

If a number differs, the usual culprits are a missing relationship, a wrong
data type on `industry_key`, or a slicer you forgot was set.

## 7. Publish
Publishing to the Power BI service needs a work or school Microsoft account.
Many universities provide one, so try your student account. If you can publish,
*Publish to web* makes the report fully public, which is fine here because the
data is public. If you can't, commit the `.pbix` file and 2–3 screenshots to
the repo and embed the screenshots in the README. Hiring managers rarely open
the `.pbix` anyway.
