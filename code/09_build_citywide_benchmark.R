# =============================================================================
# 09. BUILD THE 37-ZIP CITYWIDE BENCHMARK
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Puts every qualifying ZIP on one comparable footing: price growth,
#   vulnerability percentile, transaction change, and sales per 1,000 occupied
#   units, plus the median-ZIP and pooled City benchmarks.
# INPUTS
#   tableau_data/week04_zip_selection_scorecard.csv
#   tableau_data/fact_zip_price_income.csv
#   external_data/acs_zcta_vulnerability.csv
# OUTPUTS
#   tableau_data/week05_citywide_zip_benchmark.csv
#   tableau_data/week05_citywide_summary.csv
#   visualizations/week05_citywide_selection_context.png
#   visualizations/week05_price_growth_transaction_change.png
# RUNS AFTER   08
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)
source(file.path(code_dir, "00_plot_theme.R"))

# =============================================================================
# WEEK 05: CITYWIDE BENCHMARKS AND TWO-ZIP CONTEXT
# =============================================================================
# ABSTRACT
# This script places 19132 and 19143 in the full set of qualifying Philadelphia
# ZIP/ZCTAs. It compares 2015-2024 Redfin median-price growth, 2024 ACS resident
# vulnerability, and the change in eligible arm's-length RTT sale activity from
# 2015-2017 to 2022-2024. It answers the professor's request for a Philadelphia
# baseline and comparator ZIPs. These are descriptive associations: a price-
# growth/transaction relationship cannot establish affordability constraints,
# displacement, or causality by itself.
#
# Run after the Week 4 ETL and analysis scripts.

# =============================================================================
# 1. SETTINGS, PATHS, AND SHARED PRESENTATION THEME
# =============================================================================
# Caption: Keep the selected pair, comparator ZIPs, source files, and shared
# projector-readable visual settings explicit and auditable.

selected_zips <- c("19132", "19143")
comparison_zips <- c("19122", "19138", "19119")
display_zips <- c(selected_zips, comparison_zips)

# Caption: One colour code for the whole project. 19132 is orange and 19143 is
# dark blue in every deck chart, the dashboard worksheet and the map. The three
# named comparators take the map's comparison grey; the rest of the qualifying
# universe is a lighter grey so it reads as background, not as a third finding.
zip_palette <- c(
  "19132 \u00b7 case study"                = "#D95F0E",
  "19143 \u00b7 case study"                = "#0E4E8F",
  "Named comparison (19122, 19119, 19138)" = "#737980",
  "Other qualifying ZIP/ZCTA"              = "#B4BCC3"
)
zip_levels <- names(zip_palette)

paths <- list(
  affordability = file.path("tableau_data", "fact_zip_price_income.csv"),
  scorecard = file.path("tableau_data", "week04_zip_selection_scorecard.csv"),
  vulnerability = file.path("external_data", "acs_zcta_vulnerability.csv")
)

missing_inputs <- names(paths)[!file.exists(unlist(paths))]
if (length(missing_inputs)) {
  stop("Missing Week 5 input(s): ", paste(missing_inputs, collapse = ", "))
}

dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# 2. LOAD THE FULL QUALIFYING-ZIP UNIVERSE
# =============================================================================
# Caption: Retain every ZIP that passed the Week 4 coverage gate; the five
# presentation ZIPs are labels within this citywide analytical universe.

scorecard <- read_csv(paths$scorecard, col_types = cols(zip5 = col_character())) |>
  filter(coverage_gate_pass)

affordability <- read_csv(
  paths$affordability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)

vulnerability_2024 <- read_csv(
  paths$vulnerability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(year == 2024L) |>
  select(zip5, occupied_housing_units, renter_share)

# =============================================================================
# 3. CALCULATE COMPARABLE TRANSACTION-ACTIVITY CHANGE
# =============================================================================
# Caption: Average three complete years at each endpoint so a single unusual
# year does not determine the result. Counts use the same eligible single-
# property, non-nominal deed definition used in Week 4.

transaction_periods <- affordability |>
  filter(
    price_source == "Philadelphia RTT",
    year %in% c(2015:2017, 2022:2024),
    zip5 %in% scorecard$zip5
  ) |>
  mutate(period = if_else(year <= 2017L, "2015-2017", "2022-2024")) |>
  summarise(
    annual_eligible_sales = mean(n_eligible_sales, na.rm = TRUE),
    years_observed = n_distinct(year),
    .by = c(zip5, period)
  ) |>
  pivot_wider(
    names_from = period,
    values_from = c(annual_eligible_sales, years_observed),
    names_sep = "_"
  ) |>
  rename_with(~ str_replace_all(.x, "-", "_")) |>
  mutate(
    transaction_change_pct =
      annual_eligible_sales_2022_2024 / annual_eligible_sales_2015_2017 - 1
  )

# Caption: Join market growth, vulnerability, transaction change, and the 2024
# occupied-unit denominator into one dashboard-ready benchmarking table.
week05_zip_benchmark <- scorecard |>
  select(
    zip5,
    redfin_2015_2024_cagr,
    vulnerability_percentile,
    market_growth_rank,
    vulnerability_rank
  ) |>
  left_join(transaction_periods, by = "zip5") |>
  left_join(vulnerability_2024, by = "zip5") |>
  mutate(
    sales_per_1000_occupied_2015_2017 =
      1000 * annual_eligible_sales_2015_2017 / occupied_housing_units,
    sales_per_1000_occupied_2022_2024 =
      1000 * annual_eligible_sales_2022_2024 / occupied_housing_units,
    case_group = case_when(
      zip5 %in% selected_zips ~ "Detailed case study",
      zip5 %in% comparison_zips ~ "Named comparison",
      TRUE ~ "Other qualifying ZIP/ZCTA"
    ),
    default_dashboard_selection = zip5 %in% selected_zips,
    dashboard_selection_order = case_when(
      zip5 == "19132" ~ 1L,
      zip5 == "19143" ~ 2L,
      TRUE ~ 3L
    )
  ) |>
  arrange(desc(redfin_2015_2024_cagr))

# Caption: Report both a median-ZIP baseline and an aggregate activity rate.
# The former describes a typical qualifying ZIP; the latter pools denominators.
week05_city_benchmark <- week05_zip_benchmark |>
  summarise(
    geography = "Philadelphia qualifying ZIP/ZCTA benchmark",
    qualifying_zips = n(),
    median_price_cagr = median(redfin_2015_2024_cagr, na.rm = TRUE),
    median_vulnerability_percentile =
      median(vulnerability_percentile, na.rm = TRUE),
    median_transaction_change_pct =
      median(transaction_change_pct, na.rm = TRUE),
    pooled_sales_per_1000_occupied_2015_2017 =
      1000 * sum(annual_eligible_sales_2015_2017, na.rm = TRUE) /
      sum(occupied_housing_units, na.rm = TRUE),
    pooled_sales_per_1000_occupied_2022_2024 =
      1000 * sum(annual_eligible_sales_2022_2024, na.rm = TRUE) /
      sum(occupied_housing_units, na.rm = TRUE),
    spearman_price_growth_vs_transaction_change = cor(
      redfin_2015_2024_cagr,
      transaction_change_pct,
      method = "spearman",
      use = "complete.obs"
    )
  )

write_csv(week05_zip_benchmark, "tableau_data/week05_citywide_zip_benchmark.csv")
write_csv(week05_city_benchmark, "tableau_data/week05_citywide_summary.csv")

# Caption: Assign presentation colours on a separate plotting frame. The written
# benchmark CSV keeps its original columns and row order because the Week 6
# dashboard derives geography_sort from that row order. Rows are ordered so the
# named ZIPs are drawn on top of the grey context cloud.
plot_frame <- week05_zip_benchmark |>
  mutate(
    zip_group = case_when(
      zip5 == "19132" ~ zip_levels[1],
      zip5 == "19143" ~ zip_levels[2],
      zip5 %in% comparison_zips ~ zip_levels[3],
      TRUE ~ zip_levels[4]
    ),
    zip_group = factor(zip_group, levels = zip_levels)
  ) |>
  arrange(desc(as.integer(zip_group)))

# =============================================================================
# VISUALIZATION 1 — FULL PHILADELPHIA SELECTION CONTEXT
# =============================================================================
# Caption: Show the chosen ZIPs against all qualifying ZIPs, while labeling the
# three requested comparators and using the citywide medians as bold guides.

x_median <- median(plot_frame$redfin_2015_2024_cagr, na.rm = TRUE)
y_median <- median(plot_frame$vulnerability_percentile, na.rm = TRUE)

citywide_selection_plot <- ggplot(
  plot_frame,
  aes(redfin_2015_2024_cagr, vulnerability_percentile)
) +
  geom_vline(xintercept = x_median, linewidth = 1.15, linetype = "dashed") +
  geom_hline(yintercept = y_median, linewidth = 1.15, linetype = "dashed") +
  geom_point(aes(color = zip_group), size = 3.9) +
  # Caption: The two case-study ZIPs are drawn larger so they carry the eye at
  # projector distance; the comparators and the context cloud keep the base size.
  geom_point(
    data = filter(plot_frame, zip5 %in% selected_zips),
    aes(color = zip_group),
    size = 6.3,
    show.legend = FALSE
  ) +
  geom_text(
    data = filter(plot_frame, zip5 %in% display_zips),
    aes(label = zip5, color = zip_group),
    nudge_y = 0.025,
    fontface = "bold",
    size = 4,
    show.legend = FALSE
  ) +
  scale_color_manual(values = zip_palette, breaks = zip_levels, drop = FALSE) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "The Two Case Studies in Philadelphia Context",
    subtitle = "All qualifying ZIP/ZCTAs; dashed lines are citywide medians",
    x = "Redfin median-sale-price CAGR, 2015-2024",
    y = "2024 vulnerability composite percentile",
    color = NULL,
    caption = paste(
      "Vulnerability combines renter share, renter burden, poverty, and senior share.",
      "Screening identifies housing-pressure cases; it does not prove displacement."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_citywide_selection_context.png",
  citywide_selection_plot,
  width = 11,
  height = 7.2,
  dpi = 300,
  bg = "white",
  device = ragg::agg_png
)

# =============================================================================
# VISUALIZATION 2 — PRICE GROWTH VERSUS TRANSACTION CHANGE
# =============================================================================
# Caption: Test the proposed association across all qualifying ZIPs. The fitted
# line is descriptive and must not be described as a causal affordability test.

price_transaction_plot <- ggplot(
  plot_frame,
  aes(redfin_2015_2024_cagr, transaction_change_pct)
) +
  geom_hline(yintercept = 0, linewidth = 0.9, linetype = "dashed") +
  geom_smooth(method = "lm", se = TRUE, color = "#636363", fill = "#BDBDBD") +
  geom_point(aes(color = zip_group), size = 3.9) +
  geom_text(
    data = filter(plot_frame, zip5 %in% display_zips),
    aes(label = zip5, color = zip_group),
    nudge_y = 0.045,
    fontface = "bold",
    size = 4,
    show.legend = FALSE
  ) +
  scale_color_manual(values = zip_palette, breaks = zip_levels, drop = FALSE) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "Faster Price Growth Did Not Generally Mean Lower Sale Activity",
    subtitle = "Eligible annual sales: 2022-2024 average versus 2015-2017 average",
    x = "Redfin median-sale-price CAGR, 2015-2024",
    y = "Change in eligible arm's-length sale activity",
    color = NULL,
    caption = paste(
      "The line summarizes an ecological association across ZIP/ZCTAs.",
      "It does not identify why transaction activity changed."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_price_growth_transaction_change.png",
  price_transaction_plot,
  width = 11,
  height = 7.2,
  dpi = 300,
  bg = "white",
  device = ragg::agg_png
)

# =============================================================================
# 6. PRINT WEEK 5 CITYWIDE OUTPUTS TO THE R PLOT CANVAS
# =============================================================================
# Caption: Print both graphs when sourced interactively and expose summary
# objects for presentation review.

if (interactive()) {
  print(citywide_selection_plot)
  print(price_transaction_plot)
}
week05_city_benchmark
