# =============================================================================
# 03. CLEAN PHILADELPHIA REAL ESTATE TRANSFERS AND BUILD BOTH GRAINS
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Reads the raw OpenDataPhilly extract once, applies the documented cleaning
#   rules, and writes the parcel-level source table plus its document-level
#   derivative. Also builds the citywide monthly series, the descriptive
#   analysis, the citywide forecast backtest, and the ward allocation model.
# INPUTS
#   data/raw/rtt_summary.csv  (5,168,394 rows x 47 columns; not submitted)
# OUTPUTS
#   team_data/data_clean.csv.gz           one row per record_id
#   team_data/data_document.csv.gz        one row per document_id
#   team_data/data_clean_dictionary.csv, data_document_dictionary.csv
#   team_data/data_clean_metadata.csv     build counts and outlier cutoff
#   cache/philly_rtt_clean_v6.rds, cache/raw_parse_problems.csv
#   tableau_data/ citywide facts, model tables and export manifest
#   model_inputs/ward_solver_input.csv    Excel Solver hand-off
# RUNS AFTER   nothing
# NOTES        Longest stage: about 15 minutes on the first run, seconds on a cache hit.
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)
library(lubridate)
library(tsibble)
library(feasts)
library(fabletools)
library(fable)
library(lpSolve)

# Project folders are created once and reused by all later sections. Keeping
# generated artifacts out of the project root makes the analytical handoffs
# easier to audit and prevents raw, intermediate, and Tableau files from being
# confused with one another.
dir.create("cache", showWarnings = FALSE, recursive = TRUE)
dir.create(file.path("data", "raw"), showWarnings = FALSE, recursive = TRUE)
dir.create("external_data", showWarnings = FALSE, recursive = TRUE)
dir.create("model_inputs", showWarnings = FALSE, recursive = TRUE)
dir.create("tableau_data", showWarnings = FALSE, recursive = TRUE)
dir.create("team_data", showWarnings = FALSE, recursive = TRUE)

# The group approved all complete months available in the October 2026 source
# snapshot. August is present only through August 24, so the analytical cutoff
# remains July 31, 2026. Complete-year comparisons still end in 2025.
analysis_start <- as_date("2000-01-01")
analysis_end <- as_date("2026-07-31")
analysis_end_month <- floor_date(analysis_end, "month")
analysis_months <- seq.Date(analysis_start, analysis_end_month, by = "month")
last_complete_year <- 2025L


# =============================================================================
# SECTION 1 (DESCRIPTIVE): DATA LOADING
# =============================================================================
# Source: OpenDataPhilly "Real Estate Transfers" (Philadelphia Dept. of
# Records, Recorder of Deeds RTT summary extract).
# Research question: How have patterns of property transactions and mortgage
# activity changed across Philadelphia since 2000, and how do those changes
# compare with broader economic/real-estate trends (e.g. mortgage rates, home
# price indices, recessions, and comparable legacy-city housing markets)?

# The raw CSV is almost 2 GB, so repeating the same cleaning work during every
# R session wastes substantial time and memory. The cache stores the internal
# parcel-cleaning and document-aggregation objects needed to rebuild the two
# shared analytical grains. `data_clean` is the parcel-level source of truth;
# `data_document` is derived from it for transaction-level questions. Delete
# the cache, or increment the schema version, whenever these rules change.
clean_cache_path <- file.path("cache", "philly_rtt_clean_v6.rds")
clean_cache_version <- 6L
cache_loaded <- FALSE

if (file.exists(clean_cache_path)) {
  cached_objects <- tryCatch(
    readRDS(clean_cache_path),
    error = function(e) {
      warning("Clean cache could not be read; rebuilding from CSV: ", conditionMessage(e))
      NULL
    }
  )

  if (
    is.list(cached_objects) &&
      identical(cached_objects$cache_version, clean_cache_version)
  ) {
    parcel_clean <- cached_objects$parcel_clean
    transactions_by_doc <- cached_objects$transactions_by_doc
    document_ward_bridge <- cached_objects$document_ward_bridge
    transactions_by_doc_primary_ward <-
      cached_objects$transactions_by_doc_primary_ward
    cleaning_audit <- cached_objects$cleaning_audit
    sale_price_outlier_cutoff <- cached_objects$sale_price_outlier_cutoff
    cache_loaded <- TRUE
    message("Loaded cleaned Philadelphia RTT objects from: ", clean_cache_path)
  }
}

if (!cache_loaded) {
  raw <- read_csv(
    file.path("data", "raw", "rtt_summary.csv"),
    # Values such as "1/2" are fractional street-address suffixes, not Boolean
    # flags. Declaring the type prevents readr from converting them to NA and
    # eliminates the corresponding RStudio Problems-pane warnings.
    col_types = cols(
      record_id = col_character(),
      document_id = col_character(),
      opa_account_num = col_character(),
      zip_code = col_character(),
      address_low_frac = col_character(),
      street_postdir = col_character()
    ),
    show_col_types = FALSE
  )

  # Preserve readr's row/column-level parsing diagnostics instead of relying on
  # the transient Problems pane in RStudio. A small number of malformed source
  # values can then be reviewed without losing the rest of the valid records.
  raw_parse_problems <- problems(raw)
  write_csv(raw_parse_problems, "cache/raw_parse_problems.csv")
  message(
    "CSV parsing diagnostics written to cache/raw_parse_problems.csv (",
    nrow(raw_parse_problems), " issue(s))."
  )
}

# =============================================================================
# SECTION 2 (DESCRIPTIVE): INITIAL DIAGNOSTICS (documented findings that
# drive the cleaning rules below -- kept here for transparency/reproducibility)
# =============================================================================
# - 5,168,394 rows / 47 cols; each row is a document x property record, so a
#   single legal document_id can repeat across multiple property parcels.
# - document_type has 36 categories. Every type containing DEED is assigned to
#   sale_deed and the non-exact variants receive a deed_variant flag. MORTGAGE
#   and ORIGINAL FINANCING STATEMENT identify new financing. Satisfaction,
#   assignment, and release types form a separate mortgage-lifecycle bucket.
# - The current raw discrepancy field contains 16,203 explicit True values. The group
#   decision is to exclude those source-flagged rows and record the removal in
#   the team metadata.
# - display_date/recording_date agree in ~78% of rows; a small number of
#   dates are corrupted (years like 0182, 0206, 9798) from data entry errors.
#   Restricting to 2000-01-01 through 2026-07-31 removes essentially all of
#   these and retains every complete month approved by the group. August 2026
#   is excluded because the source ends on August 24.
# - Record volume is negligible before 1999 (a few hundred to low thousands
#   per year) then jumps to ~100k/year from 2000 on -- consistent with the
#   RTT system's effective start date. This supports starting the panel in
#   2000 rather than it being a modeling choice alone.
# - zip_code is stored as a 5- or 9-digit number with no separator (i.e.
#   ZIP+4 concatenated for ~25% of rows); needs first 5 digits only.
# - For DEED records, total_consideration is NA only ~4.7% of the time (a
#   reasonable price field). For MORTGAGE records, total_consideration is NA
#   ~77% of the time and cash_consideration is 0/NA ~100% of the time --
#   this dataset does not reliably capture mortgage loan amounts, so mortgage
#   *volume* (count of documents), not dollar value, is the usable signal.
# - adjusted_* monetary columns behave like parcel-level allocations: summing
#   them across a fully covered multi-property document usually reconciles to
#   the reported document total. They are therefore kept separate from the raw
#   reported values and summed only with explicit coverage checks.

# =============================================================================
# SECTION 3 (DESCRIPTIVE / DATA PREPARATION): CLEANING
# =============================================================================
# This section first cleans the source at its natural parcel-record grain: one
# row per `record_id`. No valid property row is removed merely because its
# `document_id` appears elsewhere. A second, derived table then aggregates to
# one row per legal document for transaction counts, citywide forecasting, and
# Tableau. The two grains answer different questions and are kept separately.

if (!cache_loaded) {
raw_row_count <- nrow(raw)
raw_discrepancy_count <- sum(
  str_to_lower(str_trim(as.character(raw$discrepancy))) %in%
    c("true", "t", "1", "yes", "y")
)

parcel_clean <- raw |>
  mutate(
    # The group decision is to remove rows explicitly marked as source
    # discrepancies. Missing and False both remain. Normalize the source text
    # first so the rule is stable if readr's type guessing changes.
    source_discrepancy = str_to_lower(str_trim(as.character(discrepancy))) %in%
      c("true", "t", "1", "yes", "y"),
    # Preserve reported document amounts before creating parcel-level clean
    # values. The reported amount may repeat on every parcel row, whereas the
    # adjusted amount behaves like a parcel allocation and is additive.
    reported_total_consideration = total_consideration,
    reported_local_tax_amount = local_tax_amount,
    reported_state_tax_amount = state_tax_amount,
    # Prefer adjusted (corrected/allocated) values for parcel analysis.
    total_consideration = coalesce(adjusted_total_consideration, total_consideration),
    cash_consideration = coalesce(adjusted_cash_consideration, cash_consideration),
    local_tax_amount = coalesce(adjusted_local_tax_amount, local_tax_amount),
    state_tax_amount = coalesce(adjusted_state_tax_amount, state_tax_amount),
    assessed_value = coalesce(adjusted_assessed_value, assessed_value),
    fair_market_value = coalesce(adjusted_fair_market_value, fair_market_value),
    # Canonical transaction date + calendar fields
    record_date = as_date(coalesce(recording_date, display_date)),
    year = year(record_date),
    month = month(record_date),
    yr_mo = floor_date(record_date, "month"),
    quarter = floor_date(record_date, "quarter"),
    # Standardize ZIP/ZIP+4 to five characters. This is a formatting rule, not
    # a claim that every nonmissing code has been geographically validated.
    zip5 = str_sub(as.character(zip_code), 1, 5),
    # Group detailed document types into analysis categories. Every source
    # type containing the word DEED is treated as a deed variant, matching the
    # group presentation rather than limiting sales to the exact value DEED.
    activity_type = case_when(
      is.na(document_type) ~ "unknown",
      str_detect(document_type, regex("\\bDEED\\b", ignore_case = TRUE)) ~
        "sale_deed",
      document_type %in% c("MORTGAGE", "ORIGINAL FINANCING STATEMENT") ~ "new_mortgage",
      document_type %in% c(
        "SATISFACTION", "SATISFACTION OF MORTGAGE", "RELEASE OF MORTGAGE",
        "ASSIGNMENT OF MORTGAGE", "RELEASE", "ASSIGNMENT"
      ) ~ "mortgage_lifecycle",
      TRUE ~ "other"
    ),
    transaction_type = case_when(
      activity_type == "sale_deed" ~ "Sale",
      activity_type %in% c("new_mortgage", "mortgage_lifecycle") ~ "Loan",
      TRUE ~ "Other"
    ),
    deed_variant = activity_type == "sale_deed" & document_type != "DEED",
    # Nominal-transfer status is a document concept. Prefer the reported
    # document total here so a small parcel allocation does not misclassify a
    # larger multi-property sale; fall back to the adjusted value if needed.
    nominal_transfer = activity_type == "sale_deed" &
      !is.na(coalesce(reported_total_consideration, adjusted_total_consideration)) &
      coalesce(reported_total_consideration, adjusted_total_consideration) <= 100,
    unknown_consideration = activity_type == "sale_deed" &
      is.na(reported_total_consideration) &
      is.na(adjusted_total_consideration)
  ) |>
  filter(
    !source_discrepancy,
    !is.na(record_date),
    record_date >= analysis_start,
    record_date <= analysis_end
  )

# The full raw object is no longer needed after the parcel filter. Releasing it
# before document aggregation prevents the first build from holding two large
# copies of the source in memory.
rm(raw)
invisible(gc())

# Derive a one-row-per-document analytical table after parcel-level cleaning.
# This is aggregation, not duplicate deletion. Adjusted parcel allocations are
# summed when every parcel has one. Otherwise, a single consistent reported
# document total is used as the fallback. Documents without an ID remain in
# parcel_clean but cannot be aggregated safely.
document_source <- parcel_clean |>
  filter(!is.na(document_id)) |>
  select(
    document_id,
    activity_type,
    transaction_type,
    deed_variant,
    record_date,
    adjusted_total_consideration,
    reported_total_consideration,
    cash_consideration,
    ward,
    zip5
  )

# A forward duplicate test misses the first row of each repeated ID; the
# reverse test identifies that first row. Their union marks every row that
# belongs to a multi-parcel document without grouping millions of unique IDs.
multi_parcel_row <- duplicated(document_source$document_id) |
  duplicated(document_source$document_id, fromLast = TRUE)

# Most legal documents contain one parcel. Pass those records through directly
# and reserve grouped conflict/reconciliation work for actual multi-parcel
# filings. This produces the same document schema without evaluating complex
# group expressions millions of unnecessary times.
single_parcel_documents <- document_source |>
  filter(!multi_parcel_row) |>
  transmute(
    document_id,
    activity_type_conflict = FALSE,
    record_date_conflict = FALSE,
    total_consideration_conflict = FALSE,
    cash_consideration_conflict = FALSE,
    activity_type,
    transaction_type,
    deed_variant,
    record_date,
    adjusted_consideration_coverage_pct =
      as.numeric(!is.na(adjusted_total_consideration)),
    consideration_aggregation_method = case_when(
      !is.na(adjusted_total_consideration) ~ "sum_adjusted_parcel_values",
      !is.na(reported_total_consideration) ~ "reported_document_value",
      TRUE ~ "missing_or_conflicting"
    ),
    total_consideration = coalesce(
      adjusted_total_consideration,
      reported_total_consideration
    ),
    consideration_reconciliation_difference = if_else(
      !is.na(adjusted_total_consideration) &
        !is.na(reported_total_consideration),
      adjusted_total_consideration - reported_total_consideration,
      NA_real_
    ),
    cash_consideration,
    n_parcel_rows = 1L,
    n_wards = as.integer(!is.na(ward)),
    n_zips = as.integer(!is.na(zip5) & zip5 != "")
  )

multi_parcel_documents <- document_source |>
  filter(multi_parcel_row) |>
  summarise(
    # These conflict flags preserve evidence of inconsistent parcel rows.
    activity_type_conflict = n_distinct(activity_type, na.rm = TRUE) > 1,
    record_date_conflict = n_distinct(record_date, na.rm = TRUE) > 1,
    total_consideration_conflict =
      n_distinct(reported_total_consideration, na.rm = TRUE) > 1,
    cash_consideration_conflict = n_distinct(cash_consideration, na.rm = TRUE) > 1,
    activity_type = if_else(
      activity_type_conflict,
      "conflicting",
      first(activity_type[!is.na(activity_type)], default = "unknown")
    ),
    transaction_type = if_else(
      activity_type_conflict,
      "Conflicting",
      first(transaction_type[!is.na(transaction_type)], default = "Other")
    ),
    deed_variant = if_else(
      activity_type_conflict,
      NA,
      any(deed_variant, na.rm = TRUE)
    ),
    # Use the earliest recording date when parcel rows disagree, and flag it.
    record_date = min(record_date),
    adjusted_consideration_coverage_pct =
      mean(!is.na(adjusted_total_consideration)),
    consideration_aggregation_method = case_when(
      all(!is.na(adjusted_total_consideration)) ~ "sum_adjusted_parcel_values",
      n_distinct(reported_total_consideration, na.rm = TRUE) == 1L ~
        "reported_document_value",
      TRUE ~ "missing_or_conflicting"
    ),
    total_consideration = {
      reported_values <- unique(na.omit(reported_total_consideration))
      if (all(!is.na(adjusted_total_consideration))) {
        sum(adjusted_total_consideration)
      } else if (length(reported_values) == 1L) {
        reported_values[[1]]
      } else {
        NA_real_
      }
    },
    consideration_reconciliation_difference = {
      reported_values <- unique(na.omit(reported_total_consideration))
      if (
        all(!is.na(adjusted_total_consideration)) &&
          length(reported_values) == 1L
      ) {
        sum(adjusted_total_consideration) - reported_values[[1]]
      } else {
        NA_real_
      }
    },
    cash_consideration = if_else(
      cash_consideration_conflict,
      NA_real_,
      first(cash_consideration[!is.na(cash_consideration)], default = NA_real_)
    ),
    n_parcel_rows = n(),
    n_wards = n_distinct(ward, na.rm = TRUE),
    n_zips = n_distinct(zip5, na.rm = TRUE),
    .by = document_id
  )

transactions_by_doc <- bind_rows(
  single_parcel_documents,
  multi_parcel_documents
) |>
  mutate(
    year = year(record_date),
    month = month(record_date),
    yr_mo = floor_date(record_date, "month"),
    quarter = floor_date(record_date, "quarter"),
    nominal_transfer = activity_type == "sale_deed" &
      !is.na(total_consideration) & total_consideration <= 100,
    unknown_consideration = activity_type == "sale_deed" &
      is.na(total_consideration)
  )

rm(
  document_source,
  multi_parcel_row,
  single_parcel_documents,
  multi_parcel_documents
)
invisible(gc())

# High-value transactions remain in the data, but the group agreed to flag the
# upper 0.1% of non-nominal deed consideration so typical-price summaries can
# exclude them consistently. The cutoff is calculated at document grain to
# avoid allowing repeated parcel rows to distort the percentile.
sale_price_outlier_cutoff <- quantile(
  transactions_by_doc$total_consideration[
    transactions_by_doc$activity_type == "sale_deed" &
      !transactions_by_doc$nominal_transfer &
      !is.na(transactions_by_doc$total_consideration) &
      transactions_by_doc$total_consideration > 100
  ],
  probs = 0.999,
  na.rm = TRUE,
  names = FALSE,
  type = 7
)

transactions_by_doc <- transactions_by_doc |>
  mutate(
    high_value_sale_outlier = activity_type == "sale_deed" &
      !nominal_transfer &
      !is.na(total_consideration) &
      total_consideration > sale_price_outlier_cutoff
  )

cleaning_audit <- tibble(
  raw_rows = raw_row_count,
  rows_removed_source_discrepancy = raw_discrepancy_count,
  rows_after_cleaning = nrow(parcel_clean),
  sale_price_outlier_quantile = 0.999,
  sale_price_outlier_cutoff = sale_price_outlier_cutoff
)

# One row per document x ward, retaining how many parcel rows each document
# has in each ward. is_primary_ward assigns every document to exactly one ward
# (the ward containing the most parcel rows; lowest ward breaks a tie). Use the
# primary ward for additive ward totals and Solver so a multi-ward document is
# never counted or audited twice. The full bridge remains available for maps.
document_ward_bridge <- parcel_clean |>
  filter(!is.na(document_id), !is.na(ward)) |>
  count(document_id, ward, name = "parcel_rows_in_ward") |>
  arrange(document_id, desc(parcel_rows_in_ward), ward) |>
  mutate(
    ward_share = parcel_rows_in_ward / sum(parcel_rows_in_ward),
    is_primary_ward = row_number() == 1L,
    .by = document_id
  )

transactions_by_doc_primary_ward <- transactions_by_doc |>
  left_join(
    document_ward_bridge |>
      filter(is_primary_ward) |>
      select(document_id, ward),
    by = "document_id"
  )

saveRDS(
  list(
    cache_version = clean_cache_version,
    parcel_clean = parcel_clean,
    transactions_by_doc = transactions_by_doc,
    document_ward_bridge = document_ward_bridge,
    transactions_by_doc_primary_ward = transactions_by_doc_primary_ward,
    cleaning_audit = cleaning_audit,
    sale_price_outlier_cutoff = sale_price_outlier_cutoff
  ),
  clean_cache_path
)
message("Saved cleaned Philadelphia RTT cache to: ", clean_cache_path)
rm(raw_row_count, raw_discrepancy_count)
}

# Compact checks for both declared grains.
parcel_grain_summary <- parcel_clean |>
  summarise(
    parcel_rows = n(),
    missing_record_id = sum(is.na(record_id)),
    unique_record_ids = n_distinct(record_id, na.rm = TRUE),
    repeated_document_rows = n() - n_distinct(document_id, na.rm = TRUE)
  )

document_grain_summary <- transactions_by_doc |>
  summarise(
    clean_rows = nrow(parcel_clean),
    rows_missing_document_id = sum(is.na(parcel_clean$document_id)),
    unique_document_ids = n_distinct(parcel_clean$document_id, na.rm = TRUE),
    document_rows = n(),
    multi_parcel_documents = sum(n_parcel_rows > 1),
    conflicting_activity_types = sum(activity_type_conflict),
    conflicting_record_dates = sum(record_date_conflict),
    conflicting_total_consideration = sum(total_consideration_conflict),
    multi_ward_documents = sum(n_wards > 1),
    high_value_sale_outliers = sum(high_value_sale_outlier)
  )

stopifnot(
  !anyNA(parcel_clean$record_id),
  !anyDuplicated(parcel_clean$record_id),
  nrow(transactions_by_doc) == n_distinct(parcel_clean$document_id, na.rm = TRUE)
)

parcel_grain_summary
document_grain_summary

# =============================================================================
# SECTION 3B (TEAM HANDOFF): PARCEL SOURCE + DOCUMENT DERIVATIVE
# =============================================================================
# Purpose:
#   Give every team member the same parcel-level clean starting point while
#   also supplying a reproducible document-level derivative. Repeated
#   document_id values are retained in data_clean because they can represent
#   different properties on the same filing; they are not deleted as duplicates.
#
# How the two cleaning layers fit together:
#   `data_clean`: one row per record_id. Use for property, assessment,
#     geography, mapping, and parcel-level modeling.
#   `data_document`: one row per document_id. Use for transaction counts,
#     citywide forecasting, additive primary-ward summaries, and Tableau.
#   Sections below name the input table explicitly so the analytical grain is
#   visible rather than hidden inside a generic object.
#
# Refresh policy:
#   The compressed CSV is created when missing. Set
#   options(bsan.refresh_team_data = TRUE) before sourcing this script to
#   rebuild it deliberately. Increment `team_export_version` whenever its
#   schema or aggregation rules change.

team_export_version <- 6L
team_data_path <- file.path("team_data", "data_clean.csv.gz")
document_data_path <- file.path("team_data", "data_document.csv.gz")
team_dictionary_path <- file.path("team_data", "data_clean_dictionary.csv")
document_dictionary_path <- file.path(
  "team_data", "data_document_dictionary.csv"
)
team_metadata_path <- file.path("team_data", "data_clean_metadata.csv")
refresh_team_data <- isTRUE(getOption("bsan.refresh_team_data", FALSE))

# Explicit types make both compressed CSV files load consistently. Identifiers
# and ZIP codes remain text, while calendar keys remain Date columns.
parcel_data_col_types <- cols(
  record_id = col_character(),
  document_id = col_character(),
  document_type = col_character(),
  activity_type = col_character(),
  transaction_type = col_character(),
  deed_variant = col_logical(),
  record_date = col_date(),
  document_date = col_date(),
  receipt_date = col_date(),
  year = col_integer(),
  month = col_integer(),
  yr_mo = col_date(),
  quarter = col_date(),
  street_address = col_character(),
  ward = col_integer(),
  zip5 = col_character(),
  opa_account_num = col_character(),
  property_count = col_integer(),
  reported_total_consideration = col_double(),
  adjusted_total_consideration = col_double(),
  total_consideration = col_double(),
  reported_local_tax_amount = col_double(),
  adjusted_local_tax_amount = col_double(),
  local_tax_amount = col_double(),
  reported_state_tax_amount = col_double(),
  adjusted_state_tax_amount = col_double(),
  state_tax_amount = col_double(),
  local_tax_percent = col_double(),
  state_tax_percent = col_double(),
  assessed_value = col_double(),
  fair_market_value = col_double(),
  nominal_transfer = col_logical(),
  unknown_consideration = col_logical(),
  high_value_sale_outlier = col_logical(),
  shape = col_character()
)

document_data_col_types <- cols(
  document_id = col_character(),
  document_type = col_character(),
  activity_type = col_character(),
  transaction_type = col_character(),
  deed_variant = col_logical(),
  record_date = col_date(),
  document_date = col_date(),
  receipt_date = col_date(),
  recording_delay_from_document_days = col_integer(),
  recording_delay_from_receipt_days = col_integer(),
  year = col_integer(),
  month = col_integer(),
  yr_mo = col_date(),
  quarter = col_date(),
  primary_ward = col_integer(),
  primary_zip5 = col_character(),
  n_parcel_rows = col_integer(),
  n_wards = col_integer(),
  n_zips = col_integer(),
  transaction_count = col_integer(),
  total_consideration = col_double(),
  adjusted_consideration_coverage_pct = col_double(),
  consideration_aggregation_method = col_character(),
  consideration_reconciliation_difference = col_double(),
  local_tax_amount = col_double(),
  adjusted_local_tax_coverage_pct = col_double(),
  local_tax_aggregation_method = col_character(),
  local_tax_reconciliation_difference = col_double(),
  state_tax_amount = col_double(),
  adjusted_state_tax_coverage_pct = col_double(),
  state_tax_aggregation_method = col_character(),
  state_tax_reconciliation_difference = col_double(),
  assessed_value_total = col_double(),
  assessed_value_median = col_double(),
  assessed_parcel_rows = col_integer(),
  assessment_coverage_pct = col_double(),
  nominal_transfer = col_logical(),
  unknown_consideration = col_logical(),
  high_value_sale_outlier = col_logical(),
  activity_type_conflict = col_logical(),
  document_type_conflict = col_logical(),
  record_date_conflict = col_logical(),
  document_date_conflict = col_logical(),
  receipt_date_conflict = col_logical(),
  total_consideration_conflict = col_logical(),
  local_tax_conflict = col_logical(),
  state_tax_conflict = col_logical()
)

team_metadata_matches <- FALSE
if (file.exists(team_metadata_path)) {
  existing_team_metadata <- tryCatch(
    read_csv(team_metadata_path, show_col_types = FALSE),
    error = function(e) NULL
  )

  team_metadata_matches <-
    !is.null(existing_team_metadata) &&
    nrow(existing_team_metadata) == 1L &&
    as.integer(existing_team_metadata$team_export_version[[1]]) ==
      team_export_version &&
    as.integer(existing_team_metadata$clean_cache_version[[1]]) ==
      clean_cache_version
}

team_data_needs_refresh <-
  refresh_team_data ||
  !file.exists(team_data_path) ||
  !file.exists(document_data_path) ||
  !team_metadata_matches

# Dictionaries are kept beside the export logic so their definitions cannot
# drift silently from the files shared with the team.
parcel_data_dictionary <- tribble(
  ~column, ~grain, ~purpose, ~important_caveat,
  "record_id", "parcel record", "Unique source-row identifier", "Primary key for data_clean",
  "document_id", "document", "Legal filing identifier shared by related properties", "May repeat; use distinct counts for transactions",
  "document_type", "parcel record", "Detailed source filing type", "Use activity_type for the main analysis categories",
  "activity_type", "parcel record", "Sale deed, new mortgage, mortgage lifecycle, other, or unknown", "Category repeats across parcels in the same document",
  "transaction_type", "parcel record", "Broad Sale, Loan, or Other label", "Sale includes every detailed type containing DEED; Loan includes new and lifecycle mortgage activity",
  "deed_variant", "parcel record", "Identifies sale-deed types other than the exact DEED label", "Retained for sensitivity checks because some variants are not ordinary market sales",
  "record_date", "parcel record", "Canonical recording/display date", "Drives the January 2000 through July 2026 analysis window",
  "document_date", "parcel record", "Date the instrument was executed", "Not the default transaction-count date",
  "receipt_date", "parcel record", "Date the filing was received", "May differ from record_date",
  "year", "parcel record", "Calendar year of record_date", "Not a fiscal-year field",
  "month", "parcel record", "Calendar month number", "Use yr_mo for monthly grouping",
  "yr_mo", "parcel record", "First day of record month", "Monthly analysis key",
  "quarter", "parcel record", "First day of calendar quarter", "Derived from record_date",
  "street_address", "parcel", "Property street address", "May be missing or nonstandard",
  "ward", "parcel", "Ward attached to this property row", "A document may touch more than one ward",
  "zip5", "parcel", "Standardized five-digit ZIP", "Derived from the source ZIP/ZIP+4 value",
  "opa_account_num", "parcel", "OPA property account identifier", "Stored as text to preserve formatting",
  "property_count", "document", "Source count of properties on the filing", "Repeated across its parcel rows",
  "reported_total_consideration", "document", "Original reported document consideration", "Can repeat across parcels; never sum this field across parcel rows",
  "adjusted_total_consideration", "parcel", "Adjusted consideration allocated to this parcel row", "Sum only after checking coverage",
  "total_consideration", "parcel", "Adjusted consideration with reported value as fallback", "Convenient for parcel analysis but mixed provenance; document aggregation uses the two source fields above",
  "reported_local_tax_amount", "document", "Original reported local transfer tax", "Can repeat across parcels; never sum this field across parcel rows",
  "adjusted_local_tax_amount", "parcel", "Adjusted local tax allocated to this parcel row", "Preferred additive field when all document parcels are covered",
  "local_tax_amount", "parcel", "Adjusted local tax with reported value as fallback", "Do not sum blindly when adjusted values are missing",
  "reported_state_tax_amount", "document", "Original reported state transfer tax", "Can repeat across parcels; never sum this field across parcel rows",
  "adjusted_state_tax_amount", "parcel", "Adjusted state tax allocated to this parcel row", "Preferred additive field when all document parcels are covered",
  "state_tax_amount", "parcel", "Adjusted state tax with reported value as fallback", "Do not sum blindly when adjusted values are missing",
  "local_tax_percent", "parcel record", "Source local transfer-tax percentage", "Confirm rate-period interpretation before causal use",
  "state_tax_percent", "parcel record", "Source state transfer-tax percentage", "Confirm rate-period interpretation before causal use",
  "assessed_value", "parcel", "Adjusted assessed value with reported value as fallback", "Missingness must be reported in assessment models",
  "fair_market_value", "parcel", "Adjusted fair-market value with reported value as fallback", "Not the same as transaction consideration",
  "nominal_transfer", "document flag", "Sale deed with document consideration at or below $100", "Repeated for every parcel in the document",
  "unknown_consideration", "document flag", "Sale deed with no reported or adjusted consideration", "Kept separate from nominal transfers",
  "high_value_sale_outlier", "document flag", "Non-nominal sale above the document-level 99.9th percentile", "Retained in counts but excluded from typical-price summaries; repeated for every parcel in the document",
  "shape", "parcel geometry", "Source point geometry for mapping", "Not an input to ordinary k-means unless transformed into meaningful coordinates/features"
)

document_data_dictionary <- tribble(
  ~column, ~grain, ~purpose, ~aggregation_rule, ~important_caveat,
  "document_id", "document", "Unique legal filing identifier", "Key; never sum", "Defines the transaction-counting grain",
  "document_type", "document", "Detailed source filing type", "Category", "Set to CONFLICTING when parcel rows disagree",
  "activity_type", "document", "Analysis category for deed, mortgage, lifecycle, other, or unknown", "Category", "Use sale_deed and new_mortgage for the main research question",
  "transaction_type", "document", "Broad Sale, Loan, Other, or Conflicting label", "Derived from activity_type", "Loan combines new mortgages with mortgage lifecycle filings; use activity_type when the distinction matters",
  "deed_variant", "document", "Identifies a sale document whose detailed type is not exact DEED", "Any deed-variant parcel when the activity category is consistent", "Variant deeds remain in sale counts but can be isolated in sensitivity checks",
  "record_date", "document", "Canonical filing date used by the project", "Earliest recording/display date when source rows disagree", "Drives the January 2000 through July 2026 analysis window",
  "document_date", "document", "Earliest date the instrument was executed", "Earliest nonmissing valid document date", "Dates outside 1800-2025 are treated as missing; not the default revenue-recognition date",
  "receipt_date", "document", "Earliest date the filing was received", "Earliest nonmissing receipt date", "Compare with record_date before using for revenue timing",
  "recording_delay_from_document_days", "document", "Days from document execution to recording", "record_date minus document_date", "Can be negative when source dates are inconsistent",
  "recording_delay_from_receipt_days", "document", "Days from receipt to recording", "record_date minus receipt_date", "Can be negative when source dates are inconsistent",
  "year", "document", "Calendar year of record_date", "Derived", "Not a fiscal-year field",
  "month", "document", "Calendar month number of record_date", "Derived", "Use yr_mo for time-series grouping",
  "yr_mo", "document", "First day of the record month", "Derived", "Monthly analysis key",
  "quarter", "document", "First day of the record quarter", "Derived", "Calendar quarter",
  "primary_ward", "document", "Single ward used for additive ward totals", "Most parcel rows; lowest ward breaks a tie", "A practical allocation rule for multi-ward documents",
  "primary_zip5", "document", "Single five-digit ZIP used for additive ZIP totals", "Most parcel rows; lowest ZIP breaks a tie", "A practical allocation rule for multi-ZIP documents",
  "n_parcel_rows", "document", "Number of source parcel rows in the document", "Count", "Values above one identify multi-parcel filings",
  "n_wards", "document", "Number of wards touched by the document", "Distinct count", "Zero means ward is unavailable",
  "n_zips", "document", "Number of ZIP codes touched by the document", "Distinct count", "Zero means ZIP is unavailable",
  "transaction_count", "document", "Safe additive transaction counter", "Always 1", "Sum this field for transaction volume",
  "total_consideration", "document", "Document consideration used for analysis", "Sum complete adjusted parcel allocations; otherwise use one consistent reported document value", "Mortgage consideration is too incomplete for loan-value analysis",
  "adjusted_consideration_coverage_pct", "document", "Share of parcel rows with adjusted consideration", "Nonmissing adjusted rows divided by parcel rows", "Values below 1 trigger the reported-value fallback when available",
  "consideration_aggregation_method", "document", "Rule used to create total_consideration", "Method label", "Distinguishes adjusted sums from reported fallbacks",
  "consideration_reconciliation_difference", "document", "Adjusted parcel sum minus reported document consideration", "Calculated when both are fully available", "Investigate material nonzero differences",
  "local_tax_amount", "document", "Recorded Philadelphia transfer-tax amount", "Sum complete adjusted parcel allocations; otherwise use one consistent reported document value", "Recorded filing amount is not automatically cash revenue received",
  "adjusted_local_tax_coverage_pct", "document", "Share of parcel rows with adjusted local tax", "Nonmissing adjusted rows divided by parcel rows", "Values below 1 trigger the reported-value fallback when available",
  "local_tax_aggregation_method", "document", "Rule used to create local_tax_amount", "Method label", "Distinguishes adjusted sums from reported fallbacks",
  "local_tax_reconciliation_difference", "document", "Adjusted parcel tax sum minus reported local tax", "Calculated when both are fully available", "Investigate material nonzero differences",
  "state_tax_amount", "document", "Recorded Commonwealth transfer-tax amount", "Sum complete adjusted parcel allocations; otherwise use one consistent reported document value", "Included as a reconciliation field, not City revenue",
  "adjusted_state_tax_coverage_pct", "document", "Share of parcel rows with adjusted state tax", "Nonmissing adjusted rows divided by parcel rows", "Values below 1 trigger the reported-value fallback when available",
  "state_tax_aggregation_method", "document", "Rule used to create state_tax_amount", "Method label", "Distinguishes adjusted sums from reported fallbacks",
  "state_tax_reconciliation_difference", "document", "Adjusted parcel tax sum minus reported state tax", "Calculated when both are fully available", "Investigate material nonzero differences",
  "assessed_value_total", "document", "Sum of available assessed values across parcel rows", "Sum across nonmissing parcel rows", "Do not treat missing parcels as zero-valued property",
  "assessed_value_median", "document", "Median available parcel assessed value", "Median across nonmissing parcel rows", "Primarily descriptive for multi-parcel documents",
  "assessed_parcel_rows", "document", "Parcel rows with an assessed value", "Nonmissing count", "Compare with n_parcel_rows",
  "assessment_coverage_pct", "document", "Share of parcel rows with assessed values", "assessed_parcel_rows divided by n_parcel_rows", "Low coverage weakens document-level assessment comparisons",
  "nominal_transfer", "document", "Deed with reported consideration at or below $100", "Derived Boolean", "Missing consideration is not classified as nominal",
  "unknown_consideration", "document", "Deed with missing consideration", "Derived Boolean", "Keep separate from nominal transfers",
  "high_value_sale_outlier", "document", "Non-nominal sale above the 99.9th percentile of eligible document consideration", "Derived Boolean", "Retain the transaction but exclude it from typical-price summaries",
  "activity_type_conflict", "document", "Parcel rows disagree on activity category", "Any conflict", "Conflicted documents should be reviewed before category modeling",
  "document_type_conflict", "document", "Parcel rows disagree on detailed document type", "Any conflict", "Detailed type is replaced by CONFLICTING",
  "record_date_conflict", "document", "Parcel rows disagree on canonical record date", "Any conflict", "Earliest date is retained",
  "document_date_conflict", "document", "Parcel rows disagree on document date", "Any conflict", "Earliest date is retained",
  "receipt_date_conflict", "document", "Parcel rows disagree on receipt date", "Any conflict", "Earliest date is retained",
  "total_consideration_conflict", "document", "Reported document consideration differs across parcel rows", "Any conflict", "Complete adjusted parcel allocations can still supply the document total",
  "local_tax_conflict", "document", "Reported local tax differs across parcel rows", "Any conflict", "Complete adjusted parcel allocations can still supply the document total",
  "state_tax_conflict", "document", "Reported state tax differs across parcel rows", "Any conflict", "Complete adjusted parcel allocations can still supply the document total"
)

write_csv(parcel_data_dictionary, team_dictionary_path)
write_csv(document_data_dictionary, document_dictionary_path)

if (team_data_needs_refresh) {
  message("Building parcel-level data_clean and document-level data_document...")

  # Canonical team table: one row per source record_id. This deliberately
  # retains repeated document_id values because each row can identify a
  # different property attached to the same filing.
  data_clean <- parcel_clean |>
    left_join(
      transactions_by_doc |>
        select(document_id, high_value_sale_outlier),
      by = "document_id"
    ) |>
    transmute(
      record_id = as.character(record_id),
      document_id = as.character(document_id),
      document_type,
      activity_type,
      transaction_type,
      deed_variant,
      record_date,
      document_date = as_date(document_date),
      receipt_date = as_date(receipt_date),
      year,
      month,
      yr_mo,
      quarter,
      street_address,
      ward = as.integer(ward),
      zip5,
      opa_account_num = as.character(opa_account_num),
      property_count = as.integer(property_count),
      reported_total_consideration,
      adjusted_total_consideration,
      total_consideration,
      reported_local_tax_amount,
      adjusted_local_tax_amount,
      local_tax_amount,
      reported_state_tax_amount,
      adjusted_state_tax_amount,
      state_tax_amount,
      local_tax_percent,
      state_tax_percent,
      assessed_value,
      fair_market_value,
      nominal_transfer,
      unknown_consideration,
      high_value_sale_outlier,
      shape = as.character(shape)
    ) |>
    mutate(
      document_date = if_else(
        is.na(document_date) |
          between(document_date, as_date("1800-01-01"), analysis_end),
        document_date,
        as_date(NA)
      )
    )

  # Build document-level fields not needed by the original forecasting code.
  # Reported document totals and adjusted parcel allocations stay separate so
  # the correct aggregation rule can be applied and audited.
  team_extension_source <- parcel_clean |>
    filter(!is.na(document_id)) |>
    transmute(
      document_id,
      document_type,
      document_date = as_date(document_date),
      receipt_date = as_date(receipt_date),
      reported_local_tax_amount,
      adjusted_local_tax_amount,
      reported_state_tax_amount,
      adjusted_state_tax_amount,
      assessed_value
    ) |>
    mutate(
      # Remove clearly corrupted execution dates before aggregation. The raw
      # source remains untouched, while the central CSV receives ISO dates that
      # can be read consistently by every team member.
      document_date = if_else(
        is.na(document_date) |
          between(
            document_date,
            as_date("1800-01-01"),
            analysis_end
          ),
        document_date,
        as_date(NA)
      )
    ) |>
    left_join(
      transactions_by_doc |> select(document_id, n_parcel_rows),
      by = "document_id"
    )

  # Most documents have only one parcel row. Passing those rows through
  # directly avoids running expensive grouped statistics millions of times.
  team_single_document_extension <- team_extension_source |>
    filter(n_parcel_rows == 1L) |>
    transmute(
      document_id,
      document_type_conflict = FALSE,
      document_date_conflict = FALSE,
      receipt_date_conflict = FALSE,
      local_tax_conflict = FALSE,
      state_tax_conflict = FALSE,
      document_type = coalesce(document_type, "UNKNOWN"),
      document_date,
      receipt_date,
      local_tax_amount = coalesce(
        adjusted_local_tax_amount,
        reported_local_tax_amount
      ),
      adjusted_local_tax_coverage_pct =
        as.numeric(!is.na(adjusted_local_tax_amount)),
      local_tax_aggregation_method = case_when(
        !is.na(adjusted_local_tax_amount) ~ "sum_adjusted_parcel_values",
        !is.na(reported_local_tax_amount) ~ "reported_document_value",
        TRUE ~ "missing_or_conflicting"
      ),
      local_tax_reconciliation_difference = if_else(
        !is.na(adjusted_local_tax_amount) &
          !is.na(reported_local_tax_amount),
        adjusted_local_tax_amount - reported_local_tax_amount,
        NA_real_
      ),
      state_tax_amount = coalesce(
        adjusted_state_tax_amount,
        reported_state_tax_amount
      ),
      adjusted_state_tax_coverage_pct =
        as.numeric(!is.na(adjusted_state_tax_amount)),
      state_tax_aggregation_method = case_when(
        !is.na(adjusted_state_tax_amount) ~ "sum_adjusted_parcel_values",
        !is.na(reported_state_tax_amount) ~ "reported_document_value",
        TRUE ~ "missing_or_conflicting"
      ),
      state_tax_reconciliation_difference = if_else(
        !is.na(adjusted_state_tax_amount) &
          !is.na(reported_state_tax_amount),
        adjusted_state_tax_amount - reported_state_tax_amount,
        NA_real_
      ),
      assessed_value_total = assessed_value,
      assessed_value_median = assessed_value,
      assessed_parcel_rows = as.integer(!is.na(assessed_value)),
      assessment_coverage_pct = as.numeric(!is.na(assessed_value))
    )

  # Only multi-parcel documents need aggregation and conflict checks.
  team_multi_document_extension <- team_extension_source |>
    filter(n_parcel_rows > 1L) |>
    summarise(
      document_type_conflict = n_distinct(document_type, na.rm = TRUE) > 1,
      document_date_conflict = n_distinct(document_date, na.rm = TRUE) > 1,
      receipt_date_conflict = n_distinct(receipt_date, na.rm = TRUE) > 1,
      local_tax_conflict =
        n_distinct(reported_local_tax_amount, na.rm = TRUE) > 1,
      state_tax_conflict =
        n_distinct(reported_state_tax_amount, na.rm = TRUE) > 1,
      document_type = if_else(
        document_type_conflict,
        "CONFLICTING",
        first(document_type[!is.na(document_type)], default = "UNKNOWN")
      ),
      document_date = if (
        all(is.na(document_date))
      ) as_date(NA) else min(document_date, na.rm = TRUE),
      receipt_date = if (
        all(is.na(receipt_date))
      ) as_date(NA) else min(receipt_date, na.rm = TRUE),
      adjusted_local_tax_coverage_pct =
        mean(!is.na(adjusted_local_tax_amount)),
      local_tax_aggregation_method = case_when(
        all(!is.na(adjusted_local_tax_amount)) ~
          "sum_adjusted_parcel_values",
        n_distinct(reported_local_tax_amount, na.rm = TRUE) == 1L ~
          "reported_document_value",
        TRUE ~ "missing_or_conflicting"
      ),
      local_tax_amount = {
        reported_values <- unique(na.omit(reported_local_tax_amount))
        if (all(!is.na(adjusted_local_tax_amount))) {
          sum(adjusted_local_tax_amount)
        } else if (length(reported_values) == 1L) {
          reported_values[[1]]
        } else {
          NA_real_
        }
      },
      local_tax_reconciliation_difference = {
        reported_values <- unique(na.omit(reported_local_tax_amount))
        if (
          all(!is.na(adjusted_local_tax_amount)) &&
            length(reported_values) == 1L
        ) {
          sum(adjusted_local_tax_amount) - reported_values[[1]]
        } else {
          NA_real_
        }
      },
      adjusted_state_tax_coverage_pct =
        mean(!is.na(adjusted_state_tax_amount)),
      state_tax_aggregation_method = case_when(
        all(!is.na(adjusted_state_tax_amount)) ~
          "sum_adjusted_parcel_values",
        n_distinct(reported_state_tax_amount, na.rm = TRUE) == 1L ~
          "reported_document_value",
        TRUE ~ "missing_or_conflicting"
      ),
      state_tax_amount = {
        reported_values <- unique(na.omit(reported_state_tax_amount))
        if (all(!is.na(adjusted_state_tax_amount))) {
          sum(adjusted_state_tax_amount)
        } else if (length(reported_values) == 1L) {
          reported_values[[1]]
        } else {
          NA_real_
        }
      },
      state_tax_reconciliation_difference = {
        reported_values <- unique(na.omit(reported_state_tax_amount))
        if (
          all(!is.na(adjusted_state_tax_amount)) &&
            length(reported_values) == 1L
        ) {
          sum(adjusted_state_tax_amount) - reported_values[[1]]
        } else {
          NA_real_
        }
      },
      assessed_value_total = if_else(
        all(is.na(assessed_value)),
        NA_real_,
        sum(assessed_value, na.rm = TRUE)
      ),
      assessed_value_median = if (
        all(is.na(assessed_value))
      ) NA_real_ else median(assessed_value, na.rm = TRUE),
      assessed_parcel_rows = sum(!is.na(assessed_value)),
      assessment_coverage_pct = mean(!is.na(assessed_value)),
      .by = document_id
    )

  team_document_extension <- bind_rows(
    team_single_document_extension,
    team_multi_document_extension
  )

  stopifnot(
    nrow(team_document_extension) == nrow(transactions_by_doc),
    !anyDuplicated(team_document_extension$document_id)
  )

  # ZIP follows the same deterministic primary-geography rule used for wards.
  team_zip_source <- parcel_clean |>
    filter(!is.na(document_id), !is.na(zip5), zip5 != "") |>
    select(document_id, zip5) |>
    left_join(
      transactions_by_doc |> select(document_id, n_zips),
      by = "document_id"
    )

  team_single_primary_zip <- team_zip_source |>
    filter(n_zips == 1L) |>
    distinct(document_id, .keep_all = TRUE) |>
    transmute(document_id, primary_zip5 = zip5)

  team_multi_primary_zip <- team_zip_source |>
    filter(n_zips > 1L) |>
    count(document_id, zip5, name = "parcel_rows_in_zip") |>
    arrange(document_id, desc(parcel_rows_in_zip), zip5) |>
    slice_head(n = 1L, by = document_id) |>
    transmute(document_id, primary_zip5 = zip5)

  team_primary_zip <- bind_rows(
    team_single_primary_zip,
    team_multi_primary_zip
  )

  rm(
    team_extension_source,
    team_single_document_extension,
    team_multi_document_extension,
    team_zip_source,
    team_single_primary_zip,
    team_multi_primary_zip
  )
  invisible(gc())

  data_document <- transactions_by_doc_primary_ward |>
    rename(primary_ward = ward) |>
    left_join(team_document_extension, by = "document_id") |>
    left_join(team_primary_zip, by = "document_id") |>
    mutate(
      document_id = as.character(document_id),
      transaction_count = 1L,
      recording_delay_from_document_days = as.integer(
        record_date - document_date
      ),
      recording_delay_from_receipt_days = as.integer(
        record_date - receipt_date
      )
    ) |>
    select(
      document_id,
      document_type,
      activity_type,
      transaction_type,
      deed_variant,
      record_date,
      document_date,
      receipt_date,
      recording_delay_from_document_days,
      recording_delay_from_receipt_days,
      year,
      month,
      yr_mo,
      quarter,
      primary_ward,
      primary_zip5,
      n_parcel_rows,
      n_wards,
      n_zips,
      transaction_count,
      total_consideration,
      adjusted_consideration_coverage_pct,
      consideration_aggregation_method,
      consideration_reconciliation_difference,
      local_tax_amount,
      adjusted_local_tax_coverage_pct,
      local_tax_aggregation_method,
      local_tax_reconciliation_difference,
      state_tax_amount,
      adjusted_state_tax_coverage_pct,
      state_tax_aggregation_method,
      state_tax_reconciliation_difference,
      assessed_value_total,
      assessed_value_median,
      assessed_parcel_rows,
      assessment_coverage_pct,
      nominal_transfer,
      unknown_consideration,
      high_value_sale_outlier,
      activity_type_conflict,
      document_type_conflict,
      record_date_conflict,
      document_date_conflict,
      receipt_date_conflict,
      total_consideration_conflict,
      local_tax_conflict,
      state_tax_conflict
    )

  stopifnot(
    nrow(data_clean) == nrow(parcel_clean),
    !anyDuplicated(data_clean$record_id),
    identical(names(data_clean), parcel_data_dictionary$column),
    nrow(data_document) == nrow(transactions_by_doc),
    !anyDuplicated(data_document$document_id),
    sum(data_document$transaction_count) == nrow(transactions_by_doc),
    identical(names(data_document), document_data_dictionary$column)
  )

  # A .csv.gz file is still a CSV and readr::read_csv() opens it directly.
  # Both outputs are compressed because each contains millions of rows.
  write_csv(data_clean, team_data_path)
  write_csv(data_document, document_data_path)
  write_csv(
    tibble(
      team_export_version = team_export_version,
      clean_cache_version = clean_cache_version,
      generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      grain = "data_clean: record_id; data_document: document_id",
      parcel_rows = nrow(data_clean),
      parcel_columns = ncol(data_clean),
      document_rows = nrow(data_document),
      document_columns = ncol(data_document),
      raw_rows = cleaning_audit$raw_rows,
      rows_removed_source_discrepancy =
        cleaning_audit$rows_removed_source_discrepancy,
      sale_price_outlier_quantile =
        cleaning_audit$sale_price_outlier_quantile,
      sale_price_outlier_cutoff = sale_price_outlier_cutoff,
      analysis_start = analysis_start,
      analysis_end = analysis_end,
      last_complete_year = last_complete_year,
      partial_year_included = year(analysis_end) > last_complete_year
    ),
    team_metadata_path
  )

  message(
    "Team datasets written: ", scales::comma(nrow(data_clean)),
    " parcel records in ", team_data_path, "; ",
    scales::comma(nrow(data_document)), " documents in ", document_data_path,
    "."
  )

  # Release construction-only objects. Both public analytical grains remain in
  # memory so later sections can select the one that matches their question.
  rm(team_document_extension, team_primary_zip)
  invisible(gc())
} else {
  message(
    "Team datasets are current. Loading parcel and document grains."
  )

  data_clean <- read_csv(
    team_data_path,
    col_types = parcel_data_col_types,
    show_col_types = FALSE
  )
  data_document <- read_csv(
    document_data_path,
    col_types = document_data_col_types,
    show_col_types = FALSE
  )
}

# These checks apply whether the files were rebuilt or loaded. They guard the
# two declared keys and ensure neither schema changes without documentation.
stopifnot(
  !anyDuplicated(data_clean$record_id),
  identical(names(data_clean), parcel_data_dictionary$column),
  !anyDuplicated(data_document$document_id),
  all(data_document$transaction_count == 1L),
  all(!is.na(data_document$high_value_sale_outlier)),
  all(data_clean$transaction_type %in% c("Sale", "Loan", "Other")),
  cleaning_audit$rows_removed_source_discrepancy > 0,
  identical(names(data_document), document_data_dictionary$column)
)

# Allows a deliberate central-data-only rebuild without running forecasting,
# Solver, or Tableau. Normal interactive/source runs continue into analysis.
if (isTRUE(getOption("bsan.stop_after_team_data", FALSE))) {
  message("Central team datasets validated; stopping before analysis sections.")
  return(invisible(list(data_clean = data_clean, data_document = data_document)))
}

# Remove construction-only aliases. The named handoff objects remain:
# data_clean (parcel grain) and data_document (document grain).
rm(parcel_clean, transactions_by_doc, transactions_by_doc_primary_ward)
invisible(gc())

# =============================================================================
# HANDOFF FROM SECTION 3 TO SECTION 4: SELECT THE GRAIN BY QUESTION
# =============================================================================
# `data_clean` preserves one row per record_id and is the central team dataset.
# Use it for property, assessment, parcel geography, and mapping questions.
# `data_document` is derived after cleaning and has one row per document_id.
# Use it for transaction counts, document totals, forecasts, and Tableau facts.
# Neither table replaces the other; each declares a different analytical unit.
#
# `document_ward_bridge` remains only as a specialist relationship table for a
# future question that needs every ward touched by a multi-ward document. It is
# not a general analysis input because summing it can count one document more
# than once.

# =============================================================================
# SECTION 4 (DESCRIPTIVE): MONTHLY TIME SERIES FOR MODELING
# =============================================================================
# Abstract: Collapses the derived document-grain data_document table into
# one row per calendar month, at the citywide level. Deeds (sale_deed) and
# mortgages (new_mortgage) are summarized separately, then joined into a
# single table -- this is the panel every later phase builds on (EDA,
# forecasting, YoY change). We also split deed counts into "nominal"
# (<=$100, non-market transfers) vs. "arms-length" here, and compute median
# price using arms-length sales only, so later price analysis isn't skewed
# by $0/nominal transfers. Missing/conflicting consideration is counted
# separately rather than silently treated as either nominal or arms-length.

# Block 1: keep only DEED (sale) transactions, then group every transaction
# into its calendar month (yr_mo) and count/summarize within each month.
monthly_sales <- data_document |>
  filter(activity_type == "sale_deed") |> # drop mortgages/other document types
  group_by(yr_mo) |> # one group per calendar month
  summarise(
    n_deeds = n(), # total # of deeds recorded that month
    n_nominal = sum(nominal_transfer), # how many of those were nominal (<=$100)
    n_unknown_consideration = sum(unknown_consideration),
    n_high_value_sale_outlier = sum(high_value_sale_outlier),
    n_arms_length = sum(!is.na(total_consideration) & total_consideration > 100),
    recorded_local_tax = sum(local_tax_amount, na.rm = TRUE),
    n_missing_local_tax = sum(is.na(local_tax_amount)),
    # median price computed ONLY over arms-length sales, so $0/nominal
    # transfers (family transfers, city-to-redevelopment-authority, etc.)
    # don't drag the price statistic down
    median_price_arms_length = median(
      total_consideration[
        !nominal_transfer & !high_value_sale_outlier
      ],
      na.rm = TRUE
    ),
    .groups = "drop"
  )

# Block 2: same idea, but for new mortgages. We only need a count here --
# recall from earlier diagnostics that mortgage dollar amounts aren't
# reliably captured in this dataset, so there's no price stat to compute.
monthly_mortgages <- data_document |>
  filter(activity_type == "new_mortgage") |>
  group_by(yr_mo) |>
  summarise(n_mortgages = n(), .groups = "drop")

# Block 3: combine the two monthly summaries into one table, one row per
# month. full_join keeps every month that appears in EITHER table. complete()
# then forces the analytical calendar to contain every complete month from
# January 2000 through July 2026. Missing count fields become true zeroes, while a
# missing price remains NA because "no observed market price" is not $0.
monthly_activity <- monthly_sales |>
  full_join(monthly_mortgages, by = "yr_mo") |>
  complete(
    yr_mo = analysis_months,
    fill = list(
      n_deeds = 0L,
      n_nominal = 0L,
      n_unknown_consideration = 0L,
      n_high_value_sale_outlier = 0L,
      n_arms_length = 0L,
      n_mortgages = 0L,
      recorded_local_tax = 0,
      n_missing_local_tax = 0L
    )
  ) |>
  arrange(yr_mo) |>
  mutate(across(starts_with("n_"), ~ replace_na(., 0)))

stopifnot(
  nrow(monthly_activity) == length(analysis_months),
  identical(monthly_activity$yr_mo, analysis_months)
)

# =============================================================================
# SECTION 5 (DESCRIPTIVE): QUICK SANITY CHECK
# =============================================================================
# Abstract: A single plot to visually confirm Section 4's output looks
# reasonable before building anything on top of it -- e.g., that deed and
# mortgage volume move in plausible ranges, that known disruptions (2008
# financial crisis, 2020-21 pandemic housing boom) are visible, and that
# there are no obvious gaps or spikes suggesting a cleaning bug. Not a
# formal analysis step -- just a checkpoint.

monthly_activity |>
  ggplot(aes(yr_mo)) +
  geom_line(aes(y = n_deeds, color = "Deeds (sales)")) +
  geom_line(aes(y = n_mortgages, color = "New mortgages")) +
  scale_x_date(
    breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
    date_labels = "%Y"
  ) +
  labs(
    x = NULL, y = "Documents recorded per month", color = NULL,
    title = "Philadelphia property transactions & mortgage volume, 2000-July 2026"
  )

# write_csv(monthly_activity, "monthly_activity_2000_2025.csv")

# =============================================================================
# SECTION 6 (DESCRIPTIVE): EDA -- CITYWIDE TIME SERIES
# =============================================================================
# Goal: understand the shape of the citywide series before we forecast it --
# trend, seasonality, and year-over-year change -- and flag the two
# disruption windows (2008 crash, 2020 pandemic) we'll quantify later.

# 6a. Year-over-year % change (12-month lag), the clearest "how has it
# changed" view for a non-technical audience.
monthly_activity_yoy <- monthly_activity |>
  arrange(yr_mo) |>
  mutate(
    deeds_yoy = n_deeds / lag(n_deeds, 12) - 1,
    mortgages_yoy = n_mortgages / lag(n_mortgages, 12) - 1
  )

monthly_activity_yoy |>
  filter(!is.na(deeds_yoy)) |>
  ggplot(aes(yr_mo)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50") +
  geom_line(aes(y = deeds_yoy, color = "Deeds (sales)")) +
  geom_line(aes(y = mortgages_yoy, color = "New mortgages")) +
  scale_x_date(
    breaks = seq(as.Date("2000-01-01"), as.Date("2025-01-01"), by = "5 years"),
    date_labels = "%Y"
  ) +
  scale_y_continuous(labels = scales::percent) +
  labs(
    x = NULL, y = "Year-over-year change", color = NULL,
    title = "Year-over-year change in Philadelphia property activity"
  )

# 6b. Trend/seasonal decomposition (STL) -- separates each series into
# trend, seasonal, and remainder components. The remainder/trend panels are
# where the 2008 and 2020 disruptions should show up as large deviations.
monthly_ts <- monthly_activity |>
  # tsibble needs an explicit yearmonth index (not a Date) to recognize a
  # regular monthly interval -- using Date directly causes it to see
  # irregular gaps (months have 28-31 days).
  mutate(yr_mo = yearmonth(yr_mo)) |>
  as_tsibble(index = yr_mo)

monthly_ts |>
  model(STL(n_deeds ~ season(window = "periodic"))) |>
  components() |>
  autoplot() +
  labs(title = "STL decomposition: monthly deed (sale) volume")

monthly_ts |>
  model(STL(n_mortgages ~ season(window = "periodic"))) |>
  components() |>
  autoplot() +
  labs(title = "STL decomposition: monthly new-mortgage volume")

# =============================================================================
# SECTION 7 (DESCRIPTIVE): EDA -- PRICE DISTRIBUTION
# =============================================================================
# Sale prices are always right-skewed (a few very high-value transactions),
# so a log10 x-axis is used to see the bulk of the distribution clearly.
# Nominal transfers (<= $100) are excluded here since they're not market
# transactions (already flagged during cleaning).

data_document |>
  filter(
    activity_type == "sale_deed",
    !nominal_transfer,
    !high_value_sale_outlier,
    total_consideration > 0
  ) |>
  ggplot(aes(total_consideration)) +
  geom_histogram(bins = 60) +
  scale_x_log10(labels = scales::dollar) +
  labs(
    x = "Sale price (log scale)", y = "Number of deeds",
    title = "Distribution of market-priced deeds, 2000-July 2026"
  )

# 7b. Parcel-level value and coverage summary. This uses data_clean because
# assessed value, fair-market value, and property counts describe individual
# properties rather than whole filing documents. The document count is kept
# beside the parcel count so the two units cannot be confused.
parcel_value_yearly <- data_clean |>
  filter(activity_type == "sale_deed") |>
  summarise(
    n_parcel_records = n(),
    n_documents = n_distinct(document_id, na.rm = TRUE),
    assessment_coverage_pct = mean(!is.na(assessed_value)),
    median_assessed_value = median(assessed_value, na.rm = TRUE),
    median_fair_market_value = median(fair_market_value, na.rm = TRUE),
    .by = year
  ) |>
  arrange(year)

# =============================================================================
# SECTION 8 (DESCRIPTIVE): EDA -- GEOGRAPHIC PATTERNS (WARD LEVEL)
# =============================================================================
# Uses both grains deliberately. Parcel-level data_clean measures property-row
# geographic coverage. Document-level data_document supplies additive
# transaction totals through one deterministic primary ward per document.

# 8a. Parcel-level missingness: what share of property records lacks a ward?
data_clean |>
  summarise(
    parcel_records = n(),
    pct_missing_ward = mean(is.na(ward)),
    .by = activity_type
  )

# Document-level missingness is reported separately because one document can
# contain several parcels but receives only one primary ward for additive use.
document_ward_missingness <- data_document |>
  summarise(
    documents = n(),
    pct_missing_primary_ward = mean(is.na(primary_ward)),
    .by = activity_type
  )

# 8b. Ward x year rollup
ward_year_activity <- data_document |>
  filter(!is.na(primary_ward)) |>
  summarise(
    n_deeds = sum(activity_type == "sale_deed"),
    n_mortgages = sum(activity_type == "new_mortgage"),
    median_price = median(total_consideration[
      activity_type == "sale_deed" &
        !nominal_transfer &
        !high_value_sale_outlier
    ],
      na.rm = TRUE
    ),
    .by = c(primary_ward, year)
  ) |>
  rename(ward = primary_ward) |>
  arrange(ward, year)

# Quick look: how many wards, how complete is the year coverage?
ward_year_activity |> summarise(n_wards = n_distinct(ward), n_years = n_distinct(year))

# 8c. Ward x month fact table. This is the geographic equivalent of
# monthly_activity and is the correct input grain for Tableau filters and maps.
# Primary-ward assignment keeps totals additive: summing across wards returns
# the citywide count for documents with a known ward.
fact_monthly_geo <- data_document |>
  filter(!is.na(primary_ward)) |>
  summarise(
    n_deeds = sum(activity_type == "sale_deed"),
    n_mortgages = sum(activity_type == "new_mortgage"),
    n_nominal = sum(nominal_transfer, na.rm = TRUE),
    n_arms_length = sum(
      activity_type == "sale_deed" &
        !is.na(total_consideration) &
        total_consideration > 100
    ),
    median_price_arms_length = {
      eligible <- activity_type == "sale_deed" &
        !is.na(total_consideration) &
        total_consideration > 100 &
        !high_value_sale_outlier
      if (any(eligible)) median(total_consideration[eligible]) else NA_real_
    },
    .by = c(primary_ward, yr_mo)
  ) |>
  rename(ward = primary_ward) |>
  complete(
    ward,
    yr_mo = analysis_months,
    fill = list(
      n_deeds = 0L,
      n_mortgages = 0L,
      n_nominal = 0L,
      n_arms_length = 0L
    )
  ) |>
  arrange(ward, yr_mo)

# 8d. Ward trajectory features and clustering. Early (2000-2004) and recent
# (2021-2025) five-year windows reduce sensitivity to a single unusual year.
# Log growth measures handle wards with very different starting volumes. Price
# growth, recent mortgage/deed balance, and recent nominal-transfer share add
# economically distinct dimensions to the grouping.
ward_period_features <- data_document |>
  filter(!is.na(primary_ward), year %in% c(2000:2004, 2021:2025)) |>
  mutate(
    period = case_when(
      year <= 2004 ~ "early",
      year >= 2021 ~ "recent"
    )
  ) |>
  summarise(
    n_deeds = sum(activity_type == "sale_deed"),
    n_mortgages = sum(activity_type == "new_mortgage"),
    n_nominal = sum(nominal_transfer, na.rm = TRUE),
    median_price = {
      eligible <- activity_type == "sale_deed" &
        !is.na(total_consideration) &
        total_consideration > 100 &
        !high_value_sale_outlier
      if (any(eligible)) median(total_consideration[eligible]) else NA_real_
    },
    .by = c(primary_ward, period)
  ) |>
  rename(ward = primary_ward) |>
  pivot_wider(
    names_from = period,
    values_from = c(n_deeds, n_mortgages, n_nominal, median_price),
    values_fill = list(n_deeds = 0, n_mortgages = 0, n_nominal = 0)
  )

ward_cluster_features <- ward_period_features |>
  mutate(
    avg_annual_deeds_early = n_deeds_early / 5,
    avg_annual_deeds_recent = n_deeds_recent / 5,
    deed_growth_log = log1p(avg_annual_deeds_recent) -
      log1p(avg_annual_deeds_early),
    price_growth_log = if_else(
      median_price_early > 0 & median_price_recent > 0,
      log(median_price_recent) - log(median_price_early),
      NA_real_
    ),
    mortgage_to_deed_recent = n_mortgages_recent / pmax(n_deeds_recent, 1),
    nominal_share_recent = n_nominal_recent / pmax(n_deeds_recent, 1)
  ) |>
  select(
    ward,
    avg_annual_deeds_early,
    avg_annual_deeds_recent,
    deed_growth_log,
    price_growth_log,
    mortgage_to_deed_recent,
    nominal_share_recent
  ) |>
  drop_na()

cluster_feature_names <- c(
  "deed_growth_log",
  "price_growth_log",
  "mortgage_to_deed_recent",
  "nominal_share_recent"
)

cluster_matrix <- ward_cluster_features |>
  select(all_of(cluster_feature_names)) |>
  scale()

# Average silhouette width compares how cohesive and well-separated candidate
# solutions are. We test two through six clusters and retain the highest score;
# this avoids selecting k only because one visual result looks appealing.
set.seed(710)
candidate_ks <- 2:min(6, nrow(ward_cluster_features) - 1)
cluster_validation <- map_dfr(candidate_ks, function(k_value) {
  candidate_model <- kmeans(cluster_matrix, centers = k_value, nstart = 100)
  silhouette_result <- cluster::silhouette(candidate_model$cluster, dist(cluster_matrix))
  tibble(k = k_value, average_silhouette = mean(silhouette_result[, "sil_width"]))
})

best_cluster_k <- cluster_validation$k[which.max(cluster_validation$average_silhouette)]
ward_cluster_model <- kmeans(cluster_matrix, centers = best_cluster_k, nstart = 200)

cluster_z_scores <- as_tibble(cluster_matrix) |>
  mutate(
    ward = ward_cluster_features$ward,
    cluster = ward_cluster_model$cluster
  )

cluster_profiles <- cluster_z_scores |>
  summarise(across(all_of(cluster_feature_names), mean), .by = cluster) |>
  mutate(
    profile = case_when(
      deed_growth_log > 0.35 & price_growth_log > 0.35 ~
        "activity and price growth",
      deed_growth_log < -0.35 ~ "activity decline",
      nominal_share_recent > 0.35 ~ "high nominal-transfer share",
      mortgage_to_deed_recent > 0.35 ~ "mortgage-intensive activity",
      price_growth_log > 0.35 ~ "price-led growth",
      TRUE ~ "mixed or stable"
    ),
    cluster_label = paste0("Cluster ", cluster, ": ", profile)
  )

ward_cluster_assignments <- ward_cluster_features |>
  mutate(cluster = ward_cluster_model$cluster) |>
  left_join(
    cluster_profiles |> select(cluster, cluster_label),
    by = "cluster"
  ) |>
  arrange(cluster, ward)

cluster_validation
cluster_profiles

ward_cluster_assignments |>
  ggplot(aes(
    x = deed_growth_log,
    y = price_growth_log,
    color = cluster_label,
    label = ward
  )) +
  geom_hline(yintercept = 0, color = "grey80") +
  geom_vline(xintercept = 0, color = "grey80") +
  geom_point(size = 2) +
  labs(
    x = "Change in log average annual deed volume",
    y = "Change in log median arms-length price",
    color = NULL,
    title = "Ward trajectory clusters: early period vs. recent period"
  )

# =============================================================================
# SECTION 9 (PREDICTIVE): TIME SERIES FORECASTING
# =============================================================================
# Abstract: This is the first PREDICTIVE step in the project (everything
# above was DESCRIPTIVE -- summarizing/visualizing what already happened).
# Here we fit models on pre-2020 data only, "forecast" them forward through
# 2025 as if 2020-2025 hadn't happened yet, and compare that forecast to
# what actually occurred. The gap between forecast and actual is our
# measure of how disruptive the pandemic period was, relative to a
# reasonable pre-pandemic baseline. We deliberately include two "naive"
# baseline models alongside more sophisticated ETS/ARIMA models -- a
# forecast is only useful if it beats a naive baseline, so both must be
# reported together, not just the fancier model.

# 9a. Split the tsibble into a training window (pre-disruption) and a test
# window (2020 onward) -- the model never sees the test period while fitting.
train_ts <- monthly_ts |> filter(yr_mo < yearmonth("2020-01"))
test_ts <- monthly_ts |> filter(yr_mo >= yearmonth("2020-01"))
horizon <- nrow(test_ts) # forecast exactly as far as we have actuals to compare against

# 9b. Fit four candidate models per series on the training window only:
#   NAIVE   -- "next month = this month" (simplest possible baseline)
#   SNAIVE  -- "next month = same month last year" (accounts for seasonality)
#   ETS     -- Exponential Smoothing (trend + seasonality, adaptive)
#   ARIMA   -- auto-selected AutoRegressive Integrated Moving Average model
# Fitting all four on both series (deeds, mortgages) in one call via the
# fable "formula per column" shorthand.
deed_models <- train_ts |>
  model(
    naive    = NAIVE(n_deeds),
    snaive   = SNAIVE(n_deeds),
    ets      = ETS(n_deeds),
    arima    = ARIMA(n_deeds)
  )

mortgage_models <- train_ts |>
  model(
    naive    = NAIVE(n_mortgages),
    snaive   = SNAIVE(n_mortgages),
    ets      = ETS(n_mortgages),
    arima    = ARIMA(n_mortgages)
  )

# 9b-diagnostic. Ljung-Box test on each model's residuals (fit on the
# training window). This answers a DIFFERENT question than the backtest
# accuracy in 9c below: Ljung-Box checks whether a model has left behind
# statistically significant autocorrelation in its residuals ("model
# adequacy" -- did it fully capture the patterns in the training data?),
# whereas RMSE/MAPE checks how close the model's forecasts came to actual
# 2020-2025 values ("forecast accuracy" -- a genuinely different, and for
# our purposes more important, question). A model can pass Ljung-Box (well-
# specified on the training data) and still forecast poorly through an
# unprecedented shock like 2020-2025, or vice versa. We still run it
# because a model failing Ljung-Box means its residuals aren't white noise,
# which also means its *prediction intervals* (used in Section 10's forward
# forecast) are likely too narrow -- useful context alongside the accuracy
# ranking, not a replacement for it.
# lag = 24 (two years of monthly autocorrelation checked); dof = 0 is a
# simplification (ideally subtracted per estimated ARIMA/ETS parameter, but
# treated the same across models here for a like-for-like comparison).
deed_ljung_box <- deed_models |>
  augment() |>
  features(.innov, ljung_box, lag = 24, dof = 0) |>
  arrange(.model)

mortgage_ljung_box <- mortgage_models |>
  augment() |>
  features(.innov, ljung_box, lag = 24, dof = 0) |>
  arrange(.model)

deed_ljung_box
mortgage_ljung_box

# 9c. Forecast forward through the test window, then score every model
# against the actual 2020-2025 values using standard forecast-accuracy
# metrics (RMSE = typical error size in the original units; MAPE = typical
# error as a %, easier to compare across deeds vs. mortgages).
deed_forecasts <- deed_models |> forecast(h = horizon)
mortgage_forecasts <- mortgage_models |> forecast(h = horizon)

deed_accuracy <- deed_forecasts |>
  accuracy(test_ts) |>
  arrange(RMSE)
mortgage_accuracy <- mortgage_forecasts |>
  accuracy(test_ts) |>
  arrange(RMSE)

deed_accuracy
mortgage_accuracy

# Combine both diagnostics side by side for the model we end up using --
# lets us report, e.g., "ARIMA won the backtest (lowest RMSE) AND passed
# Ljung-Box (residuals are white noise, so its intervals are trustworthy)."
deed_accuracy |>
  left_join(deed_ljung_box, by = ".model") |>
  select(.model, RMSE, MAPE, lb_stat, lb_pvalue)

mortgage_accuracy |>
  left_join(mortgage_ljung_box, by = ".model") |>
  select(.model, RMSE, MAPE, lb_stat, lb_pvalue)

# 9d. Visualize: actual vs. forecast, so the size of the pandemic-era
# deviation is visible directly (not just as a table of error metrics).
deed_forecasts |>
  autoplot(bind_rows(train_ts, test_ts), level = NULL) +
  labs(
    title = "Deed (sale) volume: forecast vs. actual, 2020-2025",
    subtitle = "Models trained on pre-2020 data only",
    y = "Deeds per month", x = NULL
  )

mortgage_forecasts |>
  autoplot(bind_rows(train_ts, test_ts), level = NULL) +
  labs(
    title = "New-mortgage volume: forecast vs. actual, 2020-2025",
    subtitle = "Models trained on pre-2020 data only",
    y = "Mortgages per month", x = NULL
  )

# 9e. Quantify the deviation directly: for the best-performing model
# (lowest RMSE) on each series, compute actual-minus-forecast by month.
# This is the number we'll cite in recommendations (e.g. "deed volume ran
# X% below the pre-pandemic-implied trend for Y months").
best_deed_model <- deed_accuracy$.model[1]
best_mortgage_model <- mortgage_accuracy$.model[1]

deed_deviation <- deed_forecasts |>
  filter(.model == best_deed_model) |>
  as_tibble() |>
  select(yr_mo, forecast_deeds = .mean) |>
  left_join(as_tibble(test_ts) |> select(yr_mo, n_deeds), by = "yr_mo") |>
  mutate(deviation_pct = n_deeds / forecast_deeds - 1)

mortgage_deviation <- mortgage_forecasts |>
  filter(.model == best_mortgage_model) |>
  as_tibble() |>
  select(yr_mo, forecast_mortgages = .mean) |>
  left_join(as_tibble(test_ts) |> select(yr_mo, n_mortgages), by = "yr_mo") |>
  mutate(deviation_pct = n_mortgages / forecast_mortgages - 1)

deed_deviation |> summarise(avg_deviation_pct = mean(deviation_pct, na.rm = TRUE))
mortgage_deviation |> summarise(avg_deviation_pct = mean(deviation_pct, na.rm = TRUE))

# 9f. Financial-crisis backtest. The primary backtest above measures the
# pandemic/high-rate disruption. This second holdout repeats the same logic for
# 2008-2012, allowing the final report to compare two shocks using consistent
# model families and error metrics rather than relying only on a visual story.
crisis_train_ts <- monthly_ts |> filter(yr_mo < yearmonth("2008-01"))
crisis_test_ts <- monthly_ts |>
  filter(yr_mo >= yearmonth("2008-01"), yr_mo <= yearmonth("2012-12"))
crisis_horizon <- nrow(crisis_test_ts)

crisis_deed_models <- crisis_train_ts |>
  model(
    naive = NAIVE(n_deeds),
    snaive = SNAIVE(n_deeds),
    ets = ETS(n_deeds),
    arima = ARIMA(n_deeds)
  )

crisis_mortgage_models <- crisis_train_ts |>
  model(
    naive = NAIVE(n_mortgages),
    snaive = SNAIVE(n_mortgages),
    ets = ETS(n_mortgages),
    arima = ARIMA(n_mortgages)
  )

crisis_deed_forecasts <- crisis_deed_models |> forecast(h = crisis_horizon)
crisis_mortgage_forecasts <- crisis_mortgage_models |> forecast(h = crisis_horizon)

crisis_deed_accuracy <- crisis_deed_forecasts |>
  accuracy(crisis_test_ts) |>
  arrange(RMSE)
crisis_mortgage_accuracy <- crisis_mortgage_forecasts |>
  accuracy(crisis_test_ts) |>
  arrange(RMSE)

crisis_best_deed_model <- crisis_deed_accuracy$.model[1]
crisis_best_mortgage_model <- crisis_mortgage_accuracy$.model[1]

crisis_deed_deviation <- crisis_deed_forecasts |>
  filter(.model == crisis_best_deed_model) |>
  as_tibble() |>
  select(yr_mo, forecast_deeds = .mean) |>
  left_join(
    as_tibble(crisis_test_ts) |> select(yr_mo, n_deeds),
    by = "yr_mo"
  ) |>
  mutate(deviation_pct = n_deeds / forecast_deeds - 1)

crisis_mortgage_deviation <- crisis_mortgage_forecasts |>
  filter(.model == crisis_best_mortgage_model) |>
  as_tibble() |>
  select(yr_mo, forecast_mortgages = .mean) |>
  left_join(
    as_tibble(crisis_test_ts) |> select(yr_mo, n_mortgages),
    by = "yr_mo"
  ) |>
  mutate(deviation_pct = n_mortgages / forecast_mortgages - 1)

# 9g. Recent-regime stress test. A model trained only on 2015-2019 is carried
# forward through 2025, then scored specifically on 2023-2025. Poor performance
# here supports a cautious "regime changed" interpretation after mortgage rates
# rose, while good performance would favor a temporary-shock interpretation.
recent_regime_train <- monthly_ts |>
  filter(yr_mo >= yearmonth("2015-01"), yr_mo < yearmonth("2020-01"))
recent_regime_actual <- monthly_ts |>
  filter(yr_mo >= yearmonth("2023-01"), yr_mo <= yearmonth("2025-12"))
recent_regime_horizon <- 72

recent_regime_deed_models <- recent_regime_train |>
  model(
    naive = NAIVE(n_deeds),
    snaive = SNAIVE(n_deeds),
    ets = ETS(n_deeds),
    arima = ARIMA(n_deeds)
  )
recent_regime_mortgage_models <- recent_regime_train |>
  model(
    naive = NAIVE(n_mortgages),
    snaive = SNAIVE(n_mortgages),
    ets = ETS(n_mortgages),
    arima = ARIMA(n_mortgages)
  )

recent_regime_deed_accuracy <- recent_regime_deed_models |>
  forecast(h = recent_regime_horizon) |>
  filter(yr_mo >= yearmonth("2023-01")) |>
  accuracy(recent_regime_actual) |>
  arrange(RMSE)

recent_regime_mortgage_accuracy <- recent_regime_mortgage_models |>
  forecast(h = recent_regime_horizon) |>
  filter(yr_mo >= yearmonth("2023-01")) |>
  accuracy(recent_regime_actual) |>
  arrange(RMSE)

crisis_deed_accuracy
crisis_mortgage_accuracy
recent_regime_deed_accuracy
recent_regime_mortgage_accuracy

# =============================================================================
# SECTION 10 (PREDICTIVE): FORWARD FORECAST, AUGUST 2026-2028
# =============================================================================
# Abstract: Section 9 was a BACKTEST -- it validated model performance
# against a period whose outcome we already knew (2020-2025), which is why
# it could quantify the pandemic-era disruption but couldn't tell us
# anything about the genuine future. This section is the actual forecast:
# we refit each series' best-performing model type (chosen by Section 9's
# accuracy comparison, e.g. ARIMA for deeds) on the full history through July
# 2026 with no holdout, then project forward from August 2026 through 2028.
# Fable's model-based 80% and 95% prediction intervals
# show statistical uncertainty under the fitted model. Section 9's backtest
# errors are reported alongside them as an empirical warning about how much
# wider real-world errors can become during a structural shock.

forecast_end_month <- as_date("2028-12-01")
forecast_horizon_months <- length(seq.Date(
  analysis_end_month %m+% months(1),
  forecast_end_month,
  by = "month"
))

# Refit on ALL available data (train + test from Section 9combined back
# into the full series) using only the winning model type per series.
final_deed_model <- monthly_ts |>
  model(
    naive  = NAIVE(n_deeds),
    snaive = SNAIVE(n_deeds),
    ets    = ETS(n_deeds),
    arima  = ARIMA(n_deeds)
  ) |>
  select(all_of(best_deed_model))

final_mortgage_model <- monthly_ts |>
  model(
    naive  = NAIVE(n_mortgages),
    snaive = SNAIVE(n_mortgages),
    ets    = ETS(n_mortgages),
    arima  = ARIMA(n_mortgages)
  ) |>
  select(all_of(best_mortgage_model))

deed_forward_forecast <- final_deed_model |> forecast(h = forecast_horizon_months)
mortgage_forward_forecast <- final_mortgage_model |> forecast(h = forecast_horizon_months)

# Visualize the genuine forward forecast, with its prediction interval, on
# top of the full observed history -- this is the chart that answers "what
# does the model expect next," as opposed to Section 9's "how wrong was the
# model about a period we already know."
deed_forward_forecast |>
  autoplot(monthly_ts) +
  labs(
    title = "Deed (sale) volume: forward forecast, August 2026-2028",
    subtitle = paste("Model:", best_deed_model, "-- refit through July 2026"),
    y = "Deeds per month", x = NULL
  )

mortgage_forward_forecast |>
  autoplot(monthly_ts) +
  labs(
    title = "New-mortgage volume: forward forecast, August 2026-2028",
    subtitle = paste("Model:", best_mortgage_model, "-- refit through July 2026"),
    y = "Mortgages per month", x = NULL
  )

# Tidy tables of the forward forecast (point forecast + 80%/95% intervals)
# -- these are what would feed a revenue-planning conversation with the City.
deed_forward_table <- deed_forward_forecast |>
  hilo(level = c(80, 95)) |>
  as_tibble() |>
  select(yr_mo, .mean, `80%`, `95%`)

mortgage_forward_table <- mortgage_forward_forecast |>
  hilo(level = c(80, 95)) |>
  as_tibble() |>
  select(yr_mo, .mean, `80%`, `95%`)

deed_forward_table
mortgage_forward_table

# =============================================================================
# SECTION 10B (PREDICTIVE): ECONOMIC INDICATORS, LAGS, AND REGRESSION
# =============================================================================
# Purpose:
#   Directly address the "broader economic trends" portion of the research
#   question. The external ETL supplies monthly mortgage rates, the NBER
#   recession indicator, and quarterly Philadelphia FHFA HPI aligned to months.
#
# Interpretation boundary:
#   These time-series regressions measure conditional association, not causal
#   impact. A three-month rate lag is included because financing decisions and
#   deed recording occur after rate exposure. An autoregressive outcome term,
#   calendar-month controls, and a linear time trend absorb persistence,
#   seasonality, and broad long-run growth that would otherwise confound the
#   rate/HPI coefficients.

econ_indicator_path <- file.path("external_data", "dim_econ_indicators.csv")
peer_hpi_path <- file.path("external_data", "fact_quarterly_peer_hpi.csv")

if (!file.exists(econ_indicator_path)) {
  message("Economic indicator file not found; running 02_build_economic_context.R.")
  source(file.path(code_dir, "02_build_economic_context.R"))
}

dim_econ_indicators <- read_csv(econ_indicator_path, show_col_types = FALSE) |>
  mutate(yr_mo = as_date(yr_mo))

monthly_model_data <- monthly_activity |>
  left_join(dim_econ_indicators, by = "yr_mo") |>
  arrange(yr_mo) |>
  mutate(
    time_index = row_number(),
    calendar_month = factor(month(yr_mo)),
    log_deeds = log1p(n_deeds),
    log_mortgages = log1p(n_mortgages),
    lag_log_deeds = lag(log_deeds),
    lag_log_mortgages = lag(log_mortgages),
    mortgage_rate_lag3 = lag(mortgage_rate_30y, 3)
  )

deed_regression_data <- monthly_model_data |>
  drop_na(
    log_deeds,
    lag_log_deeds,
    mortgage_rate_lag3,
    philly_hpi_yoy,
    recession_flag
  )

mortgage_regression_data <- monthly_model_data |>
  drop_na(
    log_mortgages,
    lag_log_mortgages,
    mortgage_rate_lag3,
    philly_hpi_yoy,
    recession_flag
  )

deed_econ_model <- lm(
  log_deeds ~ lag_log_deeds + mortgage_rate_lag3 + philly_hpi_yoy +
    recession_flag + time_index + calendar_month,
  data = deed_regression_data
)

mortgage_econ_model <- lm(
  log_mortgages ~ lag_log_mortgages + mortgage_rate_lag3 + philly_hpi_yoy +
    recession_flag + time_index + calendar_month,
  data = mortgage_regression_data
)

tidy_lm_coefficients <- function(model, outcome_name) {
  as.data.frame(summary(model)$coefficients) |>
    rownames_to_column("term") |>
    as_tibble() |>
    rename(
      estimate = Estimate,
      std_error = `Std. Error`,
      statistic = `t value`,
      p_value = `Pr(>|t|)`
    ) |>
    mutate(outcome = outcome_name, .before = 1)
}

regression_coefficients <- bind_rows(
  tidy_lm_coefficients(deed_econ_model, "Monthly deeds"),
  tidy_lm_coefficients(mortgage_econ_model, "Monthly mortgages")
)

regression_diagnostics <- bind_rows(
  tibble(
    outcome = "Monthly deeds",
    observations = nobs(deed_econ_model),
    adjusted_r_squared = summary(deed_econ_model)$adj.r.squared,
    residual_ljung_box_p = Box.test(
      residuals(deed_econ_model),
      lag = 12,
      type = "Ljung-Box",
      fitdf = 0
    )$p.value
  ),
  tibble(
    outcome = "Monthly mortgages",
    observations = nobs(mortgage_econ_model),
    adjusted_r_squared = summary(mortgage_econ_model)$adj.r.squared,
    residual_ljung_box_p = Box.test(
      residuals(mortgage_econ_model),
      lag = 12,
      type = "Ljung-Box",
      fitdf = 0
    )$p.value
  )
)

# Positive lag_months means the economic indicator is moved earlier and is
# being evaluated as a possible leading signal for later transaction activity.
lagged_correlation <- function(indicator, activity, lag_months) {
  n_values <- length(indicator)
  if (lag_months >= 0) {
    indicator_part <- indicator[seq_len(n_values - lag_months)]
    activity_part <- activity[(lag_months + 1):n_values]
  } else {
    lead_months <- abs(lag_months)
    indicator_part <- indicator[(lead_months + 1):n_values]
    activity_part <- activity[seq_len(n_values - lead_months)]
  }
  cor(indicator_part, activity_part, use = "complete.obs")
}

economic_lag_correlations <- crossing(
  comparison = c("Mortgage rate vs mortgages", "HPI YoY vs deeds"),
  lag_months = -12:12
) |>
  mutate(
    correlation = map2_dbl(comparison, lag_months, function(comparison_name, lag_value) {
      if (comparison_name == "Mortgage rate vs mortgages") {
        lagged_correlation(
          monthly_model_data$mortgage_rate_30y,
          monthly_model_data$n_mortgages,
          lag_value
        )
      } else {
        lagged_correlation(
          monthly_model_data$philly_hpi_yoy,
          monthly_model_data$n_deeds,
          lag_value
        )
      }
    })
  )

regression_coefficients |>
  filter(term %in% c("mortgage_rate_lag3", "philly_hpi_yoy", "recession_flag"))
regression_diagnostics

economic_lag_correlations |>
  ggplot(aes(lag_months, correlation, color = comparison)) +
  geom_hline(yintercept = 0, color = "grey70") +
  geom_line() +
  geom_point() +
  labs(
    x = "Indicator lead in months (positive = indicator leads activity)",
    y = "Correlation",
    color = NULL,
    title = "Lag scan: economic indicators and Philadelphia activity"
  )

# Peer HPI comparison uses the consistent quarterly FHFA methodology prepared
# in econ_peer_etl.R. This complements, rather than substitutes for, Zillow's
# optional monthly sales-count comparison.
if (file.exists(peer_hpi_path)) {
  fact_quarterly_peer_hpi <- read_csv(peer_hpi_path, show_col_types = FALSE) |>
    mutate(quarter = as_date(quarter))

  fact_quarterly_peer_hpi |>
    ggplot(aes(quarter, hpi_index_2000, color = city)) +
    geom_line() +
    labs(
      x = NULL,
      y = "FHFA HPI (2000 Q1 = 100)",
      color = NULL,
      title = "Philadelphia home-price appreciation vs. legacy-city peers"
    )
}

# =============================================================================
# SECTION 11 (PRESCRIPTIVE): DATA PREP FOR EXCEL SOLVER
# =============================================================================
# Abstract: This is the first PRESCRIPTIVE step (everything above described
# or predicted; this section recommends an ACTION). The question we're
# formulating for the optimization:
#
#   "Given a limited number of assessment/audit-hours per year, how should
#   the City allocate audits across wards to maximize the potential transfer
#   tax value reviewed from nominal (<=$100 reported) property transfers
#   -- while guaranteeing every affected ward gets at least minimal
#   coverage?"
#
# Why this framing: it uses only data we already have cleanly (nominal
# transfer counts and arms-length prices by ward), sidestepping the
# assessed_value field's ~46% missingness gap flagged earlier. It's also a
# genuine linear program -- not a "just sort and pick the top ward" problem
# -- because of the equity-floor constraint below, which forces Solver to
# trade off pure efficiency against covering every ward.
#
# Decision variables: audits_w = number of audits allocated to ward w
# Objective: maximize sum(value_per_audit_w * audits_w)
# Constraints:
#   audits_w <= n_nominal_per_year_w   (can't audit more cases than exist)
#   audits_w >= min_coverage            (equity floor: every active ward
#                                         gets at least this many audits/yr)
#   sum(audits_w) <= total_audit_capacity  (total staffing budget)

# Assumptions -- flagged explicitly since they're not directly in the data
# and should be replaced with real City figures if/when available:
transfer_tax_rate <- 0.04578 # City 3.578% + Commonwealth 1%, effective 7/1/2025
recent_window_years <- 2021:2025 # "current risk" window -- recent years are
# more policy-relevant than a 26-year
# average for staffing next year's audits
assumed_total_audit_capacity <- 1000 # aligned to the current Excel Solver case
assumed_min_coverage <- 1 # equity floor: every active ward gets >= 1 audit
# No observed audit success rate is available. A value of 1 makes the objective
# a potential tax value reviewed, not a guaranteed revenue forecast. Replace it
# with a validated historical recovery probability before policy use.
assumed_recovery_probability <- 1

# Ward-level coefficients: for each ward, how many nominal-transfer "audit
# opportunities" exist per year recently, and what's the potential tax
# value per audit (using the ward's own typical arms-length price as the
# proxy for the property value at stake, since a nominal transfer's true
# value is exactly what an audit would be trying to establish).
ward_solver_input <- data_document |>
  filter(
    activity_type == "sale_deed",
    year %in% recent_window_years,
    !is.na(primary_ward)
  ) |>
  summarise(
    n_nominal = sum(nominal_transfer),
    median_price_arms_length = median(
      total_consideration[
        !nominal_transfer & !high_value_sale_outlier
      ],
      na.rm = TRUE
    ),
    .by = primary_ward
  ) |>
  rename(ward = primary_ward) |>
  mutate(
    n_nominal_per_year = n_nominal / length(recent_window_years),
    # An audit is indivisible, so the annual opportunity ceiling must be an
    # integer even though the five-year average itself can be fractional.
    max_audits_per_year = floor(n_nominal_per_year),
    value_per_audit = median_price_arms_length * transfer_tax_rate *
      assumed_recovery_probability
  ) |>
  filter(max_audits_per_year >= assumed_min_coverage, !is.na(value_per_audit)) |>
  arrange(desc(value_per_audit))

ward_solver_input

# This is the file that actually goes to Excel -- kept UNcommented (unlike
# other write_csv lines) since it's a required handoff artifact, not just an
# optional final export.
write_csv(
  ward_solver_input,
  file.path("model_inputs", "ward_solver_input.csv")
)

# =============================================================================
# SECTION 12 (PRESCRIPTIVE): R-SIDE LP "ANSWER KEY" (via lpSolve)
# =============================================================================
# Abstract: This solves the EXACT SAME linear program in R using lpSolve --
# not as a replacement for doing it in Excel Solver (the professor
# specifically wants that deliverable), but as an answer key: once Solver is
# set up in Excel, its optimal objective value and allocation should match
# this one. If they don't match, something in the Excel constraint setup is
# off. This also lets us preview the recommendation and build the
# downstream chart/table before anyone touches Excel.

n_wards <- nrow(ward_solver_input)

lp_solution <- lp(
  direction = "max",
  objective.in = ward_solver_input$value_per_audit,
  # Row block 1: audits_w <= n_nominal_per_year_w (per-ward ceiling)
  # Row block 2: audits_w >= assumed_min_coverage   (equity floor)
  # Row 2n+1:    sum(audits_w) <= assumed_total_audit_capacity (budget)
  const.mat = rbind(
    diag(n_wards),
    diag(n_wards),
    rep(1, n_wards)
  ),
  const.dir = c(rep("<=", n_wards), rep(">=", n_wards), "<="),
  const.rhs = c(
    ward_solver_input$max_audits_per_year,
    rep(assumed_min_coverage, n_wards),
    assumed_total_audit_capacity
  ),
  all.int = TRUE
)

stopifnot(lp_solution$status == 0)

ward_solver_answer_key <- ward_solver_input |>
  mutate(
    recommended_audits = lp_solution$solution,
    expected_recovered_revenue = recommended_audits * value_per_audit
  ) |>
  arrange(desc(expected_recovered_revenue))

ward_solver_answer_key
cat(
  "R-solved objective ($ potential tax value reviewed/year):",
  scales::dollar(lp_solution$objval), "\n"
)

# =============================================================================
# SECTION 13 (PRESCRIPTIVE): IMPORT REAL EXCEL SOLVER RESULTS
# =============================================================================
# Abstract: After completing the Solver setup in Excel (see instructions
# below) and solving it there, export Excel's solution as a CSV with columns
# `ward` and `recommended_audits`, save it in model_inputs as
# "ward_solver_output_excel.csv"
# in this project folder, and re-run this section. It joins the Excel
# solution back onto our ward coefficients and compares it against the
# lpSolve answer key above -- if the City's finance team (or your grader)
# asks "how do we know Excel got the right answer," this comparison is the
# evidence.
#
# EXCEL SOLVER SETUP (Data tab > Solver, in Excel):
#   1. Import model_inputs/ward_solver_input.csv into a worksheet.
#   2. Add a new column, e.g. column D, "audits_allocated" -- this is your
#      changing/decision variable cell range. Start all values at 0.
#   3. Add an objective cell, e.g. =SUMPRODUCT(value_per_audit_range,
#      audits_allocated_range).
#   4. Solver Parameters:
#      - Set Objective: the objective cell above; To: Max
#      - By Changing Variable Cells: the audits_allocated range
#      - Add Constraint: audits_allocated range <= max_audits_per_year range
#      - Add Constraint: audits_allocated range >= 1 (equity floor)
#      - Add Constraint: SUM(audits_allocated range) <= 1000 (or your real
#        capacity number)
#      - Add Constraint: audits_allocated range = integer
#      - Solving Method: Simplex LP (this is a linear program)
#   5. Click Solve, keep the solution, then export ward + audits_allocated
#      as model_inputs/ward_solver_output_excel.csv.

excel_results_csv_path <- file.path(
  "model_inputs",
  "ward_solver_output_excel.csv"
)
excel_solver_workbook_path <- file.path(
  "model_inputs",
  "ward_solver_input.xlsx"
)

if (file.exists(excel_results_csv_path)) {
  ward_solver_excel <- read_csv(excel_results_csv_path, show_col_types = FALSE)
} else if (
  file.exists(excel_solver_workbook_path) &&
    requireNamespace("readxl", quietly = TRUE)
) {
  # The current workbook retains Solver's decision values in audit_allocation.
  # Reading that column removes the need for a manual CSV export while keeping
  # the preferred CSV handoff compatible with the instructions above.
  ward_solver_excel <- readxl::read_excel(
    excel_solver_workbook_path,
    sheet = "ward_solver_input"
  ) |>
    filter(!is.na(ward)) |>
    transmute(
      ward = as.numeric(ward),
      recommended_audits = as.numeric(audit_allocation)
    )
} else {
  ward_solver_excel <- NULL
}

if (!is.null(ward_solver_excel)) {

  ward_solver_comparison <- ward_solver_input |>
    left_join(ward_solver_excel, by = "ward") |>
    left_join(
      ward_solver_answer_key |> select(ward, r_solution = recommended_audits),
      by = "ward"
    ) |>
    mutate(expected_recovered_revenue = recommended_audits * value_per_audit)

  ward_solver_comparison

  excel_solution_summary <- ward_solver_comparison |>
    summarise(
      allocated_audits = sum(recommended_audits, na.rm = TRUE),
      objective_value = sum(expected_recovered_revenue, na.rm = TRUE),
      missing_allocations = sum(is.na(recommended_audits)),
      below_minimum = sum(recommended_audits < assumed_min_coverage, na.rm = TRUE),
      above_ward_cap = sum(
        recommended_audits > max_audits_per_year,
        na.rm = TRUE
      ),
      noninteger_allocations = sum(
        abs(recommended_audits - round(recommended_audits)) > 1e-8,
        na.rm = TRUE
      )
    )

  excel_solver_valid <- with(
    excel_solution_summary,
    missing_allocations == 0 &&
      below_minimum == 0 &&
      above_ward_cap == 0 &&
      noninteger_allocations == 0 &&
      allocated_audits <= assumed_total_audit_capacity
  )

  cat(
    "Excel-solved objective ($ potential tax value reviewed/year):",
    scales::dollar(excel_solution_summary$objective_value), "\n"
  )

  if (!excel_solver_valid) {
    warning(
      "The retained Excel allocation is not feasible for the active R case. ",
      "Allocated audits = ", excel_solution_summary$allocated_audits,
      "; active capacity = ", assumed_total_audit_capacity,
      "; below-minimum wards = ", excel_solution_summary$below_minimum,
      "; above-cap wards = ", excel_solution_summary$above_ward_cap,
      ". R's valid answer key will be used for deliverable exports until ",
      "Excel Solver is rerun and saved for the active capacity."
    )
  }

  # Recommendation chart for the slide deck: allocated audits by ward
  ward_solver_comparison |>
    filter(recommended_audits > 0) |>
    ggplot(aes(x = recommended_audits, y = reorder(factor(ward), recommended_audits))) +
    geom_col() +
    labs(
      x = "Recommended audits/year", y = "Ward",
      title = "Optimized assessment-audit allocation by ward"
    )
} else {
  message(
    "No readable Excel Solver result found. Export columns `ward` and ",
    "`recommended_audits` to '", excel_results_csv_path, "', or install the ",
    "readxl package so this section can read '", excel_solver_workbook_path,
    "' directly."
  )
}

# =============================================================================
# SECTION 14 (DELIVERABLE): TABLEAU-READY EXPORTS AND MODEL TABLES
# =============================================================================
# Purpose:
#   Convert the analysis objects into small, documented, joinable CSV files.
#   Each file has one declared grain and stable keys; Tableau should relate the
#   files on those keys rather than joining everything into one duplicated
#   wide table. This section is intentionally last so it exports only results
#   that have passed the checks and models above.
#   The document-level fact is included for flexible Tableau exploration. The
#   parcel-level source remains in team_data/data_clean.csv.gz and should be
#   connected separately only for property maps or parcel-specific questions.

# Unpack fable's interval objects into ordinary numeric columns. Numeric lower
# and upper bounds are substantially easier to use in Tableau than formatted
# interval strings.
deed_forward_export <- deed_forward_forecast |>
  hilo(level = c(80, 95)) |>
  unpack_hilo(c(`80%`, `95%`), names_sep = "_") |>
  as_tibble() |>
  transmute(
    yr_mo = as_date(yr_mo),
    deed_forecast = .mean,
    # Counts cannot be negative. The statistical model may generate a negative
    # lower interval in distant months, so clamp only the exported lower bound.
    deed_lower_80 = pmax(0, `80%_lower`),
    deed_upper_80 = `80%_upper`,
    deed_lower_95 = pmax(0, `95%_lower`),
    deed_upper_95 = `95%_upper`
  )

mortgage_forward_export <- mortgage_forward_forecast |>
  hilo(level = c(80, 95)) |>
  unpack_hilo(c(`80%`, `95%`), names_sep = "_") |>
  as_tibble() |>
  transmute(
    yr_mo = as_date(yr_mo),
    mortgage_forecast = .mean,
    mortgage_lower_80 = pmax(0, `80%_lower`),
    mortgage_upper_80 = `80%_upper`,
    mortgage_lower_95 = pmax(0, `95%_lower`),
    mortgage_upper_95 = `95%_upper`
  )

pandemic_deed_export <- deed_deviation |>
  mutate(yr_mo = as_date(yr_mo)) |>
  rename(deed_deviation_pct = deviation_pct)
pandemic_mortgage_export <- mortgage_deviation |>
  mutate(yr_mo = as_date(yr_mo)) |>
  rename(mortgage_deviation_pct = deviation_pct)

fact_monthly_citywide <- monthly_activity_yoy |>
  left_join(pandemic_deed_export, by = c("yr_mo", "n_deeds")) |>
  left_join(pandemic_mortgage_export, by = c("yr_mo", "n_mortgages")) |>
  full_join(deed_forward_export, by = "yr_mo") |>
  full_join(mortgage_forward_export, by = "yr_mo") |>
  arrange(yr_mo)

fact_monthly_geo_export <- fact_monthly_geo |>
  left_join(
    ward_cluster_assignments |>
      select(ward, cluster, cluster_label),
    by = "ward"
  ) |>
  rename(geo_id = ward)

dim_geo <- ward_cluster_assignments |>
  transmute(
    geo_id = ward,
    geo_type = "Philadelphia ward",
    geo_label = paste("Ward", ward),
    cluster,
    cluster_label,
    avg_annual_deeds_early,
    avg_annual_deeds_recent,
    deed_growth_log,
    price_growth_log,
    mortgage_to_deed_recent,
    nominal_share_recent
  )

optimization_results <- if (
  exists("ward_solver_comparison") &&
    exists("excel_solver_valid") &&
    isTRUE(excel_solver_valid)
) {
  ward_solver_comparison |>
    transmute(
      geo_id = ward,
      allocated_resource = recommended_audits,
      objective_contribution = expected_recovered_revenue,
      r_answer_key = r_solution
    )
} else {
  ward_solver_answer_key |>
    transmute(
      geo_id = ward,
      allocated_resource = recommended_audits,
      objective_contribution = expected_recovered_revenue,
      r_answer_key = recommended_audits
    )
}

# Key uniqueness checks catch accidental many-to-many Tableau relationships
# before the files leave R.
stopifnot(
  !anyDuplicated(data_document$document_id),
  !anyDuplicated(fact_monthly_citywide$yr_mo),
  !anyDuplicated(dim_geo$geo_id),
  !anyDuplicated(optimization_results$geo_id),
  !anyDuplicated(fact_monthly_geo_export[c("yr_mo", "geo_id")])
)

file.copy(
  document_data_path,
  file.path("tableau_data", "fact_documents.csv.gz"),
  overwrite = TRUE
)

write_csv(
  fact_monthly_citywide,
  file.path("tableau_data", "fact_monthly_citywide.csv")
)
write_csv(
  fact_monthly_geo_export,
  file.path("tableau_data", "fact_monthly_geo.csv")
)
write_csv(dim_geo, file.path("tableau_data", "dim_geo.csv"))
write_csv(
  dim_econ_indicators,
  file.path("tableau_data", "dim_econ_indicators.csv")
)
write_csv(
  optimization_results,
  file.path("tableau_data", "optimization_results.csv")
)

if (exists("fact_quarterly_peer_hpi")) {
  write_csv(
    fact_quarterly_peer_hpi,
    file.path("tableau_data", "fact_quarterly_peer_hpi.csv")
  )
}

monthly_peer_path <- file.path("external_data", "fact_monthly_peer_cities.csv")
if (file.exists(monthly_peer_path)) {
  file.copy(
    monthly_peer_path,
    file.path("tableau_data", "fact_monthly_peer_cities.csv"),
    overwrite = TRUE
  )
}

# Keep data provenance next to the Tableau extracts so citations and refresh
# logic do not get separated from the fields used in the dashboard.
source_catalog_path <- file.path("external_data", "source_catalog.csv")
if (file.exists(source_catalog_path)) {
  file.copy(
    source_catalog_path,
    file.path("tableau_data", "source_catalog.csv"),
    overwrite = TRUE
  )
}

write_csv(
  regression_coefficients,
  file.path("tableau_data", "model_regression_coefficients.csv")
)
write_csv(
  regression_diagnostics,
  file.path("tableau_data", "model_regression_diagnostics.csv")
)
write_csv(
  cluster_validation,
  file.path("tableau_data", "model_cluster_validation.csv")
)

forecast_accuracy_all <- bind_rows(
  deed_accuracy |> mutate(outcome = "deeds", holdout = "2020-2025"),
  mortgage_accuracy |> mutate(outcome = "mortgages", holdout = "2020-2025"),
  crisis_deed_accuracy |> mutate(outcome = "deeds", holdout = "2008-2012"),
  crisis_mortgage_accuracy |>
    mutate(outcome = "mortgages", holdout = "2008-2012"),
  recent_regime_deed_accuracy |>
    mutate(outcome = "deeds", holdout = "2023-2025, trained 2015-2019"),
  recent_regime_mortgage_accuracy |>
    mutate(outcome = "mortgages", holdout = "2023-2025, trained 2015-2019")
)

write_csv(
  forecast_accuracy_all,
  file.path("tableau_data", "model_forecast_accuracy.csv")
)

tableau_export_manifest <- tribble(
  ~file, ~grain, ~key, ~purpose,
  "fact_documents.csv.gz", "document", "document_id",
  "Flexible transaction, tax, and document-level Tableau analysis",
  "fact_monthly_citywide.csv", "month", "yr_mo",
  "Actual activity, YoY change, shock deviation, and forward forecasts",
  "fact_monthly_geo.csv", "month x ward", "yr_mo + geo_id",
  "Ward activity and cluster labels",
  "dim_geo.csv", "ward", "geo_id",
  "Ward labels, clusters, and trajectory features",
  "dim_econ_indicators.csv", "month", "yr_mo",
  "Mortgage rate, Philadelphia FHFA HPI, and recession flag",
  "fact_quarterly_peer_hpi.csv", "quarter x city", "quarter + city",
  "Consistent FHFA price appreciation benchmark",
  "fact_monthly_peer_cities.csv", "month x city x metric",
  "yr_mo + city + metric", "Optional Zillow ZHVI and sales-count benchmark",
  "optimization_results.csv", "ward", "geo_id",
  "Recommended audit allocation and modeled objective contribution",
  "model_regression_coefficients.csv", "outcome x coefficient", "outcome + term",
  "Economic-association estimates, uncertainty, and p-values",
  "model_regression_diagnostics.csv", "outcome", "outcome",
  "Regression fit and residual-autocorrelation checks",
  "model_cluster_validation.csv", "candidate cluster count", "k",
  "Silhouette scores used to select the ward-cluster count",
  "model_forecast_accuracy.csv", "holdout x outcome x model",
  "holdout + outcome + .model", "Comparable forecast error by validation window",
  "source_catalog.csv", "source field", "output_field",
  "Source URLs, frequencies, and transformations for external fields"
)

write_csv(
  tableau_export_manifest,
  file.path("tableau_data", "README_export_manifest.csv")
)

message("Tableau-ready files written to: tableau_data/")
