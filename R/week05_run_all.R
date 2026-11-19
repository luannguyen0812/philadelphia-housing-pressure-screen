# =============================================================================
# WEEK 05: REPRODUCIBLE RUNNER
# =============================================================================
# ABSTRACT
# Run the complete Week 5 evidence-validation batch after the Week 4 outputs
# exist. Each sourced script owns one analytical question and writes stable
# dashboard-ready CSVs plus presentation-ready PNGs.

source("R/week05_citywide_context.R")
source("R/week05_property_permit_validation.R")
source("R/week05_redfin_rtt_reconciliation.R")
source("R/week05_neighborhood_change.R")
source("R/week05_eviction_market_signals.R")
source("R/week05_time_series_forecasting.R")
