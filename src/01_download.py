"""
Step 1 - Download DOL OFLC LCA disclosure files.

Source page: https://www.dol.gov/agencies/eta/foreign-labor/performance
Files are published quarterly as Excel workbooks. We download FY2022-FY2025
(all four quarters each) plus the latest FY2026 file posted (Q3).

Re-running is safe: files that already exist with the expected size are skipped.
Raw files land in data/raw/ which is git-ignored (too large for git).
"""
import sys
import urllib.request
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
BASE = "https://www.dol.gov/sites/dolgov/files/ETA/oflc/pdfs/"

# (filename, url). URLs copied from the DOL performance page on 2026-11-06.
FILES = []
for fy in (2022, 2023, 2024, 2025):
    for q in (1, 2, 3, 4):
        name = f"LCA_Disclosure_Data_FY{fy}_Q{q}.xlsx"
        FILES.append((name, BASE + name))
# FY2026 Q3 lives under a different path on the page.
FILES.append(("LCA_Disclosure_Data_FY2026_Q3.xlsx",
              "https://www.dol.gov/media/LCA_Disclosure_Data_FY2026_Q3.xlsx"))


def download(name: str, url: str) -> None:
    dest = RAW_DIR / name
    # HEAD request first so we can skip completed downloads.
    with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as r:
        expected = int(r.headers.get("Content-Length", 0))
    if dest.exists() and dest.stat().st_size == expected:
        print(f"skip  {name} ({expected/1e6:.1f} MB, already complete)", flush=True)
        return
    tmp = dest.with_suffix(".part")
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    size = tmp.stat().st_size
    if expected and size != expected:
        raise RuntimeError(f"{name}: got {size} bytes, expected {expected}")
    tmp.replace(dest)
    print(f"done  {name} ({size/1e6:.1f} MB)", flush=True)


if __name__ == "__main__":
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, url in FILES:
        try:
            download(name, url)
        except Exception as e:  # keep going, report at the end
            print(f"FAIL  {name}: {e}", flush=True)
            failures.append(name)
    print("failures:", failures or "none")
    sys.exit(1 if failures else 0)
