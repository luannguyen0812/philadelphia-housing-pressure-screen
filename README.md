# Housing Pressure Screening for Philadelphia

A reproducible screening instrument that ranks Philadelphia ZIP/ZCTAs on
**housing pressure and potential displacement risk**, narrows 48 measurable
areas to two case studies, forecasts their transaction activity, and turns the
evidence into eight costed-by-lead-time City actions — delivered as an
interactive Tableau dashboard.

**BSAN 710 Capstone · Drexel University, LeBow College of Business · Fall 2026**
Client: City of Philadelphia, Office of Innovation and Technology

**[▶ Open the live dashboard](https://public.tableau.com/app/profile/luan.nguyen1531/viz/PhiladelphiaHousingPressureDashboard/PhiladelphiaHousingPressureContextTrajectoryandResponse)** — *Philadelphia Housing Pressure: Context, Trajectory, and Response* (Tableau Public)

---

## What the deliverable actually is

Not a price analysis and not an affordability ratio. The end product is a
**decision instrument** with four parts:

| # | Artefact | What a decision-maker gets |
|---|---|---|
| 1 | **37-ZIP screening scorecard** | Every measurable Philadelphia ZIP ranked on six separate measures, with a published coverage gate |
| 2 | **Two case-study dossiers** | 19132 and 19143 documented measure by measure, against the city benchmark |
| 3 | **Validated forecast** | Monthly transaction path to 2035 with uncertainty bands, chosen on two out-of-sample holdouts |
| 4 | **Interactive dashboard + action matrix** | One Tableau model where City staff inspect any qualifying ZIP and read the response each signal implies |

**Price-to-income is one of six measures.** It is an input to the screen, not the
output. Any summary of this work that stops at price-to-income is describing
step four of about fifteen.

---

## The result, end to end

```
48 ZIP/ZCTAs with sale history
   └─ coverage gate ──────────────► 37 measurable
        └─ six-measure screen ────► 5 shortlisted
             └─ profile contrast ──► 2 case studies: 19132 (distress), 19143 (price)
                  └─ validation ───► forecast, permits, eviction, reconciliation
                       └─ response ► 8 time-stamped actions
```

Thirteen ZCTAs sit above the median on both price growth and resident
vulnerability. The two case studies are **two of those thirteen**, chosen because
their profiles diverge in direction — 19132 is a cheap market losing
transactions, 19143 is an expensive one holding them — not because they score
highest.

---

## The six measures

Reported separately, never pooled into a composite score:

| Measure | What it establishes | What it cannot establish |
|---|---|---|
| Price growth | Prices rose faster here than in most qualifying ZIPs | Who bought, or why the price moved |
| Price-to-income | Sale prices grew faster than resident incomes | Whether a household was priced out |
| Transaction contraction | Fewer eligible deeds recorded per occupied unit | Whether owners held or listed |
| Eviction filings | Court filings per 1,000 renter households | Judgments, removals, unique households |
| Permit pipeline | Units were applied for | Completion, affordability, net supply |
| Resident vulnerability | Residents have fewer resources to absorb cost | Whether any specific household felt pressure |

---

## Headline numbers

| | 19132 | 19143 | City benchmark |
|---|---:|---:|---:|
| Median sale price, 2024 | $80,000 | $170,500 | $269,250 |
| Price change, 2014–2024 | +285.5% | +184.3% | — |
| Median household income change | +46.0% | +42.3% | — |
| Price-to-income, 2014 → 2024 | 0.92× → 2.44× | 1.97× → 3.94× | 3.90× median |
| Price CAGR, 2015–2024 (rank of 37) | 17.0% (1st) | 11.2% (7th) | — |
| Eviction filings per 1,000 renters, 2025 | 55.2 | 34.7 | 40.2 |
| Eligible-transaction change, 2015-17 → 2022-24 | −33.2% | −13.9% | — |
| Permitted units, 2023–2025 (percentile) | 191 (72.2) | 201 (61.1) | — |

**Forecast.** Auto-ARIMA was selected on the mean RMSE of two time-ordered
holdouts, not on training error. It wins the mean for both ZIPs and loses the
2019 pre-pandemic window in each — by 0.2 sales per month in 19132 and 0.3 in
19143 — and the report states that rather than claiming a clean sweep.

**Reading the two ZIPs together is the point.** 19132 has the fastest price
growth in the city on the cheapest stock, the highest eviction rate, and the
sharpest loss of transactions: a market that is both squeezed and thinning.
19143 has strong prices, more transactions retained, and a permit pipeline that
could read as relief or as pressure depending on affordability — which is why
its actions are monitoring, not intervention.

---

## Dashboard

`tableau_data/tableau_ingestion/` holds the five files the workbook consumes —
one dimension (`dim_geography`) and four facts (`fact_zip_profile`,
`fact_annual_signals`, `fact_monthly_forecast`, `fact_policy_response`). Every
file is keyed to `geography_key`, and `19_validate_dashboard_package.R` fails the
build if a key orphans or a stray file appears.

The workbook itself is built by hand from those five files following
[`code/docs/TABLEAU_BUILD_STEPS.md`](code/docs/TABLEAU_BUILD_STEPS.md) and is
published to Tableau Public:

**[Philadelphia Housing Pressure — Context, Trajectory, and Response](https://public.tableau.com/app/profile/luan.nguyen1531/viz/PhiladelphiaHousingPressureDashboard/PhiladelphiaHousingPressureContextTrajectoryandResponse)**

It holds two dashboards joined by navigation buttons. The first is the context
view: a ZIP map selector, the five-ZIP screen, and the case-study profiles with
the six measures. The second is the forecast and response view: the per-ZIP
transaction forecast with 80% and 95% bands and a 2026-01-01 reference line,
the evidence-to-response matrix, and the response detail.

The `.twbx` is not in this repository — the five input files and the build steps
are, so the workbook can be rebuilt.

---

## Evidence to response

Eight actions, four of them High priority, each carrying its evidence trigger,
lead time and monitoring metric — for example, in 19132 *renter stabilization*
triggered by 55.2 filings per 1,000 renters against 40.2 citywide, immediate to
12 months. The full matrix is Appendix A.4 of the Data Usage Report and
`fact_policy_response.csv`.

---

## Baltimore peer comparison

Stage 20 measures five Baltimore neighborhoods — Remington, Union Square,
Washington Village-Pigtown, Highlandtown, Patterson Park — against a Baltimore
benchmark: **+146% to +270% price change 2012–2025 against +78.3%**. It runs
separately from `run_all.R` and never enters the dashboard.

One caution travels with it: the benchmark is the average of every neighborhood
in the Baltimore *metro* file, not a citywide median. See
[`code/baltimore/README.md`](code/baltimore/README.md).

---

## Repository map

```
code/                 the pipeline, in run order
  00_config.R          project-root resolution, no hard-coded paths
  01 … 19              install → clean → measure → select → validate → forecast
                       → dashboard facts → response matrix → package gate
  run_all.R            one entry point
  baltimore/           stage 20, the peer-city comparison (runs separately)
  README.md            file-by-file reference, inputs, outputs, limits
  docs/                how the five dashboard files become the Tableau workbook

R/                    week-by-week working scripts, kept because docs/ cites them
docs/                 method notes, data dictionaries, cleaning justification
tableau_data/         analysis outputs (CSV) and the five dashboard input files
visualizations/       presentation charts, 200 dpi
team_data/            field dictionaries and build metadata
external_data/        small cleaned external aggregates
data/raw/             where the 1.9 GB transfer extract goes (not committed)
```

---

## Reproduce it

```r
# from the project root
source("code/01_setup_packages.R")   # once
source("code/run_all.R")             # ~25–40 min on first run
```

`code/README.md` documents every input, whether the pipeline downloads it or it
must be placed by hand, and which artefacts are **not** produced by R — the ZIP
geometry map, the Tableau workbook and the deck.

## What is not in this repository

The raw data. The Real Estate Transfers extract alone is 1.9 GB and several
sources are governed by their publishers' terms, so both are excluded by
`.gitignore` and documented in `code/README.md`. Everything derived from them —
the cleaned dictionaries, the analysis tables, the dashboard inputs and the
charts — is committed.

---

## What this analysis does and does not claim

It measures **housing pressure and potential displacement risk**. It does not
claim that gentrification occurred, that any household was displaced, or that
price growth caused the change in transaction volume. Three limits are load-
bearing and repeated wherever the numbers appear:

- A ZIP approximates a Census ZCTA; ACS five-year releases overlap.
- A permit is not a completed or affordable unit; an eviction filing is not an
  eviction.
- Redfin prices and the transfer-tax records agree on direction and disagree on
  level. They are never merged into one claim.

---

## Documentation

| Document | What it covers |
|---|---|
| [`code/README.md`](code/README.md) | Every file, input, output, run order and known limit |
| [`docs/DATA_CLEANING_JUSTIFICATION.md`](docs/DATA_CLEANING_JUSTIFICATION.md) | Why each cleaning decision was made, with counts |
| [`docs/WEEK_06_DATA_DICTIONARY_AND_DASHBOARD_GUIDE.md`](docs/WEEK_06_DATA_DICTIONARY_AND_DASHBOARD_GUIDE.md) | Field-level definitions for the dashboard layer |
| [`code/docs/TABLEAU_BUILD_STEPS.md`](code/docs/TABLEAU_BUILD_STEPS.md) | Rebuild the workbook from the five input files |
| `Data Usage Report` (separate submission) | Sections 1–9 plus evidence appendices |

---

## Data sources

Philadelphia Real Estate Transfers, OPA properties and L&I permits (OpenDataPhilly);
Redfin Data Center; ACS 5-year (Census); Eviction Lab Eviction Tracking System;
FRED and FHFA; Baltimore neighborhood tracker (Redfin) for the peer comparison.
Access points and dates are listed in Appendix B.2 of the Data Usage Report.
