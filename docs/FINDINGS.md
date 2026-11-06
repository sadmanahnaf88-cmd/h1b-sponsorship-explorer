# Findings: how I'd explain them in an interview

**Ground rule for every sentence below:** these are counts of *certified Labor
Condition Applications (LCAs)*, not H-1B visas or hires. An LCA is the first
step an employer takes. One person can be covered by several LCAs, and many
never turn into a petition (for example, when a new hire isn't selected in
the H-1B cap lottery). So "sponsors" here means "employers that file to sponsor". It is a
strong signal of *willingness*, not a count of people.

Data roles = Data Analyst, Business/BI Analyst, Data Scientist, Data Engineer and
Analytics Manager (see DECISIONS.md §7). Complete years are FY2022–FY2025;
FY2026 covers Oct 2025–Jun 2026.

Every number has a source query in `sql/analysis/` and a saved result in `outputs/tables/`.

---

## 1. In NYC, most data-role sponsorship comes from outside tech

> "Nationally, 44% of certified data-role LCAs come from non-tech employers.
> In New York City it's **55%**, and for Data Analyst roles specifically it's
> **67%**, two out of three. Finance and insurance alone is **23%** of NYC
> data-role LCAs, versus 12% in the rest of the country. If you're an
> international student targeting analyst roles in NYC and you only apply to
> tech companies, you're skipping most of the market that sponsors."

| | NYC | National |
|---|---:|---:|
| Data-role LCAs, FY22–25 | 10,768 | 167,799 |
| % from non-tech employers (all data roles) | **54.9%** | 44.3% |
| % non-tech: Data Analyst | **67.4%** | 56.7% |
| % non-tech: Analytics Manager | 78.1% | 72.1% |
| % non-tech: Data Scientist | 52.7% | 48.3% |
| % non-tech: Data Engineer | 44.4% | 36.9% |
| % non-tech: Business/BI Analyst | 43.1% | 33.7% |
| % from Finance & Insurance (NAICS 52) | **23.0%** | 12.4% (rest of U.S.) |

- *Source:* `q4b_outside_tech_share.sql`, `q0_headline_numbers.sql`, `q4a_industry_breakdown.sql`
- *Robustness:* if you also exclude consulting, accounting and staffing firms, the NYC share is still **44.6%** vs 37.3% for the rest of the U.S. (`q0`, column `data_pct_non_tech_non_consulting`). The gap holds.
- *How "tech" is defined matters:* Amazon files under a retail NAICS code. I override that with a big-tech list. Without the override, the non-tech share would be inflated.

## 2. NYC offers carry a 13–20% premium for analyst, scientist and engineer roles, but not for managers

> "Comparing median offered base wages in FY2025, NYC data engineers are
> offered **$150k vs $126k** nationally (+19%), data scientists **$163k vs $143k**
> (+14%), and data analysts **$114k vs $99k** (+15%). Analytics managers are
> the exception: almost no premium (+2%). The premium also grows with seniority.
> For data analysts it's +6% at Level I but +20% at Level IV."

| FY2025 median offered wage | NYC | National | NYC premium |
|---|---:|---:|---:|
| Data Analyst | $113,745 | $99,100 | +14.8% |
| Business/BI Analyst | $120,000 | $106,000 | +13.2% |
| Data Scientist | $162,825 | $142,773 | +14.0% |
| Data Engineer | $150,000 | $125,571 | +19.5% |
| Analytics Manager | $157,656 | $155,000 | +1.7% |

Data Analyst premium by wage level (`q2b`): Level I +5.5%, II +14.8%, III +17.0%, IV +20.1%.

- *Context from `q2c`:* among the cities with the most data LCAs, NYC's all-data-role median ($142.6k) is below San Francisco ($175k), San Jose ($172.7k) and Seattle ($151k), but above Chicago ($118k), Boston ($127k) and Austin ($125k).
- *Caveats:* these are **base** wages from the bottom of any posted range. Bonuses and equity are excluded. That understates finance (bonus-heavy) and big tech (equity-heavy). n is small for some NYC × level cells (e.g. 26 Level I analytics managers), so I don't quote those.

## 3. Three in four analyst LCAs are filed at entry-level wage tiers

> "In FY2025, **76%** of Data Analyst LCAs nationally were filed at DOL wage
> Level I or II, the tiers for less-experienced positions, and **33%** at
> Level I alone. NYC is about the same (75%), with a median Level I/II offer
> of **$103k**. For data scientists and engineers it's closer to 58–62%,
> and for analytics managers 24%. Analyst roles are where sponsorship and
> entry level overlap most."

| FY2025 | National % Level I/II | National % Level I | NYC % Level I/II | NYC median offer, Level I/II |
|---|---:|---:|---:|---:|
| Data Analyst | **76.0%** | 32.6% | 75.4% | **$103,259** |
| Business/BI Analyst | 74.9% | 23.9% | 76.3% | $111,966 |
| Data Engineer | 62.2% | 15.1% | 58.3% | $125,000 |
| Data Scientist | 57.7% | 16.0% | 56.7% | $135,914 |
| Analytics Manager | 24.1% | 3.5% | 37.6% | $130,000 |
| All data roles | 63.1% | 19.1% | 61.6% | $119,200 |

- *Source:* `q6a_entry_level_share.sql`. Employer list: `q6b_entry_level_employers_nyc.sql`.
- *Caveat:* the level describes how the employer classified the job, not the person hired. Employers also have a cost incentive to choose lower levels.

## 4. NYC sponsorship is concentrated at the top, with a long tail of small sponsors

> "Amazon alone filed **10.8%** of NYC's data-role LCAs over four years, and
> the top 10 employers filed **27%**. Outside NYC the top 10 account for only 18%.
> But the tail is long: **2,464** different employers filed at least one NYC
> data-role LCA, and **1,341** of them filed exactly one in four years. Those
> one-off sponsors are invisible on 'top sponsor' lists."

- *Source:* `q0_headline_numbers.sql`, `q1b_top_employers_nyc.sql`
- NYC top 10 (FY22–25): Amazon 1,166 · Meta 399 · Aetna 232 · American Express 219 · Capital One 192 · Google 175 · McKinsey 158 · CVS Health 133 · JPMorgan Chase 122 · EY 116.

## 5. "Hidden sponsors": NYC employers outside tech that file every single year

> "I defined a hidden sponsor as an employer that isn't tech, consulting,
> accounting or staffing, and that filed data-role LCAs in NYC in **every one of
> the last four fiscal years**. The list is mostly banks, insurers and
> hospitals. A few stand out for entry-level candidates. **Capital One**: 192
> NYC data LCAs, 80% at Level I/II. **Morgan Stanley**: 83, 94% Level I/II.
> **Goldman Sachs**: 72, 85%. **Icahn School of Medicine at Mount Sinai**: 53,
> 87%, though with a lower median offer ($86.5k)."

| NYC, FY22–25 | Data LCAs | Fewest in any year | Most common role | Median offer | % Level I/II |
|---|---:|---:|---|---:|---:|
| Aetna | 232 | 48 | Data Scientist | $148,835 | 31% |
| American Express | 219 | 42 | Analytics Manager | $135,393 | 54% |
| Capital One | 192 | 33 | Data Scientist | $111,966 | 80% |
| CVS Health | 133 | 23 | Data Scientist | $138,000 | 43% |
| JPMorgan Chase | 122 | 26 | Data Scientist | $159,775 | 31% |
| Citi | 89 | 17 | Data Analyst | $163,238 | 38% |
| Morgan Stanley | 83 | 16 | Data Scientist | $150,000 | 94% |
| Goldman Sachs | 72 | 10 | Business/BI Analyst | $121,000 | 85% |
| Icahn School of Medicine at Mount Sinai | 53 | 7 | Data Scientist | $86,500 | 87% |
| NYU Grossman School of Medicine | 38 | 3 | Data Analyst | $94,300 | 87% |

Full list of 30: `outputs/tables/q5b_hidden_sponsors_nyc.csv`. National version: `q5a` (led by Walmart, Capital One, CVS, Discover, JPMorgan, Aetna, Visa).

## 6. Trend: a dip in FY2023, recovery through FY2025, and a softer FY2026

> "Data-role LCAs fell about **15%** in FY2023, then recovered. By FY2025 they
> were **3% above** FY2022 (45,683 vs 44,231). FY2026 is only nine months in,
> so I compare October–June with October–June: data-role LCAs are down
> **5.6%** from the same period in FY2025, but *all* LCAs are down more
> (−8.4%). So data roles' share of all LCAs actually reached a five-year high
> of **8.95%**. NYC held up better (−2.0%), and its median data-role offer rose
> **6.3%** to $150k."

| Oct–Jun of fiscal year | All certified LCAs | Data-role LCAs | NYC data-role LCAs | Data share | Median data offer | NYC median data offer |
|---|---:|---:|---:|---:|---:|---:|
| FY2022 | 441,022 | 36,711 | 2,388 | 8.32% | $108,160 | $122,500 |
| FY2023 | 359,767 | 28,704 | 1,803 | 7.98% | $113,090 | $130,000 |
| FY2024 | 384,726 | 32,123 | 2,128 | 8.35% | $114,000 | $135,782 |
| FY2025 | 427,977 | 37,210 | 2,424 | 8.69% | $120,000 | $141,170 |
| FY2026 | 392,175 | 35,110 | 2,376 | **8.95%** | $123,760 | **$150,000** |

- By family, FY2022 → FY2025 (full years, `q3a`): Data Scientist +11.8%, Analytics Manager +20.6%, Data Analyst +10.8%, Data Engineer +3.5%, **Business/BI Analyst −12.2%**. BI is the only family still below FY2022.
- *What I would NOT claim:* why FY2026 is down. A September 2025 presidential proclamation added a $100,000 payment to certain new H-1B petitions, which is plausible context, but this dataset can't isolate its effect. LCAs are filed before petitions, and FY2026 Q4 isn't published yet. I'd say "worth watching", not "caused by".

---

## How I'd answer follow-ups

- **"Isn't this just counting paperwork?"** Yes, and that's the point. I'm measuring willingness to sponsor, which is exactly what a job seeker needs to know. I don't use it as a hiring count. I also count cases, not `total_worker_positions`, to avoid "up to 50 workers" style inflation.
- **"How did you decide what a data role is?"** Ordered keyword rules on the job title, with SOC codes as a fallback only for generic titles, and every row traceable to its rule. Then a manual spot-check of 20 rows per family (≈97–98% looked right). DECISIONS.md §7.
- **"What would change your conclusions?"** Adding ML engineers to Data Scientist would make it more tech-heavy. Counting Jersey City as NYC would add a large finance and IT-services hub. Using the top of the wage range would raise every median by up to ~20%.
