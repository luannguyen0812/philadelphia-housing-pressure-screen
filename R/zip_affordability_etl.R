library(tidyverse)
library(lubridate)

# =============================================================================
# ZIP AFFORDABILITY ETL: PROPERTY PRICES + ACS HOUSEHOLD INCOME
# =============================================================================
# Purpose:
#   Create a defensible starting point for the team's ZIP-level affordability
#   work. The script uses strict single-property Philadelphia deed records for
#   the initial price numerator, joins ACS 5-year median household income by
#   ZIP Code Tabulation Area (ZCTA), and exports a long-form correlation table.
#
# Run order:
#   1. source("R/BSAN_Proj.R") or otherwise build the versioned team_data files.
#   2. source("R/redfin_zip_etl.R") to normalize the Philadelphia ZIP subset.
#   3. source("R/zip_affordability_etl.R")
#
# Optional refresh (only needed when the team wants newer ACS releases):
#   options(bsan.refresh_acs = TRUE)
#   source("R/zip_affordability_etl.R")
#   options(bsan.refresh_acs = FALSE)
#
# Important interpretation:
#   * Postal ZIP codes and Census ZCTAs are closely related but not identical.
#   * ACS 5-year values pool five years of responses and are labeled by the
#     final year of the estimate. They are not single-year survey estimates.
#   * Price-to-income is descriptive. It does not measure mortgage approval,
#     housing cost burden, or causal effects.
#   * The current RTT price series deliberately uses one-parcel deeds only.
#     Multi-parcel filings are excluded because one document price cannot be
#     attributed to an individual property without complete parcel allocation.

team_document_path <- file.path("team_data", "data_document.csv.gz")
external_dir <- "external_data"
external_raw_dir <- file.path(external_dir, "raw")
tableau_dir <- "tableau_data"

dir.create(external_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(external_raw_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tableau_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(team_document_path)) {
  stop(
    "Missing ", team_document_path,
    ". Run R/BSAN_Proj.R first so the validated document table exists."
  )
}

refresh_acs <- isTRUE(getOption("bsan.refresh_acs", FALSE))
acs_start_year <- 2011L
acs_end_year <- 2024L
census_api_key <- Sys.getenv("CENSUS_API_KEY", unset = "")

# Reuse the validated ACS output already in the project unless a refresh is
# explicitly requested. A Census key is needed only to refresh the full
# 2011-2024 history; it is not needed for normal pipeline runs.
acs_access_method <- if (nzchar(census_api_key)) "Census API" else "Census bulk table"
acs_years <- if (nzchar(census_api_key)) {
  seq.int(acs_start_year, acs_end_year)
} else {
  2021:2024
}
minimum_zip_sales <- 30L

# Normalized Redfin input built by redfin_zip_etl.R. Do not place an unmodified
# Redfin download at this path. The file must have one row per ZIP-period and
# the columns declared in the template below.
redfin_input_path <- file.path(external_raw_dir, "redfin_zip_prices_normalized.csv")
redfin_template_path <- file.path(external_dir, "redfin_zip_input_template.csv")

redfin_template <- tibble(
  zip5 = character(),
  period = as.Date(character()),
  median_sale_price = double(),
  homes_sold = double(),
  property_type = character(),
  source_url = character()
)

if (!file.exists(redfin_template_path)) {
  write_csv(redfin_template, redfin_template_path)
}

# =============================================================================
# 1. STRICT PROPERTY-LEVEL PRICE SERIES FROM PHILADELPHIA RTT
# =============================================================================

document_prices <- read_csv(
  team_document_path,
  col_select = c(
    document_id,
    record_date,
    year,
    primary_zip5,
    n_parcel_rows,
    n_zips,
    activity_type,
    total_consideration,
    nominal_transfer,
    unknown_consideration,
    high_value_sale_outlier
  ),
  col_types = cols(
    document_id = col_character(),
    record_date = col_date(),
    year = col_integer(),
    primary_zip5 = col_character(),
    n_parcel_rows = col_integer(),
    n_zips = col_integer(),
    activity_type = col_character(),
    total_consideration = col_double(),
    nominal_transfer = col_logical(),
    unknown_consideration = col_logical(),
    high_value_sale_outlier = col_logical()
  ),
  show_col_types = FALSE
)

eligible_property_sales <- document_prices |>
  filter(
    activity_type == "sale_deed",
    n_parcel_rows == 1L,
    !nominal_transfer,
    !unknown_consideration,
    !high_value_sale_outlier,
    !is.na(total_consideration),
    total_consideration > 100
  ) |>
  mutate(
    zip5 = primary_zip5,
    period_status = if_else(year == 2026L, "January-July YTD", "Complete year")
  )

fact_citywide_property_price <- eligible_property_sales |>
  summarise(
    n_eligible_property_sales = n(),
    median_property_price = median(total_consideration),
    property_price_q25 = quantile(total_consideration, 0.25, names = FALSE),
    property_price_q75 = quantile(total_consideration, 0.75, names = FALSE),
    .by = c(year, period_status)
  ) |>
  arrange(year) |>
  mutate(
    price_source = "Philadelphia RTT",
    price_measure = "Median eligible single-property deed consideration"
  )

rtt_zip_prices <- eligible_property_sales |>
  filter(str_detect(zip5, "^191[0-9]{2}$")) |>
  summarise(
    n_eligible_sales = n(),
    median_property_price = median(total_consideration),
    property_price_q25 = quantile(total_consideration, 0.25, names = FALSE),
    property_price_q75 = quantile(total_consideration, 0.75, names = FALSE),
    .by = c(zip5, year, period_status)
  ) |>
  arrange(zip5, year) |>
  mutate(
    price_source = "Philadelphia RTT",
    price_measure = "Median eligible single-property deed consideration",
    meets_minimum_sales = n_eligible_sales >= minimum_zip_sales
  )

# =============================================================================
# 2. OPTIONAL NORMALIZED REDFIN ZIP PRICE SERIES
# =============================================================================

redfin_zip_prices <- tibble()

if (file.exists(redfin_input_path)) {
  redfin_monthly <- read_csv(
    redfin_input_path,
    col_types = cols(
      zip5 = col_character(),
      period = col_date(),
      median_sale_price = col_double(),
      homes_sold = col_double(),
      property_type = col_character(),
      source_url = col_character()
    ),
    show_col_types = FALSE
  )

  required_redfin_columns <- names(redfin_template)
  missing_redfin_columns <- setdiff(required_redfin_columns, names(redfin_monthly))

  if (length(missing_redfin_columns) > 0) {
    stop(
      "The normalized Redfin input is missing: ",
      paste(missing_redfin_columns, collapse = ", "),
      ". Follow ", redfin_template_path, "."
    )
  }

  stopifnot(
    !anyDuplicated(redfin_monthly[c("zip5", "period")]),
    all(is.na(redfin_monthly$median_sale_price) |
      redfin_monthly$median_sale_price >= 0)
  )

  redfin_zip_prices <- redfin_monthly |>
    filter(
      str_detect(zip5, "^191[0-9]{2}$"),
      !is.na(period),
      !is.na(median_sale_price),
      median_sale_price > 0
    ) |>
    mutate(year = year(period)) |>
    summarise(
      n_eligible_sales = if (all(is.na(homes_sold))) {
        NA_real_
      } else {
        median(homes_sold, na.rm = TRUE)
      },
      median_property_price = median(median_sale_price),
      property_price_q25 = quantile(median_sale_price, 0.25, names = FALSE),
      property_price_q75 = quantile(median_sale_price, 0.75, names = FALSE),
      months_observed = n_distinct(period),
      .by = c(zip5, year)
    ) |>
    arrange(zip5, year) |>
    mutate(
      period_status = if_else(
        months_observed == 12L,
        "Complete year",
        "Partial year: available rolling periods"
      ),
      price_source = "Redfin",
      price_measure = "Median of Redfin rolling 90-day median sale prices",
      meets_minimum_sales = is.na(n_eligible_sales) |
        n_eligible_sales >= minimum_zip_sales
    )
}

zip_prices_all_sources <- bind_rows(rtt_zip_prices, redfin_zip_prices)

stopifnot(
  !anyDuplicated(
    zip_prices_all_sources[c("price_source", "zip5", "year")]
  )
)

# =============================================================================
# 3. ACS 5-YEAR MEDIAN HOUSEHOLD INCOME BY ZCTA
# =============================================================================

read_acs_api_year <- function(acs_year, refresh = FALSE) {
  destination <- file.path(
    external_raw_dir,
    paste0("ACS5_ZCTA_B19013_", acs_year, ".json")
  )

  query_url <- paste0(
    "https://api.census.gov/data/", acs_year,
    "/acs/acs5?get=NAME,B19013_001E,B19013_001M",
    "&for=zip%20code%20tabulation%20area:*",
    "&key=", URLencode(census_api_key, reserved = TRUE)
  )

  cached_json_is_valid <- file.exists(destination) &&
    identical(readChar(destination, nchars = 1L, useBytes = TRUE), "[")

  if (!cached_json_is_valid || refresh) {
    message("Downloading ACS ", acs_year, " ZCTA income...")
    download.file(query_url, destination, mode = "wb", quiet = TRUE)
  }

  raw_json <- jsonlite::fromJSON(destination, simplifyMatrix = TRUE)

  if (!is.matrix(raw_json) || nrow(raw_json) < 2) {
    stop("Unexpected Census API response in ", destination)
  }

  acs_data <- as_tibble(raw_json[-1, , drop = FALSE], .name_repair = "minimal")
  names(acs_data) <- raw_json[1, ]

  zcta_column <- intersect(
    c("zip code tabulation area", "zip code tabulation area (or part)"),
    names(acs_data)
  )[1]

  if (is.na(zcta_column)) {
    stop(
      "Census response did not contain a ZCTA column. Columns: ",
      paste(names(acs_data), collapse = ", ")
    )
  }

  acs_data |>
    transmute(
      year = as.integer(acs_year),
      zip5 = .data[[zcta_column]],
      zcta_name = NAME,
      median_household_income = as.numeric(B19013_001E),
      median_household_income_moe = as.numeric(B19013_001M)
    ) |>
    mutate(
      median_household_income = if_else(
        median_household_income > 0,
        median_household_income,
        NA_real_
      ),
      median_household_income_moe = if_else(
        median_household_income_moe >= 0,
        median_household_income_moe,
        NA_real_
      ),
      income_moe_pct = median_household_income_moe /
        median_household_income,
      acs_estimate_period = paste0(year - 4L, "-", year),
      acs_access_method = "Census API"
    )
}

read_acs_bulk_year <- function(acs_year, refresh = FALSE) {
  destination <- file.path(
    external_raw_dir,
    paste0("ACS5_ZCTA_B19013_", acs_year, ".dat")
  )

  bulk_url <- paste0(
    "https://www2.census.gov/programs-surveys/acs/summary_file/",
    acs_year,
    "/table-based-SF/data/5YRData/acsdt5y",
    acs_year,
    "-b19013.dat"
  )

  if (!file.exists(destination) || refresh) {
    message("Downloading ACS ", acs_year, " B19013 bulk table...")
    download.file(bulk_url, destination, mode = "wb", quiet = TRUE)
  }

  read_delim(
    destination,
    delim = "|",
    col_types = cols(
      GEO_ID = col_character(),
      B19013_E001 = col_double(),
      B19013_M001 = col_double()
    ),
    show_col_types = FALSE
  ) |>
    # Table-based summary files encode ZCTAs as 860Z200US followed by ZIP5.
    filter(str_detect(GEO_ID, "^860Z200US[0-9]{5}$")) |>
    transmute(
      year = as.integer(acs_year),
      zip5 = str_extract(GEO_ID, "[0-9]{5}$"),
      zcta_name = paste("ZCTA5", zip5),
      median_household_income = if_else(
        B19013_E001 > 0,
        B19013_E001,
        NA_real_
      ),
      median_household_income_moe = if_else(
        B19013_M001 >= 0,
        B19013_M001,
        NA_real_
      ),
      income_moe_pct = median_household_income_moe /
        median_household_income,
      acs_estimate_period = paste0(year - 4L, "-", year),
      acs_access_method = "Census bulk table"
    )
}

project_zip5 <- sort(unique(rtt_zip_prices$zip5))

acs_cache_path <- file.path(external_dir, "acs_zcta_income.csv")
use_existing_acs <- !refresh_acs && file.exists(acs_cache_path)

acs_zcta_income <- if (use_existing_acs) {
  message("Using existing validated ACS file: ", acs_cache_path)
  read_csv(
    acs_cache_path,
    col_types = cols(
      year = col_integer(),
      zip5 = col_character(),
      zcta_name = col_character(),
      median_household_income = col_double(),
      median_household_income_moe = col_double(),
      income_moe_pct = col_double(),
      acs_estimate_period = col_character(),
      acs_access_method = col_character()
    ),
    show_col_types = FALSE
  ) |>
    filter(zip5 %in% project_zip5) |>
    arrange(zip5, year)
} else {
  map_dfr(
    acs_years,
    if (nzchar(census_api_key)) read_acs_api_year else read_acs_bulk_year,
    refresh = refresh_acs
  ) |>
    filter(zip5 %in% project_zip5) |>
    arrange(zip5, year)
}

stopifnot(
  nrow(acs_zcta_income) > 0,
  !anyDuplicated(acs_zcta_income[c("zip5", "year")]),
  all(acs_zcta_income$year >= acs_start_year),
  all(acs_zcta_income$year <= acs_end_year)
)

write_csv(
  acs_zcta_income,
  file.path(external_dir, "acs_zcta_income.csv")
)

# =============================================================================
# 4. ZIP PRICE-TO-INCOME PANEL
# =============================================================================

fact_zip_price_income <- zip_prices_all_sources |>
  left_join(
    acs_zcta_income,
    by = c("zip5", "year")
  ) |>
  arrange(price_source, zip5, year) |>
  mutate(
    price_to_income_ratio = if_else(
      meets_minimum_sales &
        !is.na(median_household_income) &
        median_household_income > 0,
      median_property_price / median_household_income,
      NA_real_
    ),
    log_median_property_price = if_else(
      median_property_price > 0,
      log(median_property_price),
      NA_real_
    ),
    log_median_household_income = if_else(
      median_household_income > 0,
      log(median_household_income),
      NA_real_
    ),
    price_change_yoy = median_property_price /
      lag(median_property_price) - 1,
    income_change_yoy = median_household_income /
      lag(median_household_income) - 1,
    ratio_change_yoy = price_to_income_ratio /
      lag(price_to_income_ratio) - 1,
    .by = c(price_source, zip5)
  )

stopifnot(
  !anyDuplicated(
    fact_zip_price_income[c("price_source", "zip5", "year")]
  )
)

# =============================================================================
# 5. LONG-FORM CORRELATION MATRIX FOR TABLEAU/R REVIEW
# =============================================================================

correlation_variables <- c(
  "log_median_property_price",
  "log_median_household_income",
  "price_to_income_ratio",
  "n_eligible_sales"
)

correlation_input <- fact_zip_price_income |>
  filter(
    meets_minimum_sales,
    !is.na(median_household_income),
    is.na(income_moe_pct) | income_moe_pct <= 0.50
  )

correlation_pairs <- crossing(
  variable_x = correlation_variables,
  variable_y = correlation_variables
)

calculate_pair_correlation <- function(data, variable_x, variable_y) {
  pair_data <- data |>
    select(
      x = all_of(variable_x),
      y = all_of(variable_y)
    ) |>
    drop_na()

  tibble(
    observations = nrow(pair_data),
    pearson_correlation = if (nrow(pair_data) >= 3) {
      cor(pair_data$x, pair_data$y, method = "pearson")
    } else {
      NA_real_
    },
    spearman_correlation = if (nrow(pair_data) >= 3) {
      cor(pair_data$x, pair_data$y, method = "spearman")
    } else {
      NA_real_
    }
  )
}

build_correlation_matrix <- function(data, scope, analysis_year = NA_integer_) {
  source_name <- first(data$price_source)

  correlation_pairs |>
    mutate(
      result = map2(
        variable_x,
        variable_y,
        ~ calculate_pair_correlation(data, .x, .y)
      )
    ) |>
    unnest(result) |>
    mutate(
      price_source = source_name,
      correlation_scope = scope,
      analysis_year = as.integer(analysis_year),
      year_start = min(data$year),
      year_end = max(data$year),
      unique_zips = n_distinct(data$zip5),
      .before = 1
    )
}

# Retain the pooled result for technical comparison, but also calculate a
# separate cross-sectional matrix for every year. The client-facing chart uses
# the latest annual cross-section so common time trends do not inflate the
# displayed relationship between price and income.
pooled_correlations <- correlation_input |>
  group_split(price_source) |>
  map_dfr(function(source_data) {
    build_correlation_matrix(
      source_data,
      scope = "Pooled ZIP-years"
    )
  })

annual_cross_section_correlations <- correlation_input |>
  group_split(price_source, year) |>
  map_dfr(function(source_year_data) {
    build_correlation_matrix(
      source_year_data,
      scope = "Annual ZIP cross-section",
      analysis_year = first(source_year_data$year)
    )
  })

model_zip_price_income_correlations <- bind_rows(
  annual_cross_section_correlations,
  pooled_correlations
) |>
  arrange(
    price_source,
    correlation_scope,
    analysis_year,
    variable_y,
    variable_x
  )

# =============================================================================
# 6. EXPORTS, CATALOG, AND VALIDATION
# =============================================================================

citywide_price_path <- file.path(tableau_dir, "fact_citywide_property_price.csv")
zip_affordability_path <- file.path(tableau_dir, "fact_zip_price_income.csv")
correlation_path <- file.path(
  tableau_dir,
  "model_zip_price_income_correlations.csv"
)

write_csv(fact_citywide_property_price, citywide_price_path)
write_csv(fact_zip_price_income, zip_affordability_path)
write_csv(model_zip_price_income_correlations, correlation_path)

source_catalog_path <- file.path(external_dir, "source_catalog.csv")
source_catalog <- if (file.exists(source_catalog_path)) {
  read_csv(source_catalog_path, show_col_types = FALSE)
} else {
  tibble(
    output_field = character(),
    source = character(),
    series_or_file = character(),
    frequency = character(),
    transformation = character(),
    source_url = character()
  )
}

affordability_sources <- tribble(
  ~output_field, ~source, ~series_or_file, ~frequency, ~transformation, ~source_url,
  "median_property_price", "Philadelphia Department of Records", "team_data/data_document.csv.gz", "annual by ZIP", "Median consideration among eligible single-property, non-nominal, non-outlier deed documents", "https://opendataphilly.org/datasets/real-estate-transfers/",
  "median_household_income", "U.S. Census Bureau", "ACS 5-year B19013_001E", "annual 5-year estimate by ZCTA", "Used as published; joined from ZCTA to same five-character ZIP code", "https://api.census.gov/data.html",
  "median_household_income_moe", "U.S. Census Bureau", "ACS 5-year B19013_001M", "annual 5-year estimate by ZCTA", "Margin of error retained; correlation input excludes estimates with relative MOE above 50%", "https://api.census.gov/data.html",
  "redfin_median_sale_price", "Redfin", "external_data/raw/redfin_zip_prices_normalized.csv", "rolling 90-day period by ZIP", "All Residential only; period is the rolling-window end date; annual value is the median of available rolling-period medians", "https://www.redfin.com/news/data-center/",
  "redfin_homes_sold", "Redfin", "external_data/raw/redfin_zip_prices_normalized.csv", "rolling 90-day period by ZIP", "Annual activity field is the median of available rolling-period homes-sold counts; it is not an annual sum", "https://www.redfin.com/news/data-center/"
)

source_catalog <- bind_rows(
  source_catalog |>
    filter(!output_field %in% affordability_sources$output_field),
  affordability_sources
)

write_csv(source_catalog, source_catalog_path)
write_csv(source_catalog, file.path(tableau_dir, "source_catalog.csv"))

manifest_path <- file.path(tableau_dir, "README_export_manifest.csv")
manifest <- if (file.exists(manifest_path)) {
  read_csv(manifest_path, show_col_types = FALSE)
} else {
  tibble(
    file = character(),
    grain = character(),
    key = character(),
    purpose = character()
  )
}

affordability_manifest <- tribble(
  ~file, ~grain, ~key, ~purpose,
  "fact_citywide_property_price.csv", "year", "year", "Citywide median price for eligible single-property deed records",
  "fact_zip_price_income.csv", "price source x ZIP x year", "price_source + zip5 + year", "ZIP price, ACS household income, and descriptive price-to-income ratio",
  "model_zip_price_income_correlations.csv", "price source x scope x year x variable pair", "price_source + correlation_scope + analysis_year + variable_x + variable_y", "Annual cross-sectional and pooled Pearson/Spearman correlation matrices in long form"
)

manifest <- bind_rows(
  manifest |>
    filter(!file %in% affordability_manifest$file),
  affordability_manifest
)

write_csv(manifest, manifest_path)

stopifnot(
  nrow(fact_citywide_property_price) > 0,
  nrow(fact_zip_price_income) > 0,
  all(
    fact_zip_price_income$price_to_income_ratio[
      !is.na(fact_zip_price_income$price_to_income_ratio)
    ] > 0
  ),
  !anyDuplicated(
    model_zip_price_income_correlations[
      c(
        "price_source", "correlation_scope", "analysis_year",
        "variable_x", "variable_y"
      )
    ]
  )
)

message(
  "ZIP affordability outputs written: ",
  scales::comma(nrow(fact_zip_price_income)), " ZIP-year price rows; ",
  scales::comma(sum(!is.na(fact_zip_price_income$price_to_income_ratio))),
  " matched price-to-income observations."
)
