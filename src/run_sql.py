"""
Tiny helper: run one or more .sql files against data/h1b.duckdb.

Usage:
    python src/run_sql.py sql/03_clean.sql            # run a build script
    python src/run_sql.py sql/analysis/q1_*.sql --csv # run analysis queries,
                                                      # save results to outputs/tables/

A file may contain several statements separated by ';'. The result of the
LAST statement that returns rows is printed (and saved with --csv).
"""
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "h1b.duckdb"
TABLES = ROOT / "outputs" / "tables"


def run_file(con, path: Path, save_csv: bool):
    sql = path.read_text(encoding="utf-8")
    # DuckDB's execute() runs all statements; the returned relation is the last one.
    result = con.execute(sql)
    try:
        df = result.fetchdf()
    except duckdb.InvalidInputException:
        df = None  # last statement returned nothing (e.g. CREATE TABLE)
    print(f"\n=== {path.name} ===")
    if df is not None and len(df.columns):
        with __import__("pandas").option_context("display.width", 200, "display.max_columns", 20,
                                                 "display.max_rows", 60):
            print(df)
        if save_csv:
            TABLES.mkdir(parents=True, exist_ok=True)
            df.to_csv(TABLES / (path.stem + ".csv"), index=False)
    else:
        print("(ok)")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    save = "--csv" in sys.argv
    con = duckdb.connect(str(DB_PATH))
    for pattern in args:
        p = Path(pattern)
        files = sorted(ROOT.glob(pattern)) if any(c in pattern for c in "*?") else [ROOT / p if not p.is_absolute() else p]
        for f in files:
            run_file(con, f, save)
    con.close()
