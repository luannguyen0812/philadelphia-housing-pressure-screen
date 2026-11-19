# Week 6 data dictionary and final dashboard guide

## Purpose

Week 6 converts the Week 4 selection and Week 5 validation work into one
decision-oriented Tableau dashboard and an evidence-to-response package. The
dashboard is designed to answer four questions:

1. How do 19132 and 19143 compare with all 37 qualifying ZIP/ZCTAs?
2. Which housing-pressure and resident-exposure signals differ between them?
3. What does the validated transaction forecast show, and what does it omit?
4. Which conditional City responses are aligned with the observed evidence?

The project uses “housing pressure and displacement risk,” not a confirmed
gentrification or displacement label. ZIP-level descriptive evidence cannot
show that an individual household was displaced.

## Implemented Week 6 scripts

| Script | Purpose |
|---|---|
| `R/week06_dashboard_exports.R` | Builds the geography dimension, ZIP profile, annual signals, monthly observed/forecast fact, relationship audit, and evidence-percentile visualization |
| `R/week06_forecast_technical_appendix.R` | Refits and documents the primary Auto-ARIMA models, coefficients, residual test, validation metadata, and unseen-period RMSE chart |
| `R/week06_exogenous_forecast_challenger.R` | Tests lagged mortgage rate, Redfin inventory, and Redfin days on market on the same 2024-2025 holdout without automatically promoting a more complex model |
| `R/week06_policy_scenario_matrix.R` | Creates differentiated case-study recommendations, non-case availability records, and the evidence-to-response visualization |
| `R/week06_run_all.R` | Runs the complete Week 6 batch and fails if the Tableau package has missing, unexpected, or orphan-key files |

Run after Week 5:

```r
source("R/week06_run_all.R")
```

## Final Tableau package

Only the following production files belong in
`tableau_data/tableau_ingestion/`:

| Table | Grain / primary key | Relationship key | Use |
|---|---|---|---|
| `dim_geography.csv` | one row per `geography_key` | primary key | Shared ZIP selector, case/default flags, and case-only availability flags |
| `fact_zip_profile.csv` | one row per `geography_key` | foreign key | All-ZIP context, KPI cards, component vulnerability, endpoint affordability, and cross-sectional percentiles |
| `fact_annual_signals.csv` | `geography_key` + `year` | foreign key | Annual price, income, RTT, permit, eviction, inventory, days-on-market, and ACS measures |
| `fact_monthly_forecast.csv` | `geography_key` + `month` + `series_type` | foreign key | Observed monthly eligible sales and primary 2026-2035 forecast for the two cases |
| `fact_policy_response.csv` | `recommendation_key` | `geography_key` foreign key | Evidence trigger, priority, conditional response, lead time, outcome metric, and claim boundary |

All facts relate directly to `dim_geography` on `geography_key`. Do not
physically join the fact tables. Their grains differ, so a physical join would
repeat annual/monthly/recommendation rows and inflate sums.

The final relationship audit is
`tableau_data/week06_final_package_audit.csv`. The previous Tableau package was
moved to `tableau_data/archive_pre_week06_ingestion/` and is not a production
input.

## Geography keys

| Pattern | Meaning | Example |
|---|---|---|
| `ZIP_<zip5>` | qualifying ZIP/ZCTA approximation | `ZIP_19132` |
| `CITY_PHL` | separately labeled Philadelphia/qualifying-ZIP benchmark | `CITY_PHL` |

`dim_geography` contains 37 selectable ZIP/ZCTAs plus one nonselectable City
benchmark row. The CSV includes `default_dashboard_selection = TRUE` for 19132
and 19143, but Tableau must be published/saved with both selected because a CSV
cannot force a workbook’s initial multi-select state.

## ZIP-profile measures

The ZIP profile retains raw values and cross-sectional percentiles. Percentiles
put unlike measures on a common display scale; they are not averaged into one
index.

| Field | Definition |
|---|---|
| `redfin_2015_2024_cagr` | Compound annual growth of annual Redfin median sale price, 2015-2024 |
| `vulnerability_percentile` | Percentile of the Week 4 four-component composite: renter share, renter cost burden, poverty rate, and senior share |
| `transaction_change_pct` | Change in average annual eligible RTT sales, 2022-2024 versus 2015-2017 |
| `transaction_contraction_percentile` | Percentile rank of the negative transaction change; higher means sharper contraction |
| `price_to_income_2024` | 2024 Redfin median sale price divided by 2020-2024 ACS median household income |
| `eviction_filings_per_1000_renters_2025` | 2025 filings divided by the 2024 ACS estimated renter-household denominator, multiplied by 1,000 |
| `permitted_units_2023_2025` | Sum of positive dwelling units reported on 2023-2025 new-construction permit records |
| `permitted_units_per_1000_occupied_2023_2025` | Reported permit units divided by 2024 ACS occupied housing units, multiplied by 1,000 |
| `redfin_inventory_2025` | Mean published Redfin inventory observations during 2025 |
| `redfin_median_days_on_market_2025` | Mean of published Redfin median-days-on-market observations during 2025 |

The City profile uses qualifying-ZIP medians for percentile-style comparisons.
The annual table uses pooled totals where a count can be pooled and explicitly
uses the pooled Philadelphia eviction denominator when available.

## Annual-signal source rules

- **RTT eligible sales:** DEED, `sale_deed`, one parcel/property row,
  consideration over $100, non-nominal, known consideration, and not flagged as
  a high-value outlier.
- **Redfin price/activity:** published rolling-period ZIP measures aggregated by
  the established Redfin ETL. They are not reconstructed transaction microdata.
- **ACS:** five-year ZCTA estimates. Adjacent releases overlap and margins of
  error remain in the table.
- **Eviction:** filing cases, not unique households or completed evictions. The
  denominator is an estimated renter-household count and is not time-varying in
  the current rate.
- **Permits:** permit applications and reported project units, not starts,
  completions, net new housing, or affordable units.
- **Inventory and days on market:** market-context signals that can suggest
  mechanisms but cannot establish why price or transaction activity changed.

## Forecast construction for the final presentation

The final forecast slide and technical appendix must report the following:

| Item | Construction |
|---|---|
| Target | Monthly eligible arm’s-length single-property RTT sales |
| Training period | January 2010-December 2025 |
| Training observations | 192 monthly observations per ZIP |
| Visible history | January 2015-December 2025; 2010-2014 is used but hidden for readability |
| Candidate families | Seasonal naive, ETS, and Auto-ARIMA |
| Validation | 2019 pre-pandemic holdout and 2022-2024 changed-regime holdout |
| Selection | Mean within-holdout RMSE rank plus comparison with seasonal-naive mean RMSE |
| Primary specification | Auto-ARIMA errors plus supplied pandemic and recording-backlog intervention indicators |
| Selected order, 19132 | regression with ARIMA(1,1,2) errors |
| Selected order, 19143 | regression with ARIMA(0,1,4) errors |
| Forecast period | January 2026-December 2035, 120 months |
| Future intervention assumption | both historical shock indicators equal zero after December 2025 |
| External market drivers | not included in the primary model |

**Validation windows.** Both are forward holdouts; the two test windows never
overlap and no training window contains its own test period.

| Holdout | Training period | Test period | Training months | Test months |
|---|---|---|---:|---:|
| 2019 pre-pandemic | Jan 2010 – Dec 2018 | Jan 2019 – Dec 2019 | 108 | 12 |
| 2022-2024 changed regime | Jan 2010 – Dec 2021 | Jan 2022 – Dec 2024 | 144 | 36 |
| Final production refit | Jan 2010 – Dec 2025 | none; forecast Jan 2026 – Dec 2035 | 192 | 120 forecast |
| Exogenous challenger (Week 6) | Feb 2015 – Dec 2023 | Jan 2024 – Dec 2025 | 107 | 24 |

The validation models are plain `SNAIVE`, `ETS`, and `ARIMA` fits. The pandemic
and recording-backlog indicators are **not** present in the validation stage;
they are added only in the final production specification. Validation therefore
compares model families, not the production model.

Two timing caveats. The 2022-2024 training window contains the pandemic
(March 2020 – June 2021) with no intervention terms, which is deliberate: the
model must survive a regime change it has not been told about. The recording
backlog runs to April 2022, so the first four months of the 2022-2024 test window
sit inside it. That raises absolute error for all three candidates equally, so
the ranking is unaffected, but the RMSE levels should not be read as precise
estimates of future forecast error.

**Why the exogenous challenger has its own split.** Redfin ZIP inventory and
days-on-market only exist from 2015, so a common sample across specifications
cannot start in 2010. The challenger also needs *observed* predictor values in
its test window, which exist for 2024-2025 but do not exist for 2026-2035. It is
therefore a short-horizon explanatory test, not a deployable long-horizon model,
and it was never a candidate in the Week 5 model-family validation. All three
challenger specifications include the pandemic and backlog indicators, so the
comparison isolates the effect of adding external drivers.

**Inflation and unemployment were not tested as predictors.** `CPIAUCSL` enters
the project upstream: `R/week04_two_zip_analysis.R` deflates Redfin price and ACS
household income into 2024 dollars. Inflation therefore sits in measurement, not
in a monthly sale-count model. No monthly unemployment series exists in the
project's external panel, so unemployment was neither tested nor rejected. Both
are metro or national series with no cross-ZIP variation, so neither can separate
19132 from 19143 — which is the comparison the dashboard exists to support. A
monthly unemployment series would also be close to collinear with the pandemic
indicator, since both spike in 2020.

The model does **not** contain mortgage rates, inventory, days on market, price,
income, permits, or eviction filings as predictors. It is a conditional
historical baseline with 80% and 95% prediction intervals, not a causal market
or displacement forecast.

A Week 6 challenger tested lagged mortgage rate, Redfin inventory, and Redfin
days on market using a common February 2015-December 2023 training period and a
January 2024-December 2025 holdout. For 19132, the intervention-only model had
the lowest RMSE (8.94). For 19143, the mortgage-rate model was lower by less
than 0.01 monthly sale (13.198 versus 13.198 after rounding), which is not a
material practical improvement; the full mortgage/inventory/DOM model was
worse. The exogenous challenger is therefore not promoted to the 2035 primary
path.

All three challenger specifications include both intervention dummies, so the
shock periods are flagged in the challenger as well as in the production fit; the
baseline row is `Interventions only`. A flag-sensitivity check on the same
February 2015-December 2023 / January 2024-December 2025 split shows what the
flags are worth: RMSE falls from 9.22 to 8.94 for 19132 and from 14.17 to 13.20
for 19143. Comparing an unflagged baseline against a flagged exogenous model
would therefore have produced a spurious 0.97 improvement at 19143 that belongs
to the dummies, not to the mortgage rate. A long-horizon ARIMAX forecast would also require defensible future
scenarios for every external predictor.

Auto-ARIMA means the algorithm chooses ARIMA error orders separately for each
ZIP within the ARIMA family. It does not automatically identify economic
predictors. Model-family choice is a second step: Auto-ARIMA was compared with
ETS and seasonal naive on time-ordered unseen data.

The residual Ljung-Box result should also be disclosed. The 19132 primary model
retains evidence of residual autocorrelation at lag 24, while the 19143 result
does not. Consequently, neither 2035 line should be presented as a precise
prediction; the 3-5 year portion is more suitable for operational monitoring,
and 2035 is a long-range planning scenario.

Model-family selection was decided on **mean** RMSE across the two holdouts, not
on every individual window. Both validation windows are out of sample (12 months
in 2019 plus 36 months in 2022-2024); no training error enters the selection. As a
robustness check, pooled RMSE across all 48 held-out months, which weights each
window by its length rather than equally, gives the same decision: 19132 18.34
versus 20.96 for ETS and 23.06 for seasonal naive, and 19143 30.29 versus 33.55 and
46.13. Two exceptions should still be disclosed. For 19132 the
2019 pre-pandemic window is a near-tie that favours seasonal naive (RMSE 12.83
versus 12.96). For 19143 the 2019 window favours ETS (10.60 versus 10.91), though
Auto-ARIMA still beats seasonal naive there (13.05). Auto-ARIMA retains the lowest
mean RMSE for both ZIPs (19132: 16.38 versus 19.20; 19143: 22.66 versus 32.89) and
the lowest error in both 2022-2024 changed-regime windows, which is the regime the
2026-2035 forecast targets.

## One-dashboard worksheet plan

1. **All-ZIP context:** keep all 37 points visible and highlight the active ZIP
   selection. Bold median lines define the quadrant.
2. **Evidence percentile profile:** show the six pressure/exposure percentiles
   separately. The 50th percentile is a reference, not a pass/fail cutoff.
3. **Annual signal trend:** a measure selector switches among Redfin price, ACS
   income, RTT sales, eviction filing rate, permit units, inventory, and days
   on market. Keep the City benchmark available.
4. **Case-study forecast:** observed history, forecast median, and 80%/95%
   intervals. A non-case ZIP displays an availability message.
5. **Evidence-to-response:** filter the response table by ZIP and retain the
   trigger, lead time, monitoring metric, and claim boundary in tooltips or a
   detail panel.
6. **Limitations footer:** show the source/definition cautions permanently.

The dashboard opens with 19132 and 19143 selected in a Tableau set named
**Selected ZIPs**, but users can select any of the 37 qualifying ZIP/ZCTAs. The
all-ZIP scatter colors set membership without filtering the distribution.
Annual sheets use `City benchmark OR Selected ZIPs` so the benchmark remains
visible. Add “Reset to 19132 + 19143” and “All qualifying ZIPs” actions or
saved views.

## Week 6 visualizations

| File | Interpretation |
|---|---|
| `visualizations/week06_case_evidence_percentiles.png` | Common-scale profile showing why the two ZIPs require different interpretations |
| `visualizations/week06_evidence_to_response_matrix.png` | High/medium current evidence alignment for distinct City response families |
| `visualizations/week06_forecast_validation.png` | Unseen-period RMSE comparison that motivated Auto-ARIMA selection |
| `visualizations/week06_exogenous_forecast_challenger.png` | Same-sample test of whether lagged mortgage rate, inventory, and days on market materially improve 2024-2025 holdout error |

## Recommendation boundaries

- 19132 currently supports stronger renter-stabilization and preservation
  urgency because rapid growth, above-median vulnerability, sharper transaction
  contraction, and an above-City filing rate coincide.
- 19143 supports affordable-rental preservation and permit-pipeline monitoring;
  its price-to-income ratio is higher, while its filing rate is below the pooled
  City benchmark and its transaction contraction is milder.
- The recommendations are conditional alignments, not program impact estimates.
- Non-case ZIPs show a monitoring-only record until a comparable case-specific
  validation is completed.
