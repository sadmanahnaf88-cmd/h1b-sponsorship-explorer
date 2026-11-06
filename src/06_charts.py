"""
Step 6 - Static PNG charts for the README (matplotlib).

Reads the CSVs that src/run_sql.py saved in outputs/tables/ (so the charts
always match the SQL results exactly) and writes PNGs to outputs/charts/.

Design choices (kept consistent across charts):
  * Two colors only: blue = NYC (or tech), orange = national (or non-tech).
    The pair was checked for color-blind safety with a palette validator.
  * Thin bars, light grid, no top/right spines, values labeled directly
    where it helps reading, so color is never the only cue.
"""
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
TABLES = ROOT / "outputs" / "tables"
CHARTS = ROOT / "outputs" / "charts"

BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
FAMILIES = ["Data Analyst", "Business/BI Analyst", "Data Scientist", "Data Engineer", "Analytics Manager"]

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8, "axes.axisbelow": True,
})


def money(x, _=None):
    # "\$" because matplotlib treats a pair of "$" as math mode
    return "\\$" + f"{x/1000:,.0f}k"


ACRONYMS = {"EY", "IBM", "CVS", "ZS", "JPMORGAN", "PWC", "KPMG", "NYU", "BNY", "USAA", "GROUPM"}


def display_name(name: str) -> str:
    """'JPMORGAN CHASE' -> 'JPMorgan Chase', 'CVS HEALTH' -> 'CVS Health'."""
    fixes = {"JPMORGAN": "JPMorgan", "MCKINSEY": "McKinsey", "GROUPM": "GroupM"}
    words = []
    for w in name.split():
        words.append(fixes.get(w, w if w in ACRONYMS else w.capitalize()))
    return " ".join(words)


def title(ax, main, sub):
    ax.set_title(main, loc="left", fontsize=13, fontweight="bold", pad=24)
    ax.text(0, 1.02, sub, transform=ax.transAxes, fontsize=9.5, color=INK2, va="bottom")


def save(fig, name):
    fig.text(0.01, -0.03, "Source: U.S. DOL OFLC LCA disclosure data. Certified H-1B LCAs (applications, not approved visas).",
             fontsize=7.5, color=INK2)
    fig.savefig(CHARTS / name, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", name)


def chart_top_nyc_sponsors():
    df = pd.read_csv(TABLES / "q1b_top_employers_nyc.csv").head(15).iloc[::-1]
    fig, ax = plt.subplots(figsize=(8, 6.2))
    colors = [BLUE if t else ORANGE for t in df.is_tech]
    ax.barh([display_name(n) for n in df.employer_parent], df.nyc_data_lcas_fy22_25, color=colors, height=0.62)
    for y, v in enumerate(df.nyc_data_lcas_fy22_25):
        ax.text(v + 12, y, f"{v:,.0f}", va="center", fontsize=8.5, color=INK2)
    ax.grid(axis="y", visible=False)
    ax.set_xlabel("Certified data-role LCAs, NYC worksites, FY2022-FY2025")
    ax.legend(handles=[plt.Rectangle((0, 0), 1, 1, color=BLUE), plt.Rectangle((0, 0), 1, 1, color=ORANGE)],
              labels=["Tech employer", "Non-tech employer"], frameon=False, loc="lower right")
    title(ax, "Amazon leads NYC, but most of the top 15 are not tech companies",
          "Top 15 NYC sponsors of data/analytics roles")
    save(fig, "01_top_nyc_sponsors.png")


def chart_salary_by_family():
    df = pd.read_csv(TABLES / "q2a_salary_by_role_family.csv")
    piv = df.pivot(index="role_family", columns="geography", values="median").reindex(FAMILIES)
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = range(len(piv))
    for i, (fam, row) in enumerate(piv.iterrows()):          # connector line = the NYC premium
        ax.plot([row.National, row.NYC], [i, i], color=GRID, linewidth=3, zorder=1)
    ax.scatter(piv.National, y, color=ORANGE, s=70, zorder=2, label="National median")
    ax.scatter(piv.NYC, y, color=BLUE, s=70, zorder=2, label="NYC median")
    for i, (fam, row) in enumerate(piv.iterrows()):
        prem = (row.NYC / row.National - 1) * 100
        ax.text(max(row.NYC, row.National) + 2500, i, f"{money(row.NYC)} vs {money(row.National)}  ({prem:+.0f}%)",
                va="center", fontsize=8.5, color=INK2)
    ax.set_yticks(list(y), piv.index)
    ax.invert_yaxis()
    ax.xaxis.set_major_formatter(money)
    ax.set_xlim(80000, 215000)
    ax.grid(axis="y", visible=False)
    ax.legend(frameon=False, loc="upper right", fontsize=8.5)
    title(ax, "NYC pays a 2-20% premium on data-role offers",
          "Median annualized offered wage, FY2025, full-time certified H-1B LCAs")
    save(fig, "02_salary_nyc_vs_national.png")


def chart_non_tech_share():
    df = pd.read_csv(TABLES / "q4b_outside_tech_share.csv").set_index("role_family")
    order = FAMILIES + ["ALL DATA ROLES"]
    df = df.reindex(order)
    fig, ax = plt.subplots(figsize=(8, 4.2))
    y = list(range(len(df)))
    h = 0.36
    ax.barh([i - h / 2 for i in y], df.nyc_pct_non_tech, height=h, color=BLUE, label="NYC")
    ax.barh([i + h / 2 for i in y], df.national_pct_non_tech, height=h, color=ORANGE, label="National")
    for i, (a, b) in enumerate(zip(df.nyc_pct_non_tech, df.national_pct_non_tech)):
        ax.text(a + 1, i - h / 2, f"{a:.0f}%", va="center", fontsize=8.5, color=INK2)
        ax.text(b + 1, i + h / 2, f"{b:.0f}%", va="center", fontsize=8.5, color=INK2)
    ax.set_yticks(y, [o.title() if o.isupper() else o for o in order])
    ax.invert_yaxis()
    ax.set_xlim(0, 100)
    ax.axvline(50, color=INK2, linewidth=0.8, linestyle=":")
    ax.set_xlabel("% of certified data-role LCAs filed by non-tech employers, FY2022-FY2025")
    ax.grid(axis="y", visible=False)
    ax.legend(frameon=False, loc="lower right")
    title(ax, "In NYC, most data-role sponsorship happens outside tech",
          "Non-tech = not NAICS 51/5415/334 and not a big-tech parent (e.g. Amazon counts as tech)")
    save(fig, "03_non_tech_share.png")


def chart_like_for_like_trend():
    df = pd.read_csv(TABLES / "q3b_ytd_fy2026_vs_prior.csv")
    fig, axes = plt.subplots(1, 2, figsize=(9, 3.8))
    for ax, col, color, label in [(axes[0], "data_lcas_q1_q3", ORANGE, "National"),
                                  (axes[1], "nyc_data_lcas_q1_q3", BLUE, "NYC")]:
        ax.plot(df.fiscal_year, df[col], color=color, linewidth=2, marker="o", markersize=7)
        for x, v in zip(df.fiscal_year, df[col]):
            ax.annotate(f"{v:,.0f}", (x, v), textcoords="offset points", xytext=(0, 9),
                        ha="center", fontsize=8.5, color=INK2)
        ax.set_xticks(df.fiscal_year, [f"FY{str(y)[2:]}" for y in df.fiscal_year])
        ax.set_ylim(0, df[col].max() * 1.22)
        ax.set_xlim(df.fiscal_year.min() - 0.5, df.fiscal_year.max() + 0.5)
        ax.set_title(label, loc="left", fontsize=11, color=INK)
        ax.yaxis.set_major_formatter(lambda v, _: f"{v:,.0f}")
    fig.suptitle("Data-role LCAs, Oct-Jun of each fiscal year (FY2026 data ends June 2026)",
                 x=0.01, ha="left", fontsize=12, fontweight="bold")
    fig.tight_layout(rect=(0, 0.04, 1, 0.95))
    save(fig, "04_like_for_like_trend.png")


def chart_entry_level():
    df = pd.read_csv(TABLES / "q6a_entry_level_share.csv").set_index("role_family").reindex(FAMILIES)
    fig, ax = plt.subplots(figsize=(8, 3.8))
    y = list(range(len(df)))
    h = 0.36
    ax.barh([i - h / 2 for i in y], df.nyc_pct_level_1_2, height=h, color=BLUE, label="NYC")
    ax.barh([i + h / 2 for i in y], df.national_pct_level_1_2, height=h, color=ORANGE, label="National")
    for i, (a, b, w) in enumerate(zip(df.nyc_pct_level_1_2, df.national_pct_level_1_2, df.nyc_median_wage_level_1_2)):
        ax.text(a + 1, i - h / 2, f"{a:.0f}%  (NYC median {money(w)})", va="center", fontsize=8.5, color=INK2)
        ax.text(b + 1, i + h / 2, f"{b:.0f}%", va="center", fontsize=8.5, color=INK2)
    ax.set_yticks(y, df.index)
    ax.invert_yaxis()
    ax.set_xlim(0, 115)
    ax.set_xlabel("% of FY2025 certified data-role LCAs at DOL wage Level I or II")
    ax.grid(axis="y", visible=False)
    ax.legend(frameon=False, loc="lower right")
    title(ax, "Three in four analyst LCAs are filed at entry wage levels",
          "Level I/II = the prevailing-wage tiers used for less-experienced positions")
    save(fig, "05_entry_level_share.png")


if __name__ == "__main__":
    CHARTS.mkdir(parents=True, exist_ok=True)
    chart_top_nyc_sponsors()
    chart_salary_by_family()
    chart_non_tech_share()
    chart_like_for_like_trend()
    chart_entry_level()
