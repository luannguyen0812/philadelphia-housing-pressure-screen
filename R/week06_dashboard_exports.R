library(tidyverse)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 06: FINAL TABLEAU DASHBOARD EXPORTS
# =============================================================================
# ABSTRACT
# Build the compact, relationship-safe data package for one final interactive
# Tableau dashboard. The package uses a geography dimension and separate fact
# tables at ZIP-profile, ZIP-year, and ZIP-month grains. Facts are related in
# Tableau through geography_key; they must not be physically joined because a
# physical join would multiply rows and distort counts. The dashboard defaults
# to 19132 and 19143 but retains every ZIP/ZCTA that passed the Week 4 coverage
# gate. Forecasts remain case-study-only and are labeled accordingly.

# =============================================================================
# 1. SETTINGS, PATHS, AND REQUIRED INPUTS
# =============================================================================
# Caption: Declare the two case studies, the final Tableau folder, and every
# upstream table needed to build a reproducible semantic layer.

selected_zips <- c("19132", "19143")
ingestion_dir <- file.path("tableau_data", "tableau_ingestion")

paths <- list(
  benchmark = file.path("tableau_data", "week05_citywide_zip_benchmark.csv"),
  endpoints = file.path("tableau_data", "week05_neighborhood_change_endpoints.csv"),
  permits = file.path("tableau_data", "week05_permit_signals.csv"),
  evictions = file.path("tableau_data", "week05_eviction_annual_zip.csv"),
  eviction_city = file.path(
    "tableau_data", "week05_eviction_rate_case_studies_city.csv"
  ),
  market = file.path("tableau_data", "week05_redfin_market_signals.csv"),
  price_income = file.path("tableau_data", "fact_zip_price_income.csv"),
  vulnerability = file.path("external_data", "acs_zcta_vulnerability.csv"),
  forecast = file.path("tableau_data", "week05_primary_intervention_forecast.csv"),
  documents = file.path("team_data", "data_document.csv.gz")
)

missing_inputs <- names(paths)[!file.exists(unlist(paths))]
if (length(missing_inputs)) {
  stop("Missing Week 6 input(s): ", paste(missing_inputs, collapse = ", "))
}

dir.create(ingestion_dir, recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# 2. LOAD THE QUALIFYING GEOGRAPHY UNIVERSE
# =============================================================================
# Caption: Use the same 37-ZIP coverage gate throughout the dashboard so every
# worksheet and filter refers to one documented analytical universe.

benchmark <- read_csv(
  paths$benchmark,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)

qualifying_zips <- sort(unique(benchmark$zip5))

if (length(qualifying_zips) != 37L || anyDuplicated(qualifying_zips)) {
  stop("Expected 37 unique qualifying ZIP/ZCTAs in the Week 5 benchmark.")
}

dim_geography <- bind_rows(
  benchmark |>
    transmute(
      geography_key = paste0("ZIP_", zip5),
      geography_level = "ZIP/ZCTA",
      zip5,
      geography_label = paste("ZIP/ZCTA", zip5),
      selectable_zip = TRUE,
      default_dashboard_selection,
      case_group,
      case_study_detail_available = zip5 %in% selected_zips,
      forecast_available = zip5 %in% selected_zips,
      geography_sort = if_else(
        zip5 == "19132", 1L,
        if_else(zip5 == "19143", 2L, 100L + row_number())
      )
    ),
  tibble(
    geography_key = "CITY_PHL",
    geography_level = "City benchmark",
    zip5 = NA_character_,
    geography_label = "Philadelphia benchmark",
    selectable_zip = FALSE,
    default_dashboard_selection = FALSE,
    case_group = "City benchmark",
    case_study_detail_available = FALSE,
    forecast_available = FALSE,
    geography_sort = 999L
  )
)

if (anyDuplicated(dim_geography$geography_key)) {
  stop("dim_geography geography_key must be unique.")
}

# =============================================================================
# 3. BUILD ONE-ROW-PER-GEOGRAPHY EVIDENCE PROFILES
# =============================================================================
# Caption: Put the selection, vulnerability, affordability, outcome, permit,
# and market-context measures at one stable ZIP grain for KPI cards and the
# all-ZIP comparison view.

endpoints <- read_csv(
  paths$endpoints,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips)

vulnerability_2024 <- read_csv(
  paths$vulnerability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(year == 2024L, zip5 %in% qualifying_zips) |>
  select(
    zip5, renter_share_moe, renter_cost_burden,
    renter_cost_burden_moe, poverty_rate, poverty_rate_moe, senior_share,
    senior_share_moe, zip_zcta_caution
  )

permit_summary <- read_csv(
  paths$permits,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2023:2025) |>
  summarise(
    new_construction_permits_2023_2025 = sum(
      new_construction_permits, na.rm = TRUE
    ),
    permitted_units_2023_2025 = sum(permitted_units, na.rm = TRUE),
    .by = zip5
  )

eviction_latest <- read_csv(
  paths$evictions,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year == max(year, na.rm = TRUE)) |>
  select(
    zip5,
    eviction_filings_2025 = filings,
    eviction_filings_per_1000_renters_2025 =
      filings_per_1000_estimated_renter_households,
    eviction_denominator_caution = denominator_caution
  )

market_latest <- read_csv(
  paths$market,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year == 2025L) |>
  select(
    zip5,
    redfin_inventory_2025 = mean_inventory,
    redfin_median_days_on_market_2025 = mean_median_days_on_market,
    redfin_homes_sold_2025 = annual_homes_sold
  )

zip_profile <- benchmark |>
  left_join(endpoints, by = "zip5") |>
  left_join(vulnerability_2024, by = "zip5") |>
  left_join(permit_summary, by = "zip5") |>
  left_join(eviction_latest, by = "zip5") |>
  left_join(market_latest, by = "zip5") |>
  mutate(
    geography_key = paste0("ZIP_", zip5),
    permitted_units_per_1000_occupied_2023_2025 =
      1000 * permitted_units_2023_2025 / occupied_housing_units,
    price_growth_percentile = percent_rank(redfin_2015_2024_cagr),
    transaction_contraction_percentile = percent_rank(-transaction_change_pct),
    affordability_ratio_percentile = percent_rank(price_to_income_2024),
    eviction_rate_percentile = percent_rank(
      eviction_filings_per_1000_renters_2025
    ),
    permit_pipeline_percentile = percent_rank(
      permitted_units_per_1000_occupied_2023_2025
    ),
    endpoint_income_moe_status = if_else(
      endpoint_income_moe_warning,
      "Review: endpoint income relative MOE exceeds 20%",
      "Pass: endpoint income relative MOE at or below 20%"
    ),
    record_type = "ZIP/ZCTA estimate",
    dashboard_note = paste(
      "Screening and monitoring evidence; descriptive relationships do not",
      "prove that an individual household was displaced."
    )
  )

# Caption: Add a separately labeled benchmark row. Percentile fields equal 0.5
# by definition; raw values are medians across the 37 qualifying ZIP/ZCTAs.

city_profile <- zip_profile |>
  summarise(
    geography_key = "CITY_PHL",
    zip5 = NA_character_,
    redfin_2015_2024_cagr = median(redfin_2015_2024_cagr, na.rm = TRUE),
    vulnerability_percentile = 0.5,
    market_growth_rank = NA_integer_,
    vulnerability_rank = NA_integer_,
    annual_eligible_sales_2015_2017 = sum(
      annual_eligible_sales_2015_2017, na.rm = TRUE
    ),
    annual_eligible_sales_2022_2024 = sum(
      annual_eligible_sales_2022_2024, na.rm = TRUE
    ),
    years_observed_2015_2017 = 3,
    years_observed_2022_2024 = 3,
    transaction_change_pct = median(transaction_change_pct, na.rm = TRUE),
    occupied_housing_units = sum(occupied_housing_units, na.rm = TRUE),
    renter_share = median(renter_share, na.rm = TRUE),
    sales_per_1000_occupied_2015_2017 =
      sum(annual_eligible_sales_2015_2017, na.rm = TRUE) /
      sum(occupied_housing_units, na.rm = TRUE) * 1000,
    sales_per_1000_occupied_2022_2024 =
      sum(annual_eligible_sales_2022_2024, na.rm = TRUE) /
      sum(occupied_housing_units, na.rm = TRUE) * 1000,
    case_group = "City benchmark",
    default_dashboard_selection = FALSE,
    dashboard_selection_order = 999L,
    median_sale_price_2014 = median(median_sale_price_2014, na.rm = TRUE),
    median_sale_price_2024 = median(median_sale_price_2024, na.rm = TRUE),
    median_household_income_2014 = median(
      median_household_income_2014, na.rm = TRUE
    ),
    median_household_income_2024 = median(
      median_household_income_2024, na.rm = TRUE
    ),
    median_household_income_moe_2014 = NA_real_,
    median_household_income_moe_2024 = NA_real_,
    income_moe_pct_2014 = NA_real_,
    income_moe_pct_2024 = NA_real_,
    acs_estimate_period_2014 = "2010-2014",
    acs_estimate_period_2024 = "2020-2024",
    price_change_pct = median(price_change_pct, na.rm = TRUE),
    income_change_pct = median(income_change_pct, na.rm = TRUE),
    affordability_growth_gap = median(affordability_growth_gap, na.rm = TRUE),
    price_to_income_2014 = median(price_to_income_2014, na.rm = TRUE),
    price_to_income_2024 = median(price_to_income_2024, na.rm = TRUE),
    ratio_change = median(ratio_change, na.rm = TRUE),
    endpoint_income_moe_warning = NA,
    display_group = "Philadelphia qualifying-ZIP median",
    renter_share_moe = NA_real_,
    renter_cost_burden = median(renter_cost_burden, na.rm = TRUE),
    renter_cost_burden_moe = NA_real_,
    poverty_rate = median(poverty_rate, na.rm = TRUE),
    poverty_rate_moe = NA_real_,
    senior_share = median(senior_share, na.rm = TRUE),
    senior_share_moe = NA_real_,
    zip_zcta_caution = "Benchmark summarizes qualifying ZIP/ZCTAs",
    new_construction_permits_2023_2025 = sum(
      new_construction_permits_2023_2025, na.rm = TRUE
    ),
    permitted_units_2023_2025 = sum(permitted_units_2023_2025, na.rm = TRUE),
    eviction_filings_2025 = sum(eviction_filings_2025, na.rm = TRUE),
    eviction_filings_per_1000_renters_2025 = median(
      eviction_filings_per_1000_renters_2025, na.rm = TRUE
    ),
    eviction_denominator_caution =
      "Median ZIP rate; see annual fact for pooled Philadelphia rate",
    redfin_inventory_2025 = median(redfin_inventory_2025, na.rm = TRUE),
    redfin_median_days_on_market_2025 = median(
      redfin_median_days_on_market_2025, na.rm = TRUE
    ),
    redfin_homes_sold_2025 = sum(redfin_homes_sold_2025, na.rm = TRUE),
    permitted_units_per_1000_occupied_2023_2025 =
      sum(permitted_units_2023_2025, na.rm = TRUE) /
      sum(occupied_housing_units, na.rm = TRUE) * 1000,
    price_growth_percentile = 0.5,
    transaction_contraction_percentile = 0.5,
    affordability_ratio_percentile = 0.5,
    eviction_rate_percentile = 0.5,
    permit_pipeline_percentile = 0.5,
    endpoint_income_moe_status = "Not applicable to a median benchmark",
    record_type = "Philadelphia qualifying-ZIP benchmark",
    dashboard_note = paste(
      "Most raw values are medians across qualifying ZIP/ZCTAs; pooled rates",
      "are explicitly identified in the annual fact table."
    )
  )

fact_zip_profile <- bind_rows(zip_profile, city_profile) |>
  arrange(match(geography_key, dim_geography$geography_key))

if (anyDuplicated(fact_zip_profile$geography_key)) {
  stop("fact_zip_profile must contain one row per geography_key.")
}

write_csv(fact_zip_profile, "tableau_data/week06_zip_evidence_profile.csv")

# =============================================================================
# 4. BUILD THE ALL-ZIP ANNUAL SIGNAL FACT
# =============================================================================
# Caption: Align each annual source at ZIP-year grain without inventing missing
# values. Blank cells mean that the source does not cover that year/measure.

price_income_annual <- read_csv(
  paths$price_income,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)

redfin_annual <- price_income_annual |>
  filter(
    zip5 %in% qualifying_zips,
    price_source == "Redfin",
    year %in% 2014:2025
  ) |>
  select(
    zip5, year,
    redfin_median_sale_price = median_property_price,
    redfin_activity_measure = n_eligible_sales,
    median_household_income,
    median_household_income_moe,
    income_moe_pct,
    acs_estimate_period,
    price_to_income_ratio
  )

rtt_annual <- price_income_annual |>
  filter(
    zip5 %in% qualifying_zips,
    price_source == "Philadelphia RTT",
    year %in% 2014:2025
  ) |>
  select(
    zip5, year,
    rtt_eligible_sales = n_eligible_sales,
    rtt_median_sale_consideration = median_property_price,
    rtt_sale_price_q25 = property_price_q25,
    rtt_sale_price_q75 = property_price_q75
  )

permit_annual <- read_csv(
  paths$permits,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2014:2025)

eviction_annual <- read_csv(
  paths$evictions,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2014:2025) |>
  select(
    zip5, year,
    eviction_filings = filings,
    eviction_filing_index = filing_index_vs_prepandemic,
    eviction_filings_per_1000_renters =
      filings_per_1000_estimated_renter_households,
    eviction_months_observed = months_observed
  )

market_annual <- read_csv(
  paths$market,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2014:2025) |>
  select(
    zip5, year,
    redfin_inventory = mean_inventory,
    redfin_median_days_on_market = mean_median_days_on_market,
    redfin_months_of_supply = mean_months_of_supply,
    redfin_homes_sold = annual_homes_sold
  )

vulnerability_annual <- read_csv(
  paths$vulnerability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2014:2025) |>
  select(
    zip5, year, occupied_housing_units, renter_share, renter_share_moe,
    renter_cost_burden, renter_cost_burden_moe, poverty_rate,
    poverty_rate_moe, senior_share, senior_share_moe
  )

fact_annual_zip <- expand_grid(zip5 = qualifying_zips, year = 2014:2025) |>
  left_join(redfin_annual, by = c("zip5", "year")) |>
  left_join(rtt_annual, by = c("zip5", "year")) |>
  left_join(permit_annual, by = c("zip5", "year")) |>
  left_join(eviction_annual, by = c("zip5", "year")) |>
  left_join(market_annual, by = c("zip5", "year")) |>
  left_join(vulnerability_annual, by = c("zip5", "year")) |>
  mutate(
    geography_key = paste0("ZIP_", zip5),
    geography_level = "ZIP/ZCTA",
    annual_record_status = case_when(
      year == 2025L ~ "Latest complete dashboard year; ACS 2024 carried only where explicitly shown",
      TRUE ~ "Complete annual period where source is available"
    ),
    source_definition_note = paste(
      "RTT is eligible single-property arm's-length deed activity;",
      "Redfin is its published rolling-period ZIP measure;",
      "ACS values are five-year estimates; permits are applications;",
      "eviction filings are cases, not completed evictions."
    )
  ) |>
  select(geography_key, zip5, geography_level, year, everything())

# Caption: Add a benchmark row for every year. Medians describe a typical
# qualifying ZIP; volume fields are pooled sums. Eviction rate uses the pooled
# Philadelphia denominator from the Week 5 city benchmark when available.

city_eviction <- read_csv(
  paths$eviction_city,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 == "Philadelphia") |>
  select(
    year,
    city_eviction_filings = filings,
    city_eviction_rate = filings_per_1000_estimated_renter_households,
    city_eviction_months = months_observed
  )

sum_or_na <- function(x) {
  if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
}

median_or_na <- function(x) {
  if (all(is.na(x))) NA_real_ else median(x, na.rm = TRUE)
}

max_or_na <- function(x) {
  if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)
}

first_or_na <- function(x) {
  x <- x[!is.na(x)]
  if (length(x)) first(x) else NA_character_
}

fact_annual_city <- fact_annual_zip |>
  summarise(
    zip5 = NA_character_,
    geography_level = "City benchmark",
    redfin_median_sale_price = median_or_na(redfin_median_sale_price),
    redfin_activity_measure = sum_or_na(redfin_activity_measure),
    median_household_income = median_or_na(median_household_income),
    median_household_income_moe = NA_real_,
    income_moe_pct = NA_real_,
    acs_estimate_period = first_or_na(acs_estimate_period),
    price_to_income_ratio = median_or_na(price_to_income_ratio),
    rtt_eligible_sales = sum_or_na(rtt_eligible_sales),
    rtt_median_sale_consideration = median_or_na(
      rtt_median_sale_consideration
    ),
    rtt_sale_price_q25 = median_or_na(rtt_sale_price_q25),
    rtt_sale_price_q75 = median_or_na(rtt_sale_price_q75),
    all_permits = sum_or_na(all_permits),
    new_construction_permits = sum_or_na(new_construction_permits),
    permitted_units = sum_or_na(permitted_units),
    eviction_filings = sum_or_na(eviction_filings),
    eviction_filing_index = median_or_na(eviction_filing_index),
    eviction_filings_per_1000_renters = median_or_na(
      eviction_filings_per_1000_renters
    ),
    eviction_months_observed = max_or_na(eviction_months_observed),
    redfin_inventory = sum_or_na(redfin_inventory),
    redfin_median_days_on_market = median_or_na(
      redfin_median_days_on_market
    ),
    redfin_months_of_supply = median_or_na(redfin_months_of_supply),
    redfin_homes_sold = sum_or_na(redfin_homes_sold),
    occupied_housing_units = sum_or_na(occupied_housing_units),
    renter_share = median_or_na(renter_share),
    renter_share_moe = NA_real_,
    renter_cost_burden = median_or_na(renter_cost_burden),
    renter_cost_burden_moe = NA_real_,
    poverty_rate = median_or_na(poverty_rate),
    poverty_rate_moe = NA_real_,
    senior_share = median_or_na(senior_share),
    senior_share_moe = NA_real_,
    annual_record_status = "Philadelphia qualifying-ZIP benchmark",
    source_definition_note = paste(
      "Price, income, ratios, days on market, and shares are qualifying-ZIP",
      "medians; activity, permits, inventory, and units are pooled sums."
    ),
    .by = year
  ) |>
  left_join(city_eviction, by = "year") |>
  mutate(
    geography_key = "CITY_PHL",
    eviction_filings = coalesce(city_eviction_filings, eviction_filings),
    eviction_filings_per_1000_renters = coalesce(
      city_eviction_rate, eviction_filings_per_1000_renters
    ),
    eviction_months_observed = coalesce(
      city_eviction_months, eviction_months_observed
    )
  ) |>
  select(-starts_with("city_")) |>
  select(names(fact_annual_zip))

fact_annual_signals <- bind_rows(fact_annual_zip, fact_annual_city) |>
  arrange(geography_key, year)

if (anyDuplicated(select(fact_annual_signals, geography_key, year))) {
  stop("fact_annual_signals requires a unique geography_key + year grain.")
}

# =============================================================================
# 5. BUILD THE CASE-STUDY MONTHLY HISTORY AND FORECAST FACT
# =============================================================================
# Caption: Combine observed monthly eligible sales with the primary
# intervention-adjusted Auto-ARIMA forecast without treating forecasts as
# observations. This table intentionally covers only 19132 and 19143.

observed_monthly <- read_csv(
  paths$documents,
  col_select = c(
    document_type, activity_type, year, yr_mo, primary_zip5, n_parcel_rows,
    total_consideration, nominal_transfer, unknown_consideration,
    high_value_sale_outlier
  ),
  col_types = cols(yr_mo = col_date(), primary_zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(
    primary_zip5 %in% selected_zips,
    year %in% 2010:2025,
    document_type == "DEED",
    activity_type == "sale_deed",
    n_parcel_rows == 1L,
    !nominal_transfer,
    !unknown_consideration,
    !high_value_sale_outlier,
    total_consideration > 100
  ) |>
  count(zip5 = primary_zip5, month = yr_mo, name = "monthly_sales") |>
  complete(
    zip5 = selected_zips,
    month = seq.Date(
      as.Date("2010-01-01"), as.Date("2025-12-01"), by = "month"
    ),
    fill = list(monthly_sales = 0L)
  ) |>
  transmute(
    geography_key = paste0("ZIP_", zip5),
    zip5,
    month,
    series_type = "Observed",
    monthly_sales = as.double(monthly_sales),
    lower_80 = NA_real_,
    upper_80 = NA_real_,
    lower_95 = NA_real_,
    upper_95 = NA_real_,
    forecast_specification = NA_character_,
    training_observation = TRUE,
    displayed_in_default_view = month >= as.Date("2015-01-01")
  )

forecast_monthly <- read_csv(
  paths$forecast,
  col_types = cols(zip5 = col_character(), month = col_date()),
  show_col_types = FALSE
) |>
  transmute(
    geography_key = paste0("ZIP_", zip5),
    zip5,
    month,
    series_type = "Forecast",
    monthly_sales = forecast_sales,
    lower_80,
    upper_80,
    lower_95,
    upper_95,
    forecast_specification = paste(
      "Auto-ARIMA with pandemic and recording-backlog intervention variables"
    ),
    training_observation = FALSE,
    displayed_in_default_view = TRUE
  )

fact_monthly_forecast <- bind_rows(observed_monthly, forecast_monthly) |>
  arrange(geography_key, month, series_type)

if (anyDuplicated(select(
  fact_monthly_forecast, geography_key, month, series_type
))) {
  stop("fact_monthly_forecast has duplicate geography/month/series rows.")
}

# =============================================================================
# 6. VALIDATE RELATIONSHIPS AND WRITE THE CORE TABLEAU PACKAGE
# =============================================================================
# Caption: Fail the build if any fact contains a key that is absent from the
# geography dimension. Tableau relationships are valid only when these foreign
# keys are complete and the dimension key remains unique.

assert_foreign_key <- function(fact, fact_name) {
  orphan_keys <- setdiff(unique(fact$geography_key), dim_geography$geography_key)
  if (length(orphan_keys)) {
    stop(fact_name, " contains orphan geography_key(s): ",
         paste(orphan_keys, collapse = ", "))
  }
}

assert_foreign_key(fact_zip_profile, "fact_zip_profile")
assert_foreign_key(fact_annual_signals, "fact_annual_signals")
assert_foreign_key(fact_monthly_forecast, "fact_monthly_forecast")

write_csv(dim_geography, file.path(ingestion_dir, "dim_geography.csv"))
write_csv(fact_zip_profile, file.path(ingestion_dir, "fact_zip_profile.csv"))
write_csv(
  fact_annual_signals,
  file.path(ingestion_dir, "fact_annual_signals.csv")
)
write_csv(
  fact_monthly_forecast,
  file.path(ingestion_dir, "fact_monthly_forecast.csv")
)

relationship_audit <- tibble(
  table_name = c(
    "dim_geography", "fact_zip_profile", "fact_annual_signals",
    "fact_monthly_forecast"
  ),
  grain = c(
    "one row per geography_key",
    "one row per geography_key",
    "one row per geography_key + year",
    "one row per geography_key + month + series_type"
  ),
  rows = c(
    nrow(dim_geography), nrow(fact_zip_profile), nrow(fact_annual_signals),
    nrow(fact_monthly_forecast)
  ),
  unique_primary_key = c(
    !anyDuplicated(dim_geography$geography_key),
    !anyDuplicated(fact_zip_profile$geography_key),
    !anyDuplicated(select(fact_annual_signals, geography_key, year)),
    !anyDuplicated(select(
      fact_monthly_forecast, geography_key, month, series_type
    ))
  ),
  orphan_geography_keys = 0L,
  tableau_relationship = c(
    "Root dimension",
    "dim_geography.geography_key = fact_zip_profile.geography_key",
    "dim_geography.geography_key = fact_annual_signals.geography_key",
    "dim_geography.geography_key = fact_monthly_forecast.geography_key"
  )
)

write_csv(
  relationship_audit,
  "tableau_data/week06_tableau_relationship_audit.csv"
)

# =============================================================================
# VISUALIZATION 1 — CASE-STUDY EVIDENCE PERCENTILE PROFILE
# =============================================================================
# Caption: Put unlike measures on a common percentile scale without combining
# them into one opaque score. Fifty marks the qualifying-ZIP median; higher
# means more pressure/exposure for the definition printed on each row.

evidence_labels <- c(
  price_growth_percentile = "Price-growth speed",
  vulnerability_percentile = "Resident vulnerability",
  transaction_contraction_percentile = "Transaction contraction",
  affordability_ratio_percentile = "Price-to-income ratio",
  eviction_rate_percentile = "Eviction-filing rate",
  permit_pipeline_percentile = "Permitted-unit pipeline"
)

case_evidence_long <- fact_zip_profile |>
  filter(zip5 %in% selected_zips) |>
  select(zip5, all_of(names(evidence_labels))) |>
  pivot_longer(
    -zip5,
    names_to = "measure",
    values_to = "percentile"
  ) |>
  mutate(
    measure_label = factor(
      evidence_labels[measure],
      levels = rev(unname(evidence_labels))
    ),
    percentile_label = scales::percent(percentile, accuracy = 1)
  )

case_evidence_plot <- ggplot(
  case_evidence_long,
  aes(percentile, measure_label, color = zip5, group = measure_label)
) +
  geom_vline(
    xintercept = 0.5,
    linewidth = 1.1,
    linetype = "dashed",
    color = "#252525"
  ) +
  geom_line(color = "#BDBDBD", linewidth = 1.3) +
  geom_point(size = 5) +
  geom_text(
    aes(label = percentile_label),
    nudge_y = 0.18,
    fontface = "bold",
    size = 3.8,
    show.legend = FALSE
  ) +
  scale_color_manual(values = c("19132" = "#D95F0E", "19143" = "#08519C")) +
  scale_x_continuous(
    limits = c(0, 1),
    breaks = seq(0, 1, 0.25),
    labels = scales::label_percent(accuracy = 1)
  ) +
  labs(
    title = "The Two ZIPs Show Different Housing-Pressure Profiles",
    subtitle = "Percentile among 37 qualifying Philadelphia ZIP/ZCTAs",
    x = "Pressure or exposure percentile",
    y = NULL,
    color = "ZIP/ZCTA",
    caption = paste(
      "The 50% line is the qualifying-ZIP median. Percentiles preserve each",
      "measure separately; they are not a causal gentrification index."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week06_case_evidence_percentiles.png",
  case_evidence_plot,
  width = 11,
  height = 7.5,
  dpi = 300
)

# =============================================================================
# 7. PRINT WEEK 6 DASHBOARD OUTPUTS TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(case_evidence_plot)
}

relationship_audit
