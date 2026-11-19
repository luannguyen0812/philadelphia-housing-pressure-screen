# =============================================================================
# 04. NORMALIZE THE REDFIN ZIP MARKET TRACKER
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Filters the national Redfin ZIP tracker to Philadelphia 191xx All
#   Residential rows and standardizes period, geography and price columns.
#   Rolling 90-day periods are preserved; they are never summed into months.
# INPUTS
#   external_data/raw/redfin_zip_market_tracker_philadelphia.tsv
# OUTPUTS
#   external_data/raw/redfin_zip_prices_normalized.csv
# RUNS AFTER   02
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)

# =============================================================================
# REDFIN ZIP ETL: OFFICIAL MARKET TRACKER -> PHILADELPHIA ZIP-PERIOD FILE
# =============================================================================
# The downloaded redfin_property_types_monthly.csv is a national property-type
# file and does not contain ZIP geography. This script instead transforms the
# official Redfin ZIP Code Market Tracker subset extracted for 191xx ZIPs.
#
# Redfin ZIP observations are rolling 90-day periods. `period` is therefore the
# period-end date, not a single-month transaction total. The All Residential
# category is retained so the affordability measure covers the broad housing
# market consistently across ZIP codes and years.

redfin_source_path <- file.path(
  "external_data",
  "raw",
  "redfin_zip_market_tracker_philadelphia.tsv"
)
redfin_output_path <- file.path(
  "external_data",
  "raw",
  "redfin_zip_prices_normalized.csv"
)
redfin_source_url <- paste0(
  "https://redfin-public-data.s3.us-west-2.amazonaws.com/",
  "redfin_market_tracker/zip_code_market_tracker.tsv000.gz"
)

if (!file.exists(redfin_source_path)) {
  stop(
    "Missing ", redfin_source_path,
    ". Extract Philadelphia 191xx / All Residential rows from the official ",
    "Redfin ZIP Code Market Tracker first."
  )
}

required_columns <- c(
  "PERIOD_BEGIN",
  "PERIOD_END",
  "PERIOD_DURATION",
  "REGION_TYPE",
  "REGION",
  "STATE_CODE",
  "PROPERTY_TYPE",
  "MEDIAN_SALE_PRICE",
  "HOMES_SOLD",
  "LAST_UPDATED"
)

redfin_raw <- read_tsv(
  redfin_source_path,
  col_types = cols(
    PERIOD_BEGIN = col_date(),
    PERIOD_END = col_date(),
    PERIOD_DURATION = col_double(),
    REGION_TYPE = col_character(),
    REGION = col_character(),
    STATE_CODE = col_character(),
    PROPERTY_TYPE = col_character(),
    MEDIAN_SALE_PRICE = col_double(),
    HOMES_SOLD = col_double(),
    LAST_UPDATED = col_character()
  ),
  show_col_types = FALSE
)

missing_columns <- setdiff(required_columns, names(redfin_raw))

if (length(missing_columns) > 0) {
  stop(
    "The Redfin ZIP extract is missing: ",
    paste(missing_columns, collapse = ", ")
  )
}

redfin_zip_prices_normalized <- redfin_raw |>
  filter(
    REGION_TYPE == "zip code",
    STATE_CODE == "PA",
    PROPERTY_TYPE == "All Residential",
    PERIOD_DURATION == 90
  ) |>
  transmute(
    zip5 = str_extract(REGION, "[0-9]{5}$"),
    period = PERIOD_END,
    median_sale_price = MEDIAN_SALE_PRICE,
    homes_sold = HOMES_SOLD,
    property_type = PROPERTY_TYPE,
    source_url = redfin_source_url
  ) |>
  filter(
    str_detect(zip5, "^191[0-9]{2}$"),
    !is.na(period),
    !is.na(median_sale_price),
    median_sale_price > 0
  ) |>
  arrange(zip5, period)

stopifnot(
  nrow(redfin_zip_prices_normalized) > 0,
  n_distinct(redfin_zip_prices_normalized$property_type) == 1L,
  !anyDuplicated(redfin_zip_prices_normalized[c("zip5", "period")]),
  all(redfin_zip_prices_normalized$homes_sold >= 0, na.rm = TRUE)
)

write_csv(redfin_zip_prices_normalized, redfin_output_path)

message(
  "Normalized Redfin ZIP output written: ",
  scales::comma(nrow(redfin_zip_prices_normalized)), " ZIP-period rows; ",
  n_distinct(redfin_zip_prices_normalized$zip5), " Philadelphia ZIP codes; ",
  min(redfin_zip_prices_normalized$period), " through ",
  max(redfin_zip_prices_normalized$period), "."
)
