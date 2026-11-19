# =============================================================================
# 19. VALIDATE THE FINAL DASHBOARD PACKAGE
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Fails the run if the ingestion folder has missing or unexpected files, if
#   a geography key is not unique, or if any fact carries an orphan key. Writes
#   the audit table the dashboard relies on.
# INPUTS
#   the five files in tableau_data/tableau_ingestion/
# OUTPUTS
#   tableau_data/week06_final_package_audit.csv
# RUNS AFTER   15 through 18
# NOTES        This is the last stage; it is the gate before publication.
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

# =============================================================================
# WEEK 06: FINAL PACKAGE GATE
# =============================================================================
# Stages 15-18 run before this file (see run_all.R). This script then enforces a
# compact ingestion folder, unique table grains, and valid geography foreign
# keys before the package is handed to Tableau.

library(tidyverse)

ingestion_dir <- file.path("tableau_data", "tableau_ingestion")
required_files <- c(
  "dim_geography.csv",
  "fact_zip_profile.csv",
  "fact_annual_signals.csv",
  "fact_monthly_forecast.csv",
  "fact_policy_response.csv",
  "README.md"
)

present_files <- list.files(ingestion_dir)
missing_files <- setdiff(required_files, present_files)
unexpected_files <- setdiff(present_files, required_files)

if (length(missing_files)) {
  stop("Missing final Tableau file(s): ", paste(missing_files, collapse = ", "))
}

if (length(unexpected_files)) {
  stop(
    "Unexpected file(s) in tableau_ingestion: ",
    paste(unexpected_files, collapse = ", "),
    ". Move analytical/support files outside the final ingestion folder."
  )
}

dimension <- read_csv(
  file.path(ingestion_dir, "dim_geography.csv"),
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)

facts <- list(
  fact_zip_profile = read_csv(
    file.path(ingestion_dir, "fact_zip_profile.csv"),
    col_types = cols(zip5 = col_character()),
    show_col_types = FALSE
  ),
  fact_annual_signals = read_csv(
    file.path(ingestion_dir, "fact_annual_signals.csv"),
    col_types = cols(zip5 = col_character()),
    show_col_types = FALSE
  ),
  fact_monthly_forecast = read_csv(
    file.path(ingestion_dir, "fact_monthly_forecast.csv"),
    col_types = cols(zip5 = col_character()),
    show_col_types = FALSE
  ),
  fact_policy_response = read_csv(
    file.path(ingestion_dir, "fact_policy_response.csv"),
    col_types = cols(zip5 = col_character()),
    show_col_types = FALSE
  )
)

if (anyDuplicated(dimension$geography_key)) {
  stop("dim_geography geography_key is not unique.")
}

relationship_results <- imap_dfr(facts, function(fact, fact_name) {
  orphan_keys <- setdiff(unique(fact$geography_key), dimension$geography_key)
  tibble(
    fact_table = fact_name,
    rows = nrow(fact),
    distinct_geography_keys = n_distinct(fact$geography_key),
    orphan_geography_keys = length(orphan_keys),
    relationship_valid = length(orphan_keys) == 0L
  )
})

if (any(!relationship_results$relationship_valid)) {
  stop("At least one final Tableau fact contains an orphan geography_key.")
}

write_csv(
  relationship_results,
  "tableau_data/week06_final_package_audit.csv"
)

relationship_results
