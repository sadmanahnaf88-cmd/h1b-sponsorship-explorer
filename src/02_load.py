"""
Step 2 - Convert raw Excel files to Parquet and load them into DuckDB.

What this script does, in order:
  1. Reads every data/raw/LCA_Disclosure_Data_FY*_Q*.xlsx with python-calamine
     (a Rust Excel reader, ~10x faster than openpyxl on 100 MB files).
  2. Records each file's actual column list (we do NOT assume columns are the
     same every year) -> docs/column_inventory.md
  3. Renames columns to ONE canonical schema using COLUMN_MAP below. Any column
     that is missing in a file becomes NULL; any extra column is reported.
  4. Keeps only the columns the analysis needs. Personal contact fields
     (point-of-contact names, emails, phones, attorney details) are dropped on
     purpose: we don't need them and shouldn't redistribute them.
  5. Writes one Parquet file per source file to data/processed/raw_parquet/.
  6. Creates DuckDB table `lca_raw` (all rows, all statuses) in data/h1b.duckdb.

Every value is stored as TEXT at this stage. Typing (dates, numbers) happens
in the cleaning step, in SQL, where bad values can be counted instead of
silently crashing the load.
"""
import datetime as dt
import re
from pathlib import Path

import duckdb
import pandas as pd
from python_calamine import CalamineWorkbook

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
PQ_DIR = ROOT / "data" / "processed" / "raw_parquet"
DB_PATH = ROOT / "data" / "h1b.duckdb"
DOCS = ROOT / "docs"

# canonical_name -> list of names it has appeared under in DOL files.
# The FY2022+ layouts turned out to share names, but the map makes the
# assumption explicit and the inventory below proves it per file.
COLUMN_MAP = {
    "case_number":            ["CASE_NUMBER"],
    "case_status":            ["CASE_STATUS"],
    "received_date":          ["RECEIVED_DATE"],
    "decision_date":          ["DECISION_DATE"],
    "visa_class":             ["VISA_CLASS"],
    "job_title":              ["JOB_TITLE"],
    "soc_code":               ["SOC_CODE"],
    "soc_title":              ["SOC_TITLE"],
    "full_time_position":     ["FULL_TIME_POSITION"],
    "begin_date":             ["BEGIN_DATE"],
    "end_date":               ["END_DATE"],
    "total_worker_positions": ["TOTAL_WORKER_POSITIONS"],
    "new_employment":         ["NEW_EMPLOYMENT"],
    "continued_employment":   ["CONTINUED_EMPLOYMENT"],
    "change_previous_employment": ["CHANGE_PREVIOUS_EMPLOYMENT"],
    "new_concurrent_employment":  ["NEW_CONCURRENT_EMPLOYMENT"],
    "change_employer":        ["CHANGE_EMPLOYER"],
    "amended_petition":       ["AMENDED_PETITION"],
    "employer_name":          ["EMPLOYER_NAME"],
    "trade_name_dba":         ["TRADE_NAME_DBA"],
    "employer_city":          ["EMPLOYER_CITY"],
    "employer_state":         ["EMPLOYER_STATE"],
    "employer_postal_code":   ["EMPLOYER_POSTAL_CODE"],
    "naics_code":             ["NAICS_CODE"],
    "employer_fein":          ["EMPLOYER_FEIN"],      # only FY2024+ files (business tax ID)
    "worksite_workers":       ["WORKSITE_WORKERS"],
    "secondary_entity":       ["SECONDARY_ENTITY"],
    "worksite_city":          ["WORKSITE_CITY"],
    "worksite_county":        ["WORKSITE_COUNTY"],
    "worksite_state":         ["WORKSITE_STATE"],
    "worksite_postal_code":   ["WORKSITE_POSTAL_CODE"],
    "wage_rate_from":         ["WAGE_RATE_OF_PAY_FROM"],
    "wage_rate_to":           ["WAGE_RATE_OF_PAY_TO"],
    "wage_unit":              ["WAGE_UNIT_OF_PAY"],
    "prevailing_wage":        ["PREVAILING_WAGE"],
    "pw_unit":                ["PW_UNIT_OF_PAY"],
    "pw_wage_level":          ["PW_WAGE_LEVEL"],
    "total_worksite_locations": ["TOTAL_WORKSITE_LOCATIONS"],
    "h1b_dependent":          ["H_1B_DEPENDENT", "H-1B_DEPENDENT"],  # FY2025 Q1 uses a hyphen
    "willful_violator":       ["WILLFUL_VIOLATOR"],
}
# Columns we deliberately drop (personal / contact details, not needed).
PII_PATTERN = re.compile(r"(POC|AGENT|ATTORNEY|LAWFIRM|PREPARER|PHONE|EMAIL|ADDRESS|HIGHEST)")


def to_text(v):
    """Convert one Excel cell to text consistently.

    - empty -> None
    - dates -> ISO 'YYYY-MM-DD'
    - floats that are whole numbers -> no '.0' (Excel stores 7652 as 7652.0)
    """
    if v is None or v == "":
        return None
    if isinstance(v, (dt.datetime, dt.date)):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() else repr(v)
    s = str(v).strip()
    return s or None


def read_xlsx(path: Path) -> tuple[list[str], list[list]]:
    wb = CalamineWorkbook.from_path(str(path))
    sheet = wb.get_sheet_by_index(0)
    rows = sheet.to_python(skip_empty_area=False)
    header = [str(h).strip() for h in rows[0]]
    return header, rows[1:]


def main():
    PQ_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(RAW.glob("LCA_Disclosure_Data_FY*_Q*.xlsx"))
    inventory = {}      # file -> list of raw columns
    log_rows = []       # per-file load log
    reverse = {raw: canon for canon, raws in COLUMN_MAP.items() for raw in raws}

    for path in files:
        m = re.search(r"FY(\d{4})_Q(\d)", path.name)
        fy, q = int(m.group(1)), int(m.group(2))
        header, data = read_xlsx(path)
        inventory[path.name] = header

        # Build a dataframe of only the mapped columns, as text.
        idx = {canon: None for canon in COLUMN_MAP}
        for i, col in enumerate(header):
            if col in reverse:
                idx[reverse[col]] = i
        missing = [c for c, i in idx.items() if i is None]
        unmapped = [c for c in header if c not in reverse and not PII_PATTERN.search(c)]

        out = {}
        for canon, i in idx.items():
            out[canon] = [None] * len(data) if i is None else [to_text(r[i]) for r in data]
        df = pd.DataFrame(out, dtype="string")
        # Drop fully blank trailing rows Excel sometimes includes.
        df = df[df["case_number"].notna()]
        df["source_file"] = path.name
        df["file_fy"] = fy
        df["file_quarter"] = q
        df.to_parquet(PQ_DIR / path.name.replace(".xlsx", ".parquet"), index=False)

        log_rows.append((path.name, len(data), len(df), len(header), missing, unmapped))
        print(f"{path.name}: {len(df):,} rows, {len(header)} cols, missing={missing}, "
              f"unmapped non-PII={unmapped}", flush=True)

    # ---- Load all Parquet into DuckDB ----
    con = duckdb.connect(str(DB_PATH))
    con.execute(f"""
        CREATE OR REPLACE TABLE lca_raw AS
        SELECT * FROM read_parquet('{PQ_DIR.as_posix()}/*.parquet', union_by_name = true)
    """)
    total = con.execute("SELECT count(*) FROM lca_raw").fetchone()[0]
    parquet_total = sum(r[2] for r in log_rows)
    assert total == parquet_total, f"row count mismatch: duckdb {total} vs parquet {parquet_total}"
    print(f"lca_raw: {total:,} rows (matches sum of Parquet files)")
    con.close()

    write_inventory(inventory, log_rows, total)


def write_inventory(inventory, log_rows, total):
    """docs/column_inventory.md: proof of which columns each file had."""
    all_cols = sorted({c for cols in inventory.values() for c in cols},
                      key=lambda c: min(cols.index(c) if c in cols else 999 for cols in inventory.values()))
    files = list(inventory)
    short = [re.search(r"FY\d{4}_Q\d", f).group(0) for f in files]
    lines = ["# Column inventory (generated by src/02_load.py)", "",
             "Every raw file's header was read and compared. `x` = column present.", "",
             "## Load log", "",
             "| File | Excel data rows | Rows kept (non-blank case #) | Columns | Canonical columns missing | Non-PII columns not mapped |",
             "|---|---:|---:|---:|---|---|"]
    for name, n_raw, n_kept, n_cols, missing, unmapped in log_rows:
        lines.append(f"| {name} | {n_raw:,} | {n_kept:,} | {n_cols} | {', '.join(missing) or '-'} | {', '.join(unmapped) or '-'} |")
    lines += ["", f"**Total rows loaded into `lca_raw`: {total:,}**", "",
              "## Column presence by file", "",
              "| Raw column | " + " | ".join(short) + " | maps to |",
              "|---|" + "---|" * len(short) + "---|"]
    reverse = {raw: canon for canon, raws in COLUMN_MAP.items() for raw in raws}
    for c in all_cols:
        marks = " | ".join("x" if c in inventory[f] else "" for f in files)
        target = reverse.get(c, "(dropped: personal/contact)" if PII_PATTERN.search(c) else "(not used)")
        lines.append(f"| {c} | {marks} | {target} |")
    (DOCS / "column_inventory.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
