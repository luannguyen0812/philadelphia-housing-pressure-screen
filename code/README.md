# BSAN 710 Group 4 — Philadelphia Housing Pressure: analysis code

## Identifiers

| | |
|---|---|
| Prepared by | BSAN 710 Group 4, Drexel University, LeBow College of Business |
| Contact for this code | Luan Nguyen |
| Baltimore section | Stage 20, run separately (see the stage 20 section below) |
| Version | 1.0 |
| Date prepared | 18 November 2026 |
| Course | BSAN 710, Fall 2026, MS in Business Analytics Capstone |
| Client | City of Philadelphia — Office of Innovation and Technology |

## Purpose

This code rebuilds every number, table, chart, model and dashboard file behind
the final deliverable: a ZIP-level screen of **housing pressure and potential
displacement risk** across Philadelphia.

Starting from the raw OpenDataPhilly Real Estate Transfers extract, the pipeline

1. cleans 5,168,394 transfer records into two documented tables — one row per
   property record, one row per legal document;
2. joins ZIP-level sale prices to ACS household income and builds
   price-to-income and growth-endpoint measures;
3. applies a pre-declared coverage gate to all 48 measurable Philadelphia
   ZIP/ZCTAs, which 37 pass;
4. scores those 37 on six separately reported measures and retains 19132 and
   19143 as detailed case studies;
5. validates the case studies against property class, permits, eviction
   filings, inventory and days on market;
6. validates a monthly transaction forecast on two time-ordered holdouts before
   producing a 2026–2035 path with uncertainty bands;
7. assembles the dashboard's semantic layer (one dimension, four fact tables)
   and the evidence-to-response table;
8. gates the package: unique keys, no orphan geography keys, no stray files.

The analysis describes pressure and exposure. It does not claim that
gentrification occurred or that any household was displaced.

## Files

Every stage is one file, numbered in run order. Each file opens with a header
giving its purpose, inputs, outputs and the stage it must follow.

| File | Does what | Reads | Writes |
|---|---|---|---|
| `00_config.R` | Resolves the project root and code folder; sets run options | folder structure | nothing |
| `00_plot_theme.R` | Shared ggplot theme for presentation charts | — | nothing |
| `01_setup_packages.R` | Installs missing R packages | — | — |
| `02_build_economic_context.R` | FRED / FHFA / optional Zillow context series | FRED CSV endpoints | `external_data/*.csv` |
| `03_clean_philadelphia_transfers.R` | **Main clean**: both grain tables, dictionaries, metadata, citywide series, backtest, ward allocation model | `data/raw/rtt_summary.csv` | `team_data/*`, `cache/*`, `tableau_data/*` |
| `04_normalize_redfin_zip_data.R` | Tidy the Redfin ZIP tracker | `external_data/raw/redfin_zip_market_tracker_philadelphia.tsv` | `external_data/raw/redfin_zip_prices_normalized.csv` |
| `05_build_zip_affordability.R` | Price × income, price-to-income, growth endpoints | 03, 04, ACS, CPI | `tableau_data/fact_zip_price_income.csv` and related |
| `06_build_core_visualizations.R` | Five core charts and their chart tables | 03, 05 | `visualizations/01..05*.png`, `tableau_data/week03_chart_tables/` |
| `07_build_acs_vulnerability.R` | ACS vulnerability measures with MOEs | ACS bulk / API | `external_data/acs_zcta_vulnerability.csv` |
| `08_select_case_study_zips.R` | Coverage gate, 48 → 37, case selection, sale-to-assessment record | 05, 07 | `tableau_data/week04_*.csv`, `visualizations/week04_*.png` |
| `09_build_citywide_benchmark.R` | The 37-ZIP benchmark table | 05, 08 | `tableau_data/week05_citywide_*.csv` |
| `10_property_and_permit_checks.R` | Property-class sensitivity, permit pipeline, unit-coverage audit | 03, OPA, L&I | `tableau_data/week05_*proper*`, `week05_permit_signals.csv` |
| `11_redfin_rtt_reconciliation.R` | Do two price sources agree on direction? | 05, 08 | `tableau_data/week05_redfin_rtt_*.csv` |
| `12_neighborhood_change_endpoints.R` | Price growth vs income growth endpoints | 05, 08 | `tableau_data/week05_neighborhood_change_*.csv` |
| `13_eviction_and_market_signals.R` | Eviction filings, inventory, days on market | Eviction Lab, Redfin, 07 | `tableau_data/week05_eviction_*.csv`, `week05_redfin_market_signals.csv` |
| `14_forecast_validation.R` | Two holdouts, model selection, 2026–2035 path | 03 | `tableau_data/week05_*forecast*.csv` |
| `15_build_dashboard_facts.R` | Dashboard dimension and four fact tables | 09–14 | `tableau_data/tableau_ingestion/*` |
| `16_forecast_technical_appendix.R` | Documented model summary and RMSE chart | 03, 14 | `tableau_data/week06_forecast_*.csv` |
| `17_exogenous_forecast_challenger.R` | External-driver test on a common holdout | 03, 02 | `tableau_data/week06_exogenous_*.csv` |
| `18_build_response_matrix.R` | Evidence-to-response actions and claim boundaries | 15 | `tableau_data/tableau_ingestion/fact_policy_response.csv` |
| `19_validate_dashboard_package.R` | Final gate and package audit | 15–18 | `tableau_data/week06_final_package_audit.csv` |
| `20_baltimore_comparison.R` | **Baltimore peer-city comparison**: five neighborhoods against the Baltimore benchmark, 2012–2025 | `external_data/raw/baltimore_redfin_neighborhoods.csv` | `external_data/baltimore_neighborhood_prices.csv`, `tableau_data/week07_baltimore_comparison.csv`, `visualizations/week07_baltimore_comparison.png` |
| `run_all.R` | Runs stages 01–19 in order. Stage 20 is not included — it reads another city and runs on its own | all of the above | all of the above |
| `docs/TABLEAU_BUILD_STEPS.md` | How the five dashboard files become the Tableau workbook: relationships, calculated fields, worksheets, dashboards, actions, QA | `tableau_data/tableau_ingestion/` | the `.twbx` workbook |

## Inputs

The code expects this folder structure at the project root:

```
BSAN_Proj/
├── data/raw/            raw extract (not redistributed)
├── external_data/       cached downloads and clean external tables
├── team_data/           the two cleaned tables, dictionaries, metadata
├── tableau_data/        analysis-ready CSVs and the dashboard package
├── visualizations/      presentation PNGs
└── code/                this folder
```

**No data files are included with this submission.** The raw sources are too
large to distribute and several are governed by their publishers' terms. Each
file below is either downloaded automatically by the pipeline or must be placed
manually before the first run.

| Input | Size | Where it comes from | How to obtain |
|---|---|---|---|
| `data/raw/rtt_summary.csv` | 1.9 GB | OpenDataPhilly, Real Estate Transfers | Download the full CSV from <https://opendataphilly.org/datasets/real-estate-transfers/>. Manual step: there is no filtered or paginated export. |
| `external_data/raw/redfin_zip_market_tracker_philadelphia.tsv` | 4.7 MB | Redfin Data Center, ZIP Code Market Tracker | Download the national ZIP tracker, keep `REGION_TYPE == "zip code"`, `STATE_CODE == "PA"`, ZIPs beginning 191, `PROPERTY_TYPE == "All Residential"`, and save as this filename. |
| `external_data/raw/week05_opa_selected_zips.csv` | 2.9 MB | OPA via Carto SQL | Downloaded automatically by stage 10 if absent (set `bsan.refresh_week05_external = TRUE` to force). |
| `external_data/raw/week05_opa_zip_property_mix.csv` | 0.3 MB | OPA via Carto SQL | As above. |
| `external_data/raw/week05_permit_zip_year.csv` | 1.4 MB | L&I permits via Carto SQL | As above. |
| `external_data/raw/week05_eviction_pa_monthly.csv` | 4.9 MB | Eviction Lab, Eviction Tracking System v3.0 | Downloaded automatically by stage 13 if absent (set `bsan.refresh_week05_eviction = TRUE` to force). |
| ACS 5-year extracts | ~1–18 MB per year | U.S. Census Bureau | Downloaded automatically by stages 05 and 07. No Census API key is required for the default bulk-file path. |
| FRED / FHFA series | < 1 MB | Federal Reserve Bank of St. Louis | Downloaded automatically by stage 02. No API key. |
| `external_data/raw/baltimore_redfin_neighborhoods.csv` | 2.8 MB | Redfin Data Center, neighborhood market tracker | Download the neighborhood tracker for the **Baltimore, MD metro area** and save the unmodified file. 305 neighborhoods, January 2012 to August 2026. Not downloaded automatically — stage 20 stops and names this path if it is missing. |

Optional: Zillow metro CSVs. If they cannot be downloaded, stage 02 warns and
continues; no reported result depends on them.

## How to run

```r
# 1. Open BSAN_Proj.Rproj so the working directory is the project root.
#    If you copied the code elsewhere, set the project root once instead:
#        Sys.setenv(BSAN710_PROJECT_ROOT = "/path/to/BSAN_Proj")
#    or add BSAN710_PROJECT_ROOT=/path/to/BSAN_Proj to .Renviron.

# 2. Install packages (once).
source("code/01_setup_packages.R")

# 3. Run everything.
source("code/run_all.R")
```

A single stage can be re-run once its inputs exist:

```r
source("code/14_forecast_validation.R")
```

Skip stages you have already run:

```r
options(bsan.skip_stages = c("01_setup_packages.R", "02_build_economic_context.R"))
source("code/run_all.R")
```

The Baltimore comparison is **stage 20** and sits outside `run_all.R`. Run it
on its own once its input is in place — what it computes, and the limits on
quoting it, are set out [below](#stage-20-the-baltimore-peer-city-comparison):

```r
source("code/20_baltimore_comparison.R")
```

**Expected runtime.** About 25–40 minutes for a first full run, most of it in
stage 03 reading the 1.9 GB extract. Subsequent runs reuse
`cache/philly_rtt_clean_v6.rds` and finish in a few minutes. Stage 03 is the
only memory-hungry step (roughly 4–6 GB peak); everything else is small.

## Requirements

- R 4.5 or later (built and tested on R 4.5.2).
- Packages: `tidyverse`, `lubridate`, `tsibble`, `feasts`, `fabletools`,
  `fable`, `lpSolve`, `readxl`, `jsonlite`.
  `01_setup_packages.R` installs anything missing.
- Package `ragg` is used indirectly by `ggsave()` for PNG output on macOS;
  if PNG rendering fails with "invalid font type", install `ragg` and re-run
  the chart stages.
- Internet access on the first run (FRED, ACS, OPA, L&I, Eviction Lab). After
  that, the pipeline runs offline from the cached inputs.
- No credentials are stored anywhere in this package. If a Census API key is
  ever needed, put `CENSUS_API_KEY` in `.Renviron`.

## Outputs

| Output | What it is |
|---|---|
| `team_data/data_clean.csv.gz` | 5,067,868 property records × 35 columns (`record_id`) |
| `team_data/data_document.csv.gz` | 4,401,686 legal documents × 47 columns (`document_id`) |
| `team_data/*_dictionary.csv`, `data_clean_metadata.csv` | Field definitions and build metadata |
| `tableau_data/tableau_ingestion/` | **The five dashboard files**: `dim_geography.csv`, `fact_zip_profile.csv`, `fact_annual_signals.csv`, `fact_monthly_forecast.csv`, `fact_policy_response.csv` |
| `tableau_data/week0*.csv` | Every intermediate table quoted in the Data Usage Report and the deck appendix |
| `visualizations/*.png` | Every presentation chart, 200 dpi |
| `tableau_data/week06_final_package_audit.csv` | Row counts and foreign-key validation for the dashboard package |
| `tableau_data/week07_baltimore_comparison.csv` | The five Baltimore neighborhoods plus the benchmark, exactly as charted on slide 10 |
| `external_data/baltimore_neighborhood_prices.csv` | The five neighborhoods, 2012 and 2025, with prices, sales and months of data observed |

The dashboard itself (Tableau workbook and public link) is not produced by this
code; it is built from `tableau_data/tableau_ingestion/` following
`docs/TABLEAU_BUILD_STEPS.md`, which ships with this package so the workbook
can be rebuilt even though the binary `.twbx` is not submitted.

## Stage 20: the Baltimore peer-city comparison

One stage sits outside `run_all.R`. It reads a different city, its input is not
part of the Philadelphia pipeline, and nothing it produces enters
`dim_geography` or any `tableau_ingestion/` file.

It exists to answer a different question from the rest of the package. The
Philadelphia screen identifies where pressure is *building*; Baltimore shows
what a comparable city looks like once that pressure has *run*. Five
neighborhoods are compared with a Baltimore benchmark: Remington, Union Square,
Washington Village-Pigtown, Highlandtown and Patterson Park.

| Item | Value |
|---|---|
| Source | Redfin neighborhood market tracker, Baltimore MD metro area |
| Measure | Mean of the year's monthly `MEDIAN SALE PRICE NSA ($)` |
| Window | Calendar 2012 against calendar 2025, both complete years in the delivered file |
| Benchmark | Mean of every neighborhood median in the metro file — see below |
| Outputs | `external_data/baltimore_neighborhood_prices.csv`, `tableau_data/week07_baltimore_comparison.csv`, `visualizations/week07_baltimore_comparison.png` |

Delivered result:

| Neighborhood | 2012 | 2025 | Change |
|---|---:|---:|---:|
| Remington | $74,936 | $277,033 | +269.7% |
| Union Square | $65,900 | $213,571 | +224.1% |
| Washington Village-Pigtown | $63,952 | $206,329 | +222.6% |
| Highlandtown | $117,646 | $316,000 | +168.6% |
| Patterson Park | $121,654 | $299,560 | +146.2% |
| **Benchmark** | **$159,820** | **$284,961** | **+78.3%** |

### What the benchmark is, and what it is not

The benchmark is the mean of **every neighborhood median in the metro file** —
305 neighborhoods, spanning Baltimore City, Baltimore County and Harford County.
It is not a citywide median: its 2012 level is $159,820 against roughly $92,000
for Baltimore City itself.

**Call it "the average Baltimore-area neighborhood". Do not call it "the city
average".**

Three limits follow and should travel with any ratio taken from this stage:

- **Geography.** Metro-wide, so it includes suburbs that are not comparable to
  the five city neighborhoods.
- **Composition.** 195 regions have 2012 data, 238 have 2025 data, 180 have both.
  The two years are not computed over the same basket.
- **Thin cells.** A year's price is the mean of that year's monthly medians, not
  an annual median. Union Square carries 4 months of 2012 data against 7 of 2025;
  Remington carries 11 against 12.

The ratio of the five-neighborhood mean (+206%) to the benchmark (+78.3%) is
**2.6x**, and 2.5x if Union Square is dropped. It is not 2.5x against a citywide
median, which would put it nearer 1.6x-1.8x. If a single multiplier is quoted,
the benchmark it is measured against has to be named in the same sentence.

### What this stage does not cover

- **No commercial-investment series.** Rising commercial investment is asserted
  in the presentation notes; no permit or commercial valuation data was
  delivered for Baltimore.
- **No Baltimore housing-stock inventory.** Nothing here counts assisted or
  income-restricted units, so it cannot say whether the five neighborhoods
  gained or lost affordable stock. Appendix B.4 of the Data Usage Report sets
  out the same limit for Philadelphia.
- **No boundary file.** The neighborhoods are Redfin's definitions, not the City
  of Baltimore's official boundaries.

### Running it

```r
# from the project root, with external_data/raw/baltimore_redfin_neighborhoods.csv in place
source("code/20_baltimore_comparison.R")
```

The script stops with the expected path if the input is missing, and it does not
download anything. It is safe to run before or after `run_all.R`; there is no
dependency in either direction.

### Before quoting it

- [ ] The benchmark is described as Baltimore-area, not city
- [ ] The window (2012, 2025) travels with the percentages
- [ ] Union Square's months of data are known if its figure is singled out
- [ ] No Baltimore key enters `dim_geography` or any `tableau_ingestion/` file
- [ ] No comparison is made between a Baltimore price and a Philadelphia price

---

## What this package reproduces, and what it does not

Running every stage in order reproduces the analysis. It does not reproduce
every artefact that appears in the client presentation, and the difference is
worth stating plainly rather than discovering it at a screen share.

| Deliverable element | Reproduced by `run_all.R`? | Where it comes from |
|---|---|---|
| Every table quoted in the Data Usage Report | **Yes** | `tableau_data/*.csv` |
| The dashboard's five input files | **Yes** | stages 15 and 18 |
| Chart: five-ZIP context scatter | **Yes** | stage 09 → `week05_citywide_selection_context.png` |
| Chart: price growth against income growth | **Yes** | stage 12 → `week05_price_income_endpoint_change.png` |
| Chart: the ZIP geometry map | **No** | built outside R; there is no geometry code in this package |
| Six-measure chart, forecast panel, dashboard schematic, policy tables | **No** | assembled in Tableau from the tables above |
| The Tableau workbook itself | **No** | built by hand from the five ingestion files, following `docs/TABLEAU_BUILD_STEPS.md` |
| The Baltimore peer-city comparison | **Separately** — stage 20, not in `run_all.R` | `code/20_baltimore_comparison.R` → `tableau_data/week07_baltimore_comparison.csv` and the chart |
| The presentation deck | **No** | consumes the tables and two charts; layout is manual |

The distinction that matters: everything marked **No** is a *rendering* of
numbers that **are** reproduced, not a separate analysis. The map is the one
exception — it has no code behind it in this package and would have to be
rebuilt in Tableau or a GIS tool from a ZCTA boundary file.

## Two stages do more than the final dashboard needs

The repository is cumulative across weeks 3 to 6, so two stages carry earlier
work that the final deliverable no longer consumes:

- **Stage 03** also writes the citywide, cluster and regression tables, and the
  ward allocation model, that backed the earlier five-chart workbook and the
  coursework. Nothing downstream of stage 03 reads those files.
- **Stage 06** also draws the five Week 3 charts (`01_` to `05_`). None of them
  appears in the final deck. The stage is still required, because it writes
  `fact_zip_price_income.csv`, which stages 08 to 12 all depend on.

Both are kept deliberately: they are the evidence trail behind the five-ZIP
selection, and removing them would break the path from the raw extract to the
case studies.

## Important notes

1. **Two grains, never one.** `data_clean` is the parcel-level source and
   `data_document` is the transaction-level derivative. Counting `data_clean`
   rows overstates transactions because one deed can cover several parcels.
   Always state which table a count comes from.
2. **2026 is incomplete.** The extract ends in July 2026. Every 2026 annual
   value is January–July year-to-date and complete-year growth and model
   fitting stop at 2025.
3. **Prices are nominal** unless a column name ends in `_2024_dollars`. Those
   real-dollar fields are the only ones that use the CPI deflator.
4. **No imputation.** Missing income, ZIP and consideration stay missing. The
   series end at 2024 for ACS because 2025–2026 income is not published.
5. **ZIP ≠ ZCTA.** Every ACS-based measure is a ZIP/ZCTA approximation and is
   labelled as such.
6. **The forecast is a scenario.** Model family was chosen on the mean RMSE of
   two out-of-sample holdouts. The 3–5 year portion is usable for monitoring;
   2035 is a planning baseline, not a prediction.
7. **External drivers were tested and not adopted.** Stage 17 documents the
   test; the production path stays intervention-adjusted Auto-ARIMA.
8. **Week 3 chart tables moved.** The five `viz1..viz5` CSVs are written to
   `tableau_data/week03_chart_tables/` rather than to
   `tableau_data/tableau_ingestion/`. The ingestion folder is reserved for the
   five final dashboard files, and stage 19 fails the run if anything else is
   in it. This is the only path change from the working repository.
9. **Raw sources change.** If a source is refreshed, the numbers in the Data
   Usage Report will move. Re-record the source date and re-run the validation
   comparisons in `docs/DATA_CLEANING_JUSTIFICATION.md` before publishing.
10. **The Baltimore benchmark is metro-wide, not citywide.** Stage 20 averages
    every neighborhood in the Baltimore MD metro file — Baltimore City plus
    Baltimore County and Harford County — so its 2012 level is about $160,000
    against roughly $92,000 for Baltimore City itself. Describe it as the
    *average Baltimore-area neighborhood*. Two limits travel with it: the set
    of neighborhoods changes between the two years (195 regions in 2012, 238
    in 2025, 180 in both), and each year's price is the mean of that year's
    monthly medians rather than an annual median, which is thin for small
    neighborhoods — Union Square carries 4 months of 2012 data against 7 of
    2025.
