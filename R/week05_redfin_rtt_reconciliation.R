library(tidyverse)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 05: REDFIN AND PHILADELPHIA RTT RECONCILIATION
# =============================================================================
# ABSTRACT
# Redfin and Philadelphia RTT do not observe identical sales. This script joins
# their annual ZIP summaries, compares price/activity direction and rank, and
# identifies disagreements rather than choosing whichever source makes the case
# studies look strongest. Redfin represents its market-tracker sample; the RTT
# proxy uses exact single-property DEED records after nominal, unknown-price,
# and high-outlier exclusions. Agreement supports robustness; disagreement is a
# result that constrains interpretation.

# =============================================================================
# 1. LOAD COMMON ZIP-YEAR OBSERVATIONS
# =============================================================================
# Caption: Restrict the reconciliation to complete 2015-2024 years and ZIPs that
# passed the Week 4 coverage gate.

affordability_path <- file.path("tableau_data", "fact_zip_price_income.csv")
scorecard_path <- file.path("tableau_data", "week04_zip_selection_scorecard.csv")
selected_zips <- c("19132", "19143")

if (any(!file.exists(c(affordability_path, scorecard_path)))) {
  stop("Missing affordability or Week 4 scorecard input.")
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

source_panel <- read_csv(
  affordability_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(zip5 %in% qualifying_zips, year %in% 2015:2024) |>
  select(zip5, year, price_source, n_eligible_sales, median_property_price) |>
  pivot_wider(
    names_from = price_source,
    values_from = c(n_eligible_sales, median_property_price),
    names_glue = "{.value}_{price_source}"
  ) |>
  rename_with(~ str_replace_all(str_to_lower(.x), "[^a-z0-9]+", "_")) |>
  rename_with(~ str_remove(.x, "_$")) |>
  mutate(
    redfin_to_rtt_price_ratio =
      median_property_price_redfin /
      median_property_price_philadelphia_rtt,
    redfin_to_rtt_activity_ratio =
      n_eligible_sales_redfin /
      n_eligible_sales_philadelphia_rtt
  )

# =============================================================================
# 2. COMPARE TREND DIRECTION, GROWTH, AND RANK STABILITY
# =============================================================================
# Caption: Correlation measures co-movement, not equality. CAGR and ranks test
# whether a source switch changes which ZIPs appear fastest-growing.

source_reconciliation <- source_panel |>
  summarise(
    common_years = sum(complete.cases(
      median_property_price_redfin,
      median_property_price_philadelphia_rtt
    )),
    price_correlation = cor(
      median_property_price_redfin,
      median_property_price_philadelphia_rtt,
      use = "complete.obs"
    ),
    activity_correlation = cor(
      n_eligible_sales_redfin,
      n_eligible_sales_philadelphia_rtt,
      use = "complete.obs"
    ),
    median_redfin_to_rtt_price_ratio =
      median(redfin_to_rtt_price_ratio, na.rm = TRUE),
    .by = zip5
  )

source_growth <- source_panel |>
  filter(year %in% c(2015L, 2024L)) |>
  select(
    zip5,
    year,
    median_property_price_redfin,
    median_property_price_philadelphia_rtt
  ) |>
  pivot_wider(names_from = year, values_from = starts_with("median_property")) |>
  transmute(
    zip5,
    redfin_cagr_2015_2024 =
      (`median_property_price_redfin_2024` /
        `median_property_price_redfin_2015`)^(1 / 9) - 1,
    rtt_cagr_2015_2024 =
      (`median_property_price_philadelphia_rtt_2024` /
        `median_property_price_philadelphia_rtt_2015`)^(1 / 9) - 1
  ) |>
  mutate(
    redfin_growth_rank = min_rank(desc(redfin_cagr_2015_2024)),
    rtt_growth_rank = min_rank(desc(rtt_cagr_2015_2024)),
    absolute_rank_change = abs(redfin_growth_rank - rtt_growth_rank),
    selected_case = zip5 %in% selected_zips
  )

source_reconciliation <- source_reconciliation |>
  left_join(source_growth, by = "zip5") |>
  mutate(
    interpretation = case_when(
      price_correlation >= 0.8 ~ "Strong directional agreement; levels still differ",
      price_correlation >= 0.5 ~ "Moderate directional agreement; investigate sample differences",
      TRUE ~ "Weak directional agreement; do not treat sources as interchangeable"
    )
  )

write_csv(source_panel, "tableau_data/week05_redfin_rtt_annual.csv")
write_csv(source_reconciliation, "tableau_data/week05_redfin_rtt_reconciliation.csv")

# =============================================================================
# VISUALIZATION 9 — INDEXED REDFIN/RTT PRICE AND ACTIVITY COMPARISON
# =============================================================================
# Caption: Index each source to its own 2015 level. This tests trajectory while
# avoiding the false expectation that source levels and counts must be equal.

indexed_source_plot_data <- source_panel |>
  filter(zip5 %in% selected_zips) |>
  arrange(zip5, year) |>
  mutate(
    redfin_price_index = 100 * median_property_price_redfin /
      first(median_property_price_redfin),
    rtt_price_index = 100 * median_property_price_philadelphia_rtt /
      first(median_property_price_philadelphia_rtt),
    redfin_activity_index = 100 * n_eligible_sales_redfin /
      first(n_eligible_sales_redfin),
    rtt_activity_index = 100 * n_eligible_sales_philadelphia_rtt /
      first(n_eligible_sales_philadelphia_rtt),
    .by = zip5
  ) |>
  select(
    zip5,
    year,
    redfin_price_index,
    rtt_price_index,
    redfin_activity_index,
    rtt_activity_index
  ) |>
  pivot_longer(
    -c(zip5, year),
    names_to = c("source", "measure"),
    names_pattern = "(redfin|rtt)_(price|activity)_index",
    values_to = "index"
  ) |>
  mutate(
    source = recode(source, redfin = "Redfin", rtt = "Philadelphia RTT"),
    measure = recode(measure, price = "Median price", activity = "Sale activity")
  )

source_comparison_plot <- ggplot(
  indexed_source_plot_data,
  aes(year, index, color = source, linetype = source)
) +
  geom_hline(yintercept = 100, color = "#636363", linetype = "dotted") +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2.2) +
  facet_grid(measure ~ zip5, scales = "free_y") +
  scale_color_manual(values = c("Redfin" = "#D95F0E", "Philadelphia RTT" = "#08519C")) +
  scale_x_continuous(breaks = seq(2015, 2024, 2)) +
  scale_y_continuous(labels = scales::label_number(accuracy = 1)) +
  labs(
    title = "Redfin and RTT: Same Direction, Different Samples?",
    subtitle = "Each source indexed to 2015 = 100 within ZIP and measure",
    x = NULL,
    y = "Index (2015 = 100)",
    color = NULL,
    linetype = NULL,
    caption = paste(
      "Redfin and RTT definitions differ, so levels and counts are not expected to match.",
      "The comparison tests trajectory and selection robustness."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_redfin_rtt_reconciliation.png",
  source_comparison_plot,
  width = 11,
  height = 8,
  dpi = 300
)

if (interactive()) print(source_comparison_plot)
filter(source_reconciliation, selected_case)

