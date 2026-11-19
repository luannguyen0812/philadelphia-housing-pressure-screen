# =============================================================================
# 12. PRICE-GROWTH VERSUS INCOME-GROWTH ENDPOINTS
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Compares two non-overlapping ACS windows against Redfin price change for
#   every qualifying ZIP, and records which measures are still unavailable.
# INPUTS
#   tableau_data/fact_zip_price_income.csv
#   tableau_data/week04_zip_selection_scorecard.csv
# OUTPUTS
#   tableau_data/week05_neighborhood_change_endpoints.csv
#   tableau_data/week05_neighborhood_change_availability.csv
#   visualizations/week05_price_income_endpoint_change.png
# RUNS AFTER   09
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)
source(file.path(code_dir, "00_plot_theme.R"))

# =============================================================================
# WEEK 05: NON-OVERLAPPING ACS INCOME AND MARKET-CHANGE COMPARISON
# =============================================================================
# ABSTRACT
# This script begins the neighborhood-change component with two non-overlapping
# ACS five-year endpoints: 2010-2014 and 2020-2024. It compares median household
# income change with Redfin median-sale-price change for every qualifying ZIP
# and highlights the five presentation ZIPs. A widening price-versus-income gap
# is evidence of affordability pressure, not sufficient proof of gentrification
# or displacement. Education, tenure, poverty, age, rent, and burden endpoint
# changes remain a documented extension requiring the historical ACS tables.

# =============================================================================
# 1. LOAD NON-OVERLAPPING ENDPOINTS
# =============================================================================
# Caption: The final-year labels 2014 and 2024 represent non-overlapping ACS
# periods, avoiding the dependence problem in adjacent five-year releases.

affordability_path <- file.path("tableau_data", "fact_zip_price_income.csv")
scorecard_path <- file.path("tableau_data", "week04_zip_selection_scorecard.csv")
display_zips <- c("19132", "19143", "19122", "19138", "19119")

if (any(!file.exists(c(affordability_path, scorecard_path)))) {
  stop("Missing affordability or scorecard input.")
}

dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

qualifying_zips <- read_csv(
  scorecard_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(coverage_gate_pass) |>
  pull(zip5)

endpoint_panel <- read_csv(
  affordability_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(
    price_source == "Redfin",
    zip5 %in% qualifying_zips,
    year %in% c(2014L, 2024L)
  ) |>
  select(
    zip5,
    year,
    median_sale_price = median_property_price,
    median_household_income,
    median_household_income_moe,
    income_moe_pct,
    acs_estimate_period
  ) |>
  pivot_wider(
    names_from = year,
    values_from = c(
      median_sale_price,
      median_household_income,
      median_household_income_moe,
      income_moe_pct,
      acs_estimate_period
    ),
    names_sep = "_"
  ) |>
  mutate(
    price_change_pct = median_sale_price_2024 / median_sale_price_2014 - 1,
    income_change_pct =
      median_household_income_2024 / median_household_income_2014 - 1,
    affordability_growth_gap = price_change_pct - income_change_pct,
    price_to_income_2014 =
      median_sale_price_2014 / median_household_income_2014,
    price_to_income_2024 =
      median_sale_price_2024 / median_household_income_2024,
    ratio_change = price_to_income_2024 / price_to_income_2014 - 1,
    endpoint_income_moe_warning =
      income_moe_pct_2014 > 0.20 | income_moe_pct_2024 > 0.20,
    display_group = case_when(
      zip5 == "19132" ~ "19132",
      zip5 == "19143" ~ "19143",
      zip5 %in% display_zips ~ "Comparison ZIP",
      TRUE ~ "Other qualifying ZIP"
    )
  )

# Caption: Export the measured endpoint comparison and an explicit availability
# register so unbuilt demographic dimensions cannot be mistaken for null results.

neighborhood_change_availability <- tribble(
  ~measure, ~endpoint_status, ~week05_use,
  "Median household income", "2010-2014 and 2020-2024 available", "Implemented",
  "Median sale price", "2014 and 2024 Redfin available", "Implemented",
  "Educational attainment", "Historical ACS table not cached", "Pending Census-key/bulk build",
  "Tenure", "2020-2024 available; historical endpoint not cached", "Pending Census-key/bulk build",
  "Poverty", "2020-2024 available; historical endpoint not cached", "Pending Census-key/bulk build",
  "Senior share", "2020-2024 available; historical endpoint not cached", "Pending Census-key/bulk build",
  "Median gross rent and burden", "2020-2024 available; historical endpoint not cached", "Pending Census-key/bulk build"
)

write_csv(endpoint_panel, "tableau_data/week05_neighborhood_change_endpoints.csv")
write_csv(
  neighborhood_change_availability,
  "tableau_data/week05_neighborhood_change_availability.csv"
)

# =============================================================================
# VISUALIZATION 10 — PRICE GROWTH VERSUS LOCAL INCOME GROWTH
# =============================================================================
# Caption: A 45-degree reference line distinguishes ZIPs where prices grew
# faster than local household income from those where income kept pace.

change_plot <- ggplot(
  endpoint_panel,
  aes(income_change_pct, price_change_pct)
) +
  geom_abline(slope = 1, intercept = 0, linewidth = 1.1, linetype = "dashed") +
  geom_point(aes(color = display_group), size = 3.8, alpha = 0.9) +
  # Caption: The comparison ZIPs keep a plain label; the two case studies carry
  # their price-to-income endpoints, because that ratio is what the growth gap
  # actually moves and it is the number quoted on the case-study slides.
  geom_text(
    data = filter(endpoint_panel, zip5 %in% setdiff(display_zips, c("19132", "19143"))),
    aes(label = zip5),
    nudge_y = 0.08,
    fontface = "bold",
    size = 4,
    show.legend = FALSE
  ) +
  geom_text(
    data = filter(endpoint_panel, zip5 %in% c("19132", "19143")) |>
      mutate(label = paste0(
        zip5, "   ",
        sprintf("%.2f\u00d7 \u2192 %.2f\u00d7", price_to_income_2014, price_to_income_2024)
      )),
    aes(label = label),
    hjust = 1,
    nudge_x = -0.045,
    fontface = "bold",
    size = 3.6,
    show.legend = FALSE
  ) +
  scale_color_manual(values = c(
    "19132" = "#D95F0E",
    "19143" = "#08519C",
    "Comparison ZIP" = "#636363",
    "Other qualifying ZIP" = "#BDBDBD"
  )) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "Did Sale Prices Outrun Local Household Income?",
    subtitle = "Non-overlapping ACS endpoints: 2010-2014 versus 2020-2024",
    x = "Median household-income change",
    y = "Redfin median-sale-price change",
    color = NULL,
    caption = paste(
      "Dashed line: price and income grew at the same rate, so the ratio held.",
      "Above it, the ratio rose. Affordability pressure, not proof of displacement."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_price_income_endpoint_change.png",
  change_plot,
  width = 11,
  height = 7.2,
  dpi = 300,
  bg = "white",
  device = ragg::agg_png
)

if (interactive()) print(change_plot)
filter(endpoint_panel, zip5 %in% c("19132", "19143"))

