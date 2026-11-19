# BSAN 710 project run order

Run every script from the project root after opening `BSAN_Proj.Rproj`.
Relative paths assume that the working directory is the repository root, not
the `R/` folder.

## First complete build

```r
# 1. Install only missing packages
source("R/setup_project.R")

# 2. Build external economic and peer-market inputs
source("R/econ_peer_etl.R")

# 3. Clean Philadelphia RTT and build team/model/Tableau tables
source("R/BSAN_Proj.R")

# 4. Normalize the local Redfin Philadelphia ZIP extract
source("R/redfin_zip_etl.R")

# 5. Join Redfin/RTT prices to ACS income and calculate affordability outputs
source("R/zip_affordability_etl.R")

# 6. Build all five chart datasets and PNG previews
source("R/core_visualizations.R")

# 7. Build the Week 4 ACS vulnerability measures (keyless bulk-table build)
source("R/week04_acs_vulnerability_etl.R")

# 8. Build the five-ZIP screen and validate the two detailed case studies
source("R/week04_two_zip_analysis.R")

# 9. Build the complete Week 5 citywide/external-source/forecast batch
source("R/week05_run_all.R")

# 10. Build and validate the final Week 6 Tableau/policy/forecast package
source("R/week06_run_all.R")
```

The first main build reads `data/raw/rtt_summary.csv` and writes the versioned
local cache `cache/philly_rtt_clean_v6.rds`. Later runs reuse that cache unless
the cleaning version changes.

## Ordinary rerun

If no raw or external source changed, the usual sequence is:

```r
source("R/BSAN_Proj.R")
source("R/zip_affordability_etl.R")
source("R/core_visualizations.R")
source("R/week04_acs_vulnerability_etl.R")
source("R/week04_two_zip_analysis.R")
source("R/week05_run_all.R")
source("R/week06_run_all.R")
```

Rerun `R/redfin_zip_etl.R` first only when the Redfin ZIP extract changes.
Rerun `R/econ_peer_etl.R` when the economic series change or their clean files
are missing.

## Required local inputs

- `data/raw/rtt_summary.csv`
- `external_data/raw/redfin_zip_market_tracker_philadelphia.tsv`
- Cached Week 5 OPA, L&I permit, and Eviction Lab extracts, or internet access
  for a deliberate refresh;
- Cached ACS files, or internet access and a Census API key for a deliberate
  refresh. The existing clean `external_data/acs_zcta_income.csv` is reused by
  default.

Do not place API keys in any R script. If a refresh requires one, define
`CENSUS_API_KEY` in the current R session or in a local `.Renviron`, which is
excluded by `.gitignore`.

## Refresh controls

Refresh FRED/FHFA/Zillow sources:

```r
options(bsan.refresh_external = TRUE)
source("R/econ_peer_etl.R")
options(bsan.refresh_external = FALSE)
```

Refresh ACS ZCTA income:

```r
options(bsan.refresh_acs = TRUE)
source("R/zip_affordability_etl.R")
options(bsan.refresh_acs = FALSE)
```

Refresh the official OPA and L&I Carto extracts used in Week 5:

```r
options(bsan.refresh_week05_external = TRUE)
source("R/week05_property_permit_validation.R")
options(bsan.refresh_week05_external = FALSE)
```

The Eviction Lab raw file is versioned by its source update date and should be
re-downloaded deliberately before the final dashboard:

```r
options(bsan.refresh_week05_eviction = TRUE)
source("R/week05_eviction_market_signals.R")
options(bsan.refresh_week05_eviction = FALSE)
```

See
`docs/WEEK_05_DATA_DICTIONARY_AND_NOTES.md` for the source link and limitations.

Change the ZIP scenario horizon to any integer from 10 through 15 years:

```r
options(bsan.zip_projection_years = 10L)
source("R/core_visualizations.R")
```

The default ZIP rule selects the five areas whose 2015-2025 compound growth is
closest to the citywide rate. The alternative below should be used only after
an explicit group scope decision:

```r
options(bsan.zip_selection_rule = "highest_growth")
source("R/core_visualizations.R")
```

## Main outputs

- `team_data/data_clean.csv.gz`: one cleaned property record per `record_id`.
- `team_data/data_document.csv.gz`: one legal filing per `document_id`.
- `tableau_data/`: compact dashboard-ready facts, dimensions, model tables,
  chart tables, and an export manifest.
- `visualizations/`: five presentation-ready PNG previews.
- `tableau_data/week04_two_zip_panel.csv`: joined 19132/19143 market,
  affordability, and vulnerability panel.
- `tableau_data/week04_zip_selection_scorecard.csv`: citywide candidate
  scorecard and documented selection gates.
- `tableau_data/week04_coverage_report.csv`: year-level coverage, volume, and
  MOE checks for the selected ZIPs.
- `tableau_data/week04_assessment_coverage.csv`: assessment availability and
  the assessment-year publication gate.
- `tableau_data/week04_sale_to_assessment.csv`: internal reproduction of the
  presented 2014-2025 property-level sale-to-assessment method for 19132 and
  19143, including annual medians, quartiles, and eligible counts.
- `tableau_data/week04_five_zip_transaction_activity.csv`: annual eligible RTT
  transactions and rates per 1,000 occupied housing units for the five-ZIP
  presentation screen.
- `visualizations/week04_preliminary_indexed_trends.png`: preliminary
  inflation-adjusted price/income comparison for the selected ZIPs and the
  Philadelphia ZIP median.
- `visualizations/week04_zip_selection_matrix.png`: market-growth versus
  vulnerability evidence for the selected pair, original Week 3 five, and
  other Philadelphia candidates.
- `visualizations/week04_selected_zip_vulnerability_profile.png`: component
  vulnerability measures for the selected ZIPs.
- `visualizations/week04_five_zip_transaction_activity.png`: three-year-average
  transaction activity for the five candidates as a common-scale dumbbell
  chart comparing 2015-2017 with 2022-2024.
- `visualizations/week04_sale_to_assessment_record.png`: internal
  sale-to-assessment appendix reproduction with the middle-50% band.
- `tableau_data/week05_citywide_zip_benchmark.csv`: all qualifying ZIP context
  for growth, vulnerability, and transaction activity.
- `tableau_data/week05_redfin_rtt_reconciliation.csv`: source-agreement and
  growth-rank sensitivity checks.
- `tableau_data/week05_eviction_monthly.csv`: selected-ZIP and Philadelphia
  eviction-filing indices relative to pre-pandemic baselines.
- `tableau_data/week05_permit_signals.csv`: all/new-construction permits and
  reported permitted-unit pipeline by ZIP-year.
- `tableau_data/week05_forecast_accuracy.csv`: pre-pandemic and changed-regime
  holdout accuracy for seasonal-naive, ETS, and ARIMA candidates.
- `tableau_data/week05_zip_transaction_forecasts.csv`: auditable candidate
  forecasts and 80%/95% intervals through 2035.
- `tableau_data/week05_pandemic_sensitivity_accuracy.csv`: common-holdout error
  under four treatments of the pandemic and recording-backlog periods.
- `tableau_data/week05_pandemic_sensitivity_forecasts.csv`: comparable 2026-2035
  paths for intervention-adjusted, disruption-excluded, and post-backlog models.
- `tableau_data/week05_primary_intervention_forecast.csv`: primary reference
  retaining all observations while controlling for identified disruption months.
- `visualizations/week05_pandemic_adjusted_transaction_forecast.png`: primary
  pandemic-adjusted reference with 80% and 95% uncertainty bands.
- `tableau_data/tableau_ingestion/`: the final five-file Tableau semantic
  package. Relate every fact directly to `dim_geography.csv` on
  `geography_key`; do not physically join facts at different grains.
- `tableau_data/week06_final_package_audit.csv`: row counts and foreign-key
  validation for every final Tableau fact.
- `tableau_data/week06_forecast_technical_summary.csv`: training period,
  observation count, Auto-ARIMA order, fit statistics, residual test,
  validation error, pandemic sensitivity, and exogenous-variable disclosure.
- `tableau_data/week06_case_study_policy_matrix.csv`: evidence triggers,
  conditional responses, lead times, monitoring metrics, and claim boundaries
  for 19132 and 19143.
- `visualizations/week06_case_evidence_percentiles.png`: common-percentile
  evidence profile without an opaque combined score.
- `visualizations/week06_evidence_to_response_matrix.png`: differentiated
  response priorities for the two case studies.
- `visualizations/week06_forecast_validation.png`: time-ordered unseen-period
  model-family RMSE comparison.
- `tableau_data/week06_exogenous_challenger_accuracy.csv`: same-sample
  2024-2025 holdout comparison for intervention-only, lagged-mortgage, and
  mortgage/inventory/days-on-market Auto-ARIMA specifications.
- `visualizations/week06_exogenous_forecast_challenger.png`: visual result of
  the external-predictor test; no challenger is promoted automatically.
- `visualizations/week05_pandemic_forecast_sensitivity.png`: common-scale scenario
  comparison showing how the forecast changes with pandemic treatment.
- `docs/WEEK_05_DATA_DICTIONARY_AND_NOTES.md`: Week 5 definitions, provenance,
  current findings, and claim boundaries.
- `Week_04_Housing_Pressure_and_Displacement_Risk.pptx`: eight-slide Week 4
  presentation with technical and interpretation speaker notes.
- `external_data/source_catalog.csv`: field-level source and transformation
  citations.
- `model_inputs/`: Excel Solver handoff and optional result import.

The large team tables, raw sources, caches, and raw downloads are intentionally
excluded from GitHub. Share the central clean table through the team's
controlled file channel rather than committing it directly.

## Interpretation checks before presenting

- Treat July 31, 2026 as the last complete Philadelphia observation date.
  Label 2026 annual values as January-July YTD.
- Use complete years through 2025 for annual growth and model fitting.
- Count transactions from the document table, not raw parcel rows.
- Use the defined eligible single-property deed sample for typical RTT price.
- Label the ZIP projection as a conditional forecast, not a guarantee. Present
  the pandemic sensitivity view whenever the long-range path is discussed.
- Limit Redfin/ACS affordability statements to the 2012-2024 common period.
- Do not interpret a correlation as causal evidence.


## Tableau build

After `R/week06_run_all.R` completes, connect the five CSVs in
`tableau_data/tableau_ingestion/` and follow
`docs/WEEK_06_TABLEAU_BUILD_STEPS.md` for the relationship model, calculated
fields, six worksheets, dashboard layout, interactivity, and QA checklist.
