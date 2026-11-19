# =============================================================================
# 13. EVICTION FILINGS AND REDFIN MARKET TIGHTNESS
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Builds the renter-instability signal and the inventory / days-on-market
#   series, both indexed to a comparable baseline.
# INPUTS
#   external_data/raw/week05_eviction_pa_monthly.csv  (Eviction Lab v3.0)
#   external_data/acs_zcta_vulnerability.csv
#   external_data/raw/redfin_zip_market_tracker_philadelphia.tsv
# OUTPUTS
#   tableau_data/week05_eviction_monthly.csv
#   tableau_data/week05_eviction_annual_zip.csv
#   tableau_data/week05_eviction_rate_case_studies_city.csv
#   tableau_data/week05_redfin_market_signals.csv
#   visualizations/week05_eviction_filing_index_dashboard.png
#   visualizations/week05_eviction_filing_rate.png
#   visualizations/week05_redfin_inventory_dom.png
# RUNS AFTER   09
# NOTES        Set options(bsan.refresh_week05_eviction = TRUE) to re-download.
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)
source(file.path(code_dir, "00_plot_theme.R"))

# =============================================================================
# WEEK 05: EVICTION FILINGS, INVENTORY, AND DAYS-ON-MARKET SIGNALS
# =============================================================================
# ABSTRACT
# This script adds two mechanisms that Week 4 could not test: renter instability
# and market tightness. Eviction Lab filings are compared with each ZIP's own
# pre-pandemic monthly baseline; Redfin inventory and median days on market are
# summarized from quarterly observations. Filings are court actions rather than
# completed evictions, and inventory/days on market are market signals rather
# than identified causes of transaction decline. The outputs strengthen policy
# targeting while retaining those limits.

# =============================================================================
# 1. SETTINGS, SOURCES, AND DEFINITIONS
# =============================================================================
# Caption: Use the public Pennsylvania ZIP-level file because the Philadelphia
# city extract is tract-level and cannot be joined directly to postal ZIPs.

selected_zips <- c("19132", "19143")
eviction_path <- file.path("external_data", "raw", "week05_eviction_pa_monthly.csv")
redfin_path <- file.path(
  "external_data", "raw", "redfin_zip_market_tracker_philadelphia.tsv"
)
vulnerability_path <- file.path("external_data", "acs_zcta_vulnerability.csv")
eviction_url <- paste0(
  "https://dev.evictionlab.org/uploads/",
  "pennsylvania_monthly_2020_2021.csv"
)
refresh_eviction <- isTRUE(getOption("bsan.refresh_week05_eviction", FALSE))
dir.create(dirname(eviction_path), recursive = TRUE, showWarnings = FALSE)

# Caption: The source retains a legacy filename while adding newer monthly
# rows. Download only when missing or explicitly refreshed; raw data stay out
# of Git and the clean analytical exports remain versionable.
if (!file.exists(eviction_path) || refresh_eviction) {
  download.file(eviction_url, eviction_path, mode = "wb", quiet = TRUE)
}

if (any(!file.exists(c(eviction_path, redfin_path, vulnerability_path)))) {
  stop("Missing Eviction Lab, Redfin, or ACS input; see paths at top of script.")
}

dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# 2. CLEAN EVICTION LAB ZIP-LEVEL FILINGS
# =============================================================================
# Caption: In the source schema `filings_2020` is retained for backward
# compatibility but contains the observed filing count for each listed month,
# including 2021 onward. Rename it immediately to prevent misinterpretation.

eviction_monthly <- read_csv(
  eviction_path,
  col_types = cols(GEOID = col_character()),
  show_col_types = FALSE
) |>
  transmute(
    geography_type = type,
    zip5 = GEOID,
    month = lubridate::my(month),
    filings = filings_2020,
    source_comparison_average = filings_avg,
    prepandemic_baseline = filings_avg_prepandemic_baseline,
    last_updated
  ) |>
  filter(
    geography_type == "ZIP Code",
    str_detect(zip5, "^191[0-9]{2}$"),
    !is.na(month)
  ) |>
  mutate(
    year = lubridate::year(month),
    filing_index_vs_prepandemic = filings / prepandemic_baseline
  )

# Caption: Create a pooled Philadelphia-191xx comparison by summing filings and
# baseline counts before calculating the index.
eviction_city_monthly <- eviction_monthly |>
  summarise(
    filings = sum(filings, na.rm = TRUE),
    prepandemic_baseline = if_else(
      all(is.na(prepandemic_baseline)),
      NA_real_,
      sum(prepandemic_baseline, na.rm = TRUE)
    ),
    .by = month
  ) |>
  mutate(
    zip5 = "Philadelphia 191xx total",
    year = lubridate::year(month),
    filing_index_vs_prepandemic = filings / prepandemic_baseline
  )

eviction_panel <- bind_rows(
  eviction_monthly |>
    filter(zip5 %in% selected_zips) |>
    select(month, year, zip5, filings, prepandemic_baseline, filing_index_vs_prepandemic),
  eviction_city_monthly
)

# Caption: For the latest complete year, normalize filings by estimated renter-
# occupied households. ACS 2024 is a five-year estimate, so this rate is a
# contextual denominator rather than a same-year administrative population.

renter_denominators <- read_csv(
  vulnerability_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(year == 2024L) |>
  transmute(
    zip5,
    estimated_renter_households = occupied_housing_units * renter_share
  )

eviction_annual <- eviction_monthly |>
  filter(year %in% 2020:2025) |>
  summarise(
    filings = sum(filings, na.rm = TRUE),
    prepandemic_baseline = sum(prepandemic_baseline, na.rm = TRUE),
    months_observed = n_distinct(month),
    .by = c(zip5, year)
  ) |>
  left_join(renter_denominators, by = "zip5") |>
  mutate(
    filing_index_vs_prepandemic = filings / prepandemic_baseline,
    filings_per_1000_estimated_renter_households =
      1000 * filings / estimated_renter_households,
    denominator_caution = paste(
      "2024 ACS 5-year renter-household estimate; filings are cases,",
      "not unique households or completed evictions"
    )
  )

# Caption: Pool all Philadelphia 191xx ZIPs after joining the same ACS renter-
# household denominator. This creates a directly comparable city benchmark.
# ZIPs without an ACS renter estimate have zero filings in the current source,
# so excluding their missing denominators does not remove observed filings.

eviction_city_annual <- eviction_annual |>
  filter(!is.na(estimated_renter_households)) |>
  summarise(
    filings = sum(filings, na.rm = TRUE),
    estimated_renter_households = sum(
      estimated_renter_households,
      na.rm = TRUE
    ),
    months_observed = min(months_observed, na.rm = TRUE),
    .by = year
  ) |>
  mutate(
    zip5 = "Philadelphia",
    filings_per_1000_estimated_renter_households =
      1000 * filings / estimated_renter_households,
    denominator_caution = paste(
      "Pooled 2024 ACS 5-year renter-household estimates; filings are cases,",
      "not unique households or completed evictions"
    )
  )

eviction_rate_panel <- bind_rows(
  eviction_annual |>
    filter(zip5 %in% selected_zips),
  eviction_city_annual
)

# =============================================================================
# 3. CLEAN REDFIN INVENTORY AND DAYS ON MARKET
# =============================================================================
# Caption: Use 90-day All Residential rows to avoid mixing monthly, quarterly,
# and annual windows or different property-type series.

redfin_market <- read_tsv(
  redfin_path,
  col_types = cols(.default = col_guess()),
  show_col_types = FALSE
) |>
  transmute(
    period_end = as.Date(PERIOD_END),
    year = lubridate::year(period_end),
    zip5 = str_extract(REGION, "[0-9]{5}"),
    property_type = PROPERTY_TYPE,
    period_duration = PERIOD_DURATION,
    homes_sold = HOMES_SOLD,
    inventory = INVENTORY,
    median_days_on_market = MEDIAN_DOM,
    months_of_supply = MONTHS_OF_SUPPLY
  ) |>
  filter(
    property_type == "All Residential",
    period_duration == 90,
    str_detect(zip5, "^191[0-9]{2}$"),
    year %in% 2015:2025
  )

# Caption: Calculate annual market signals for each ZIP and the median across
# observed Philadelphia ZIPs. Do not sum quarterly inventory snapshots.

redfin_zip_annual <- redfin_market |>
  summarise(
    quarterly_observations = n(),
    mean_inventory = mean(inventory, na.rm = TRUE),
    mean_median_days_on_market = mean(median_days_on_market, na.rm = TRUE),
    mean_months_of_supply = mean(months_of_supply, na.rm = TRUE),
    annual_homes_sold = sum(homes_sold, na.rm = TRUE),
    .by = c(zip5, year)
  )

redfin_city_annual <- redfin_zip_annual |>
  summarise(
    quarterly_observations = median(quarterly_observations, na.rm = TRUE),
    mean_inventory = median(mean_inventory, na.rm = TRUE),
    mean_median_days_on_market = median(mean_median_days_on_market, na.rm = TRUE),
    mean_months_of_supply = median(mean_months_of_supply, na.rm = TRUE),
    annual_homes_sold = median(annual_homes_sold, na.rm = TRUE),
    .by = year
  ) |>
  mutate(zip5 = "Philadelphia ZIP median")

redfin_market_panel <- bind_rows(
  redfin_zip_annual,
  redfin_city_annual
) |>
  mutate(
    geography_type = if_else(
      zip5 == "Philadelphia ZIP median",
      "Philadelphia benchmark",
      "ZIP code"
    ),
    default_dashboard_selection = zip5 %in% selected_zips
  )

write_csv(eviction_panel, "tableau_data/week05_eviction_monthly.csv")
write_csv(eviction_annual, "tableau_data/week05_eviction_annual_zip.csv")
write_csv(
  eviction_rate_panel,
  "tableau_data/week05_eviction_rate_case_studies_city.csv"
)
write_csv(redfin_market_panel, "tableau_data/week05_redfin_market_signals.csv")

# =============================================================================
# VISUALIZATION 5 — ANNUAL EVICTION FILINGS PER 1,000 RENTER HOUSEHOLDS
# =============================================================================
# Caption: Present annual filing rates on a common, intuitive scale. The fixed
# 2024 ACS renter-household denominator makes differences in ZIP size less
# dominant while preserving the important distinction between filings and
# completed evictions.

eviction_rate_plot_data <- eviction_rate_panel |>
  filter(months_observed == 12L) |>
  mutate(
    geography = factor(
      zip5,
      levels = c("19132", "19143", "Philadelphia")
    )
  )

eviction_plot <- ggplot(
  eviction_rate_plot_data,
  aes(
    year,
    filings_per_1000_estimated_renter_households,
    color = geography,
    group = geography
  )
) +
  geom_line(linewidth = 1.35) +
  geom_point(size = 3.4) +
  geom_text(
    data = filter(eviction_rate_plot_data, year == max(year)),
    aes(
      label = paste0(
        geography,
        ": ",
        scales::number(
          filings_per_1000_estimated_renter_households,
          accuracy = 0.1
        )
      )
    ),
    hjust = -0.08,
    fontface = "bold",
    size = 4.2,
    show.legend = FALSE
  ) +
  scale_color_manual(values = c(
    "19132" = "#D95F0E",
    "19143" = "#08519C",
    "Philadelphia" = "#4D4D4D"
  )) +
  scale_x_continuous(
    breaks = 2020:2025,
    expand = expansion(mult = c(0.02, 0.20))
  ) +
  scale_y_continuous(
    labels = scales::label_number(accuracy = 1),
    expand = expansion(mult = c(0.04, 0.10))
  ) +
  labs(
    title = "Eviction Filing Rates Peaked in 2022",
    subtitle = paste(
      "Annual court filings per 1,000 estimated renter households;",
      "Philadelphia provides the common benchmark"
    ),
    x = NULL,
    y = "Filings per 1,000 estimated renter households",
    color = NULL,
    caption = paste(
      "Source: Eviction Lab and 2024 ACS five-year estimates.",
      "Filings are court cases, not completed evictions or unique households."
    )
  ) +
  week05_presentation_theme() +
  theme(
    legend.position = "none",
    axis.text = element_text(size = 13, face = "bold"),
    axis.title.y = element_text(size = 14, face = "bold")
  )

ggsave(
  "visualizations/week05_eviction_filing_rate.png",
  eviction_plot,
  width = 11,
  height = 7.2,
  dpi = 300
)

# Caption: Retain the rolling pre-pandemic index as a secondary dashboard
# diagnostic for monitoring recent direction; it is no longer the main class
# presentation chart.

eviction_plot_data <- eviction_panel |>
  arrange(zip5, month) |>
  mutate(
    rolling_filings = slider::slide_dbl(filings, sum, .before = 11, .complete = TRUE),
    rolling_baseline = slider::slide_dbl(
      prepandemic_baseline, sum, .before = 11, .complete = TRUE
    ),
    rolling_index = rolling_filings / rolling_baseline,
    .by = zip5
  )

eviction_rolling_plot <- ggplot(
  filter(eviction_plot_data, !is.na(rolling_index)),
  aes(month, rolling_index, color = zip5)
) +
  geom_hline(yintercept = 1, linetype = "dashed", linewidth = 1) +
  geom_line(linewidth = 1.25) +
  scale_color_manual(values = c(
    "19132" = "#D95F0E",
    "19143" = "#08519C",
    "Philadelphia 191xx total" = "#4D4D4D"
  )) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "Eviction Filings Relative to the Pre-Pandemic Baseline",
    subtitle = "Rolling 12-month filing count divided by rolling baseline count",
    x = NULL,
    y = "Share of pre-pandemic baseline",
    color = NULL,
    caption = paste(
      "Eviction Lab filings are court cases, not completed evictions or unique households.",
      "Geocoding gaps can undercount ZIP-level filings."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_eviction_filing_index_dashboard.png",
  eviction_rolling_plot,
  width = 11,
  height = 7.2,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 6 — INVENTORY AND DAYS ON MARKET
# =============================================================================
# Caption: Compare the case studies with the Philadelphia ZIP median; these
# measures can distinguish market tightness from a simple demand-collapse story.

market_plot_data <- redfin_market_panel |>
  select(zip5, year, mean_inventory, mean_median_days_on_market) |>
  pivot_longer(
    c(mean_inventory, mean_median_days_on_market),
    names_to = "measure",
    values_to = "value"
  ) |>
  mutate(measure = recode(
    measure,
    mean_inventory = "Average listed inventory",
    mean_median_days_on_market = "Average quarterly median days on market"
  ))

market_signal_plot <- ggplot(
  market_plot_data,
  aes(year, value, color = zip5)
) +
  geom_line(linewidth = 1.25) +
  geom_point(size = 2.4) +
  facet_wrap(vars(measure), ncol = 1, scales = "free_y") +
  scale_color_manual(values = c(
    "19132" = "#D95F0E",
    "19143" = "#08519C",
    "Philadelphia ZIP median" = "#4D4D4D"
  )) +
  scale_x_continuous(breaks = seq(2015, 2025, 2)) +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(
    title = "Market Tightness Signals for the Case-Study ZIPs",
    subtitle = "Quarterly Redfin All Residential observations summarized annually",
    x = NULL,
    y = NULL,
    color = NULL,
    caption = paste(
      "Low inventory and short market time are consistent with tight supply,",
      "but do not by themselves explain who could afford to buy."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_redfin_inventory_dom.png",
  market_signal_plot,
  width = 11,
  height = 8,
  dpi = 300
)

# =============================================================================
# 6. PRINT WEEK 5 EVICTION/MARKET OUTPUTS TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(eviction_plot)
  print(market_signal_plot)
}

