# =============================================================================
# 02. EXTERNAL ECONOMIC AND PEER-CITY CONTEXT
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Downloads, caches and cleans the national and peer-metro series used as
#   context, as a deflator, and as the external-driver challenger.
# INPUTS
#   FRED series MORTGAGE30US, USREC, CPIAUCSL, ATNHPIUS37964Q and four peer
#   MSA HPI series (downloaded as CSV; no API key)
#   optional Zillow metro ZHVI and sales-count CSVs
# OUTPUTS
#   external_data/dim_econ_indicators.csv
#   external_data/fact_quarterly_peer_hpi.csv
#   external_data/fact_monthly_peer_cities.csv
#   external_data/source_catalog.csv
#   cached raw downloads in external_data/raw/
# RUNS AFTER   nothing
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)
library(lubridate)

# =============================================================================
# EXTERNAL ETL 1: PURPOSE, OUTPUTS, AND REFRESH POLICY
# =============================================================================
# Purpose:
#   Build the economic and peer-market inputs needed to compare Philadelphia's
#   deed and mortgage activity with mortgage rates, house prices, recessions,
#   and comparable legacy-city housing markets.
#
# Design choices:
#   * FRED CSV downloads require no API key and provide stable series IDs.
#   * Raw downloads are cached in external_data/raw so the analysis remains
#     reproducible and does not hit external sites every time the R file runs.
#   * Set options(bsan.refresh_external = TRUE) before sourcing this script to
#     deliberately refresh cached downloads.
#   * Quarterly FHFA price indexes are repeated across the three months in
#     their quarter only for joining to the monthly Philadelphia panel. This is
#     a frequency-alignment convention, not newly observed monthly HPI data.
#   * Zillow is optional because its public CSV paths occasionally change. The
#     FRED/FHFA outputs are still created if a Zillow download is unavailable.
#
# Main outputs:
#   external_data/dim_econ_indicators.csv
#   external_data/fact_quarterly_peer_hpi.csv
#   external_data/fact_monthly_peer_cities.csv (when Zillow is available)
#   external_data/source_catalog.csv

external_dir <- "external_data"
external_raw_dir <- file.path(external_dir, "raw")
dir.create(external_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(external_raw_dir, showWarnings = FALSE, recursive = TRUE)

refresh_external <- isTRUE(getOption("bsan.refresh_external", FALSE))
analysis_start <- as_date("2000-01-01")
analysis_end <- as_date("2026-07-31")

download_cached <- function(url, destination, refresh = FALSE, required = TRUE) {
  if (!file.exists(destination) || refresh) {
    message("Downloading: ", url)
    result <- tryCatch(
      {
        download.file(url, destination, mode = "wb", quiet = TRUE)
        TRUE
      },
      error = function(e) {
        if (file.exists(destination)) {
          file.remove(destination)
        }
        if (required) {
          stop("Required download failed: ", url, "\n", conditionMessage(e))
        }
        warning("Optional download failed: ", url, "\n", conditionMessage(e))
        FALSE
      }
    )
    if (!result) {
      return(NA_character_)
    }
  }
  destination
}

read_fred_series <- function(series_id, refresh = FALSE) {
  destination <- file.path(external_raw_dir, paste0("FRED_", series_id, ".csv"))
  url <- paste0(
    "https://fred.stlouisfed.org/graph/fredgraph.csv?id=", series_id,
    "&cosd=", format(analysis_start, "%Y-%m-%d"),
    "&coed=", format(analysis_end, "%Y-%m-%d")
  )
  download_cached(url, destination, refresh = refresh, required = TRUE)

  fred_raw <- read_csv(
    destination,
    na = c(".", "NA"),
    show_col_types = FALSE
  )
  date_column <- intersect(c("DATE", "observation_date"), names(fred_raw))[1]

  if (is.na(date_column) || !series_id %in% names(fred_raw)) {
    stop(
      "Unexpected FRED schema for ", series_id, ". Columns found: ",
      paste(names(fred_raw), collapse = ", ")
    )
  }

  fred_raw |>
    transmute(
      date = .data[[date_column]],
      value = .data[[series_id]]
    ) |>
    mutate(
      date = as_date(date),
      value = as.numeric(value),
      series_id = series_id
    ) |>
    filter(date >= analysis_start, date <= analysis_end)
}

# =============================================================================
# EXTERNAL ETL 2: FRED ECONOMIC INDICATORS
# =============================================================================
# MORTGAGE30US is weekly, so its monthly value is the arithmetic mean of the
# weekly observations that fall in that month. USREC is already monthly.
# ATNHPIUS37964Q is the quarterly FHFA All-Transactions HPI for the
# Philadelphia metropolitan division. Joining it by calendar quarter avoids
# pretending that the quarterly source has independent monthly observations.

mortgage_rate_weekly <- read_fred_series("MORTGAGE30US", refresh_external)
recession_monthly <- read_fred_series("USREC", refresh_external)
philly_hpi_quarterly <- read_fred_series("ATNHPIUS37964Q", refresh_external)

mortgage_rate_monthly <- mortgage_rate_weekly |>
  mutate(yr_mo = floor_date(date, "month")) |>
  summarise(mortgage_rate_30y = mean(value, na.rm = TRUE), .by = yr_mo)

recession_monthly <- recession_monthly |>
  transmute(
    yr_mo = floor_date(date, "month"),
    recession_flag = as.integer(value)
  )

philly_hpi_quarterly <- philly_hpi_quarterly |>
  transmute(
    quarter = floor_date(date, "quarter"),
    philly_fhfa_hpi = value
  )

dim_econ_indicators <- tibble(
  yr_mo = seq.Date(analysis_start, floor_date(analysis_end, "month"), by = "month")
) |>
  mutate(quarter = floor_date(yr_mo, "quarter")) |>
  left_join(mortgage_rate_monthly, by = "yr_mo") |>
  left_join(recession_monthly, by = "yr_mo") |>
  left_join(philly_hpi_quarterly, by = "quarter") |>
  arrange(yr_mo) |>
  mutate(
    mortgage_rate_change_12m = mortgage_rate_30y - lag(mortgage_rate_30y, 12),
    philly_hpi_yoy = philly_fhfa_hpi / lag(philly_fhfa_hpi, 12) - 1
  )

stopifnot(
  nrow(dim_econ_indicators) == length(seq.Date(
    analysis_start,
    floor_date(analysis_end, "month"),
    by = "month"
  )),
  !anyDuplicated(dim_econ_indicators$yr_mo)
)

write_csv(dim_econ_indicators, file.path(external_dir, "dim_econ_indicators.csv"))

# =============================================================================
# EXTERNAL ETL 3: CONSISTENT FHFA PEER-CITY PRICE BENCHMARK
# =============================================================================
# These five quarterly FHFA indexes use the same All-Transactions methodology,
# making them more comparable than mixing unrelated city-level price sources.
# Each series is rebased to its observation nearest 2000 Q1 = 100 so the chart
# compares relative appreciation rather than different original index bases.

peer_fhfa_series <- tribble(
  ~city,         ~series_id,
  "Philadelphia", "ATNHPIUS37964Q",
  "Baltimore",    "ATNHPIUS12580Q",
  "Pittsburgh",   "ATNHPIUS38300Q",
  "Cleveland",    "ATNHPIUS17460Q",
  "Detroit",      "ATNHPIUS19804Q"
)

fact_quarterly_peer_hpi <- pmap_dfr(peer_fhfa_series, function(city, series_id) {
  read_fred_series(series_id, refresh_external) |>
    transmute(
      quarter = floor_date(date, "quarter"),
      city = city,
      series_id = series_id,
      hpi = value
    )
}) |>
  arrange(city, quarter) |>
  mutate(
    baseline_hpi = hpi[which.min(abs(quarter - as_date("2000-01-01")))],
    hpi_index_2000 = 100 * hpi / baseline_hpi,
    .by = city
  ) |>
  select(-baseline_hpi)

write_csv(
  fact_quarterly_peer_hpi,
  file.path(external_dir, "fact_quarterly_peer_hpi.csv")
)

# =============================================================================
# EXTERNAL ETL 4: OPTIONAL ZILLOW MONTHLY PEER DATA
# =============================================================================
# Zillow supplies monthly ZHVI and sales-count nowcasts. The paths below are
# the public Research CSV paths as of this project's build. If Zillow changes a
# path, download the equivalent Metro CSV manually into external_data/raw using
# the destination filename below and rerun this script without refresh enabled.

zillow_sources <- tribble(
  ~metric, ~url, ~destination,
  "zhvi",
  paste0(
    "https://files.zillowstatic.com/research/public_csvs/zhvi/",
    "Metro_zhvi_uc_sfrcondo_tier_0.33_0.67_sm_sa_month.csv"
  ),
  file.path(external_raw_dir, "zillow_metro_zhvi.csv"),
  "sales_count",
  paste0(
    "https://files.zillowstatic.com/research/public_csvs/sales_count_now/",
    "Metro_sales_count_now_uc_sfrcondo_month.csv"
  ),
  file.path(external_raw_dir, "zillow_metro_sales_count.csv")
)

zillow_sources <- zillow_sources |>
  mutate(
    local_path = map2_chr(
      url,
      destination,
      ~ download_cached(.x, .y, refresh_external, required = FALSE)
    )
  )

peer_region_names <- c(
  "Philadelphia, PA",
  "Baltimore-Columbia-Towson, MD",
  "Pittsburgh, PA",
  "Cleveland-Elyria, OH",
  "Detroit-Warren-Dearborn, MI"
)

read_zillow_metric <- function(path, metric_name) {
  if (is.na(path) || !file.exists(path)) {
    return(tibble())
  }

  zillow_raw <- tryCatch(
    read_csv(path, show_col_types = FALSE),
    error = function(e) {
      warning(
        "Cached Zillow file could not be parsed and will be skipped: ",
        path,
        "\n",
        conditionMessage(e)
      )
      NULL
    }
  )

  if (is.null(zillow_raw)) {
    return(tibble())
  }

  zillow_raw |>
    filter(RegionName %in% peer_region_names) |>
    pivot_longer(
      cols = matches("^\\d{4}-\\d{2}-\\d{2}$"),
      names_to = "yr_mo",
      values_to = "value"
    ) |>
    transmute(
      yr_mo = floor_date(as_date(yr_mo), "month"),
      city = str_remove(RegionName, ", [A-Z-]+$"),
      metric = metric_name,
      value = as.numeric(value)
    ) |>
    filter(yr_mo >= analysis_start, yr_mo <= analysis_end) |>
    arrange(city, metric, yr_mo) |>
    mutate(
      first_value = first(value[!is.na(value)], default = NA_real_),
      indexed_value = 100 * value / first_value,
      .by = c(city, metric)
    ) |>
    select(-first_value)
}

fact_monthly_peer_cities <- map2_dfr(
  zillow_sources$local_path,
  zillow_sources$metric,
  read_zillow_metric
)

if (nrow(fact_monthly_peer_cities) > 0) {
  write_csv(
    fact_monthly_peer_cities,
    file.path(external_dir, "fact_monthly_peer_cities.csv")
  )
} else {
  message(
    "Zillow monthly files were not available. FHFA peer HPI was created; ",
    "monthly peer-city sales benchmarking remains optional until the Zillow ",
    "Metro CSVs are downloaded."
  )
}

# =============================================================================
# EXTERNAL ETL 5: SOURCE CATALOG AND COMPACT VALIDATION
# =============================================================================
# This catalog travels with the exports so every modeled field can be traced to
# an authoritative series and its transformation.

source_catalog <- tribble(
  ~output_field, ~source, ~series_or_file, ~frequency, ~transformation, ~source_url,
  "mortgage_rate_30y", "FRED / Freddie Mac", "MORTGAGE30US", "weekly",
  "Mean of weekly observations within each month",
  "https://fred.stlouisfed.org/series/MORTGAGE30US",
  "recession_flag", "FRED / NBER", "USREC", "monthly",
  "Used as published (1 = recession, 0 = expansion)",
  "https://fred.stlouisfed.org/series/USREC",
  "philly_fhfa_hpi", "FRED / FHFA", "ATNHPIUS37964Q", "quarterly",
  "Quarter value joined to all three months in that quarter",
  "https://fred.stlouisfed.org/series/ATNHPIUS37964Q",
  "peer_hpi", "FRED / FHFA", "Five metro/MSAD series", "quarterly",
  "Rebased to nearest available 2000 Q1 observation = 100",
  "https://fred.stlouisfed.org/",
  "zhvi", "Zillow Research", "Metro ZHVI CSV", "monthly",
  "Optional; indexed to each city's first nonmissing project observation",
  "https://www.zillow.com/research/data/",
  "sales_count", "Zillow Research", "Metro sales-count nowcast CSV", "monthly",
  "Optional; indexed to each city's first nonmissing project observation",
  "https://www.zillow.com/research/data/"
)

write_csv(source_catalog, file.path(external_dir, "source_catalog.csv"))

external_etl_summary <- tibble(
  output = c(
    "dim_econ_indicators",
    "fact_quarterly_peer_hpi",
    "fact_monthly_peer_cities"
  ),
  rows = c(
    nrow(dim_econ_indicators),
    nrow(fact_quarterly_peer_hpi),
    nrow(fact_monthly_peer_cities)
  )
)

external_etl_summary
