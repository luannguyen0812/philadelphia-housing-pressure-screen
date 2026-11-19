# Week 5 data dictionary and implementation notes

## Purpose

Week 5 tests whether 19132 and 19143 remain defensible housing-pressure and
potential-displacement-risk case studies after adding Philadelphia-wide
benchmarks, alternative property definitions, external market signals,
housing-instability evidence, and time-ordered forecast validation.

The analysis does not claim that price growth caused fewer sales, that permits
caused displacement, or that an eviction filing is a completed eviction.

## Added public sources

| Source | Raw scope used | Main Week 5 purpose | Important limitation |
|---|---|---|---|
| Philadelphia OPA property file | Current parcels in 19132/19143 plus citywide ZIP/property-type aggregate | Join RTT sales to property class and audit unit feasibility | `unit` is an address designator, not a complete dwelling-unit count; current classification is joined to historical sales |
| Philadelphia L&I permits | Issued permits, 2014-2025, aggregated by ZIP/year/work type | New-construction permit and reported-unit pipeline | Permit issuance is not construction completion or occupancy |
| Eviction Lab Eviction Tracking System v3.0 | Pennsylvania ZIP-level monthly filings, 2020-August 2026, with pre-pandemic baselines | Renter-instability signal and Philadelphia comparison | Filings are cases, not unique households or completed evictions; missing/sealed geography can undercount ZIPs |
| Redfin ZIP Market Tracker | Quarterly All Residential observations | Inventory, days on market, source comparison | Redfin and RTT cover different transaction samples |
| ACS five-year | Existing 2010-2014 and 2020-2024 income endpoints; 2020-2024 vulnerability | Resident income and vulnerability context | Survey estimates have MOEs; ZIP/ZCTA mismatch; full historical demographic endpoint build needs a Census API key or bulk extraction |

Official source pages:

- OPA properties: <https://opendataphilly.org/datasets/philadelphia-properties-and-assessment-history/>
- L&I permits: <https://opendataphilly.org/datasets/licenses-and-inspections-building-and-zoning-permits/>
- Eviction Lab downloads: <https://evictionlab.org/eviction-tracking/get-the-data/>
- Redfin Data Center: <https://www.redfin.com/news/data-center/>
- ACS: <https://www.census.gov/programs-surveys/acs/data.html>

## Core outputs

| Output | Grain | Meaning |
|---|---|---|
| `week05_citywide_zip_benchmark.csv` | qualifying ZIP/ZCTA | Price CAGR, vulnerability, transaction change, and sales per 1,000 occupied units |
| `week05_citywide_summary.csv` | one Philadelphia benchmark row | Median-ZIP conditions, pooled transaction rates, and Spearman association |
| `week05_unit_coverage_audit.csv` | selected ZIP | Demonstrates why a universal price-per-dwelling-unit calculation is not available |
| `week05_property_join_coverage.csv` | selected ZIP | OPA match rate for eligible RTT sale records |
| `week05_sale_price_by_property_type.csv` | ZIP × period × property class | Property-type-separated median RTT consideration and interquartile range |
| `week05_permit_signals.csv` | ZIP × year | All permits, new-construction permits, and units reported on new-construction permits |
| `week05_eviction_monthly.csv` | selected ZIP/Philadelphia × month | Filing count, pre-pandemic baseline, and filing index |
| `week05_eviction_annual_zip.csv` | Philadelphia ZIP × year | Filing totals and rate per 1,000 estimated renter households |
| `week05_redfin_market_signals.csv` | available Philadelphia ZIP/Philadelphia median × year | Inventory, median days on market, months of supply, homes sold, and the default-dashboard flag; Week 6 restricts the shared selector to the qualifying ZIP dimension |
| `week05_redfin_rtt_reconciliation.csv` | qualifying ZIP | Price/activity correlations, source-specific CAGR ranks, and rank changes |
| `week05_neighborhood_change_endpoints.csv` | qualifying ZIP | Non-overlapping ACS income and Redfin-price endpoint change |
| `week05_neighborhood_change_availability.csv` | requested measure | Implemented/pending status so missing historical fields remain visible |
| `week05_forecast_accuracy.csv` | ZIP × holdout × model | RMSE, MAE, MASE, RMSSE, and MAPE |
| `week05_forecast_model_selection.csv` | ZIP × model | Average validation rank, seasonal-naive benchmark, and recommendation flag |
| `week05_zip_transaction_forecasts.csv` | ZIP × model × future month | Point forecast, 80%/95% intervals, and recommendation flag through 2035 |
| `week05_pandemic_sensitivity_accuracy.csv` | ZIP × pandemic specification | Common 2024-2025 holdout accuracy for unadjusted, intervention-adjusted, excluded-disruption, and post-backlog histories |
| `week05_pandemic_sensitivity_forecasts.csv` | ZIP × sensitivity specification × future month | Comparable 2026-2035 paths under three defensible treatments of the pandemic/recording disruption |
| `week05_primary_intervention_forecast.csv` | ZIP × future month | Presentation reference retaining all observations, with pandemic and recording-backlog indicators set to zero in future months |

## Main calculation definitions

- **Transaction change:** percentage change from average annual eligible RTT
  sales in 2015-2017 to average annual eligible RTT sales in 2022-2024.
- **Sales per 1,000 occupied units:** average annual eligible sales divided by
  2024 ACS occupied units, multiplied by 1,000 for readability. It is market
  activity, not the share of households that moved.
- **Property-type sensitivity:** median eligible RTT consideration within OPA
  single-family, multifamily/apartment, mixed-use, and other groups. It remains
  price per transacted property.
- **Permitted units:** sum of positive `numberofunits` on L&I records classified
  as new construction. It is a pipeline measure, not completed unit delivery.
- **Eviction filing index:** observed filings divided by Eviction Lab's
  pre-pandemic baseline for the same geography/month; the chart uses rolling
  12-month sums.
- **Neighborhood affordability-growth gap:** 2014-2024 Redfin median-price
  percentage change minus 2010-2014 to 2020-2024 ACS median-income percentage
  change.
- **Forecast selection:** average within-holdout RMSE rank across a 2019
  pre-pandemic holdout and a 2022-2024 changed-regime holdout. Selected models
  are separately checked against seasonal-naive mean RMSE.
- **Pandemic sensitivity:** compare the same January 2024-December 2025 holdout
  under four specifications: full history unadjusted; full history with March
  2020-June 2021 pandemic and July 2021-April 2022 recording-backlog indicators;
  those disruption months treated as missing; and May 2022 onward only. The
  intervention-adjusted reference retains observed data and assumes no repeat
  of either identified shock in future months.

## Current evidence and decision boundaries

- The qualifying benchmark contains 37 ZIP/ZCTAs. Its median 2015-2024 Redfin
  price CAGR is about 7.8%, and its median transaction change is about -19.3%.
- Across qualifying ZIPs, the current Spearman association between price CAGR
  and transaction change is positive (about 0.61), not evidence that faster
  price growth generally caused activity to fall. The two case-study declines
  must be interpreted in their local context.
- OPA matches approximately 98% of eligible case-study sale records, making the
  property-type sensitivity analysis usable. It does not make price per dwelling
  unit usable.
- Redfin and RTT median-price trajectories correlate strongly within both case
  studies, but activity counts correlate weakly or negatively because source
  definitions differ. Price direction is more robust than transaction-count
  equivalence.
- ARIMA currently has the best average RMSE rank for both ZIPs across the two
  validation windows and beats the seasonal-naive candidate on average RMSE.
  MASE remains above 1, so long-horizon results must retain prominent uncertainty
  and should not be described as precise causal forecasts.
- Pandemic treatment does not produce one winner across both case studies. In
  the common 2024-2025 holdout, excluding disruption months has the lowest RMSE
  for 19132 (about 10.0 sales/month), whereas the post-backlog history has the
  lowest RMSE for 19143 (about 13.1). The intervention-adjusted specification is
  close but does not win both ZIPs. Accordingly, use
  `week05_pandemic_adjusted_transaction_forecast.png` as the transparent primary
  reference and show `week05_pandemic_forecast_sensitivity.png` beside it or in
  the appendix; do not imply that removing pandemic observations automatically
  makes the forecast more accurate.
- 19140 is the closest citywide comparator to 19132 on the selection quadrant
  and has adequate coverage. Retaining 19143 is defensible only under the
  documented contrasting-case design: 19140 largely repeats 19132's extreme
  growth/vulnerability profile, while 19143 contributes a higher-price,
  higher-price-to-income, renter-heavy comparison. The pair is not described
  as the two highest-scoring ZIPs.
- Dashboard exports include `default_dashboard_selection` so Tableau can open
  on 19132 and 19143 without preventing clients from selecting other
  qualifying ZIPs. Citywide context views must retain all ZIPs and highlight
  the active selection rather than filtering the comparison universe away.

## Rebuild

After the Week 4 outputs exist:

```r
source("R/week05_run_all.R")
```

Raw OPA, permit, and eviction downloads are intentionally excluded from Git.
To refresh OPA and permit caches:

```r
options(bsan.refresh_week05_external = TRUE)
source("R/week05_property_permit_validation.R")
options(bsan.refresh_week05_external = FALSE)
```

To refresh Eviction Lab separately:

```r
options(bsan.refresh_week05_eviction = TRUE)
source("R/week05_eviction_market_signals.R")
options(bsan.refresh_week05_eviction = FALSE)
```

Never place a Census API key in a tracked script. Store `CENSUS_API_KEY` in a
local `.Renviron` when the historical demographic endpoint extension is built.
