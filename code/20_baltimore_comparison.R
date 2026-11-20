# =============================================================================
# 20. BALTIMORE PEER-CITY COMPARISON
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Measures how far five Baltimore neighborhoods have travelled along the
#   price path the Philadelphia screen is trying to catch early, and sets that
#   against a Baltimore benchmark. This is the evidence behind slide 10 of the
#   client presentation. It is a descriptive comparison of stages, not a
#   forecast for a Philadelphia ZIP and not evidence of displacement in either
#   city.
# INPUTS
#   external_data/raw/baltimore_redfin_neighborhoods.csv
#     Redfin neighborhood market tracker, Baltimore MD metro area, one row per
#     neighborhood-month. Columns used: PERIOD BEGIN, REGION NAME, HOMES SOLD,
#     MEDIAN SALE PRICE NSA ($). Window in the delivered file: 2012-01-01 to
#     2026-08-31, 305 neighborhoods.
# OUTPUTS
#   external_data/baltimore_neighborhood_prices.csv
#     The five neighborhoods, 2012 and 2025 separately, with prices, sales and
#     percent change.
#   tableau_data/week07_baltimore_comparison.csv
#     The five neighborhoods plus the Baltimore benchmark, as plotted.
#   visualizations/week07_baltimore_comparison.png
#     Ranked bar chart of percent price change.
# RUNS AFTER   00 only. This stage is deliberately NOT part of run_all.R: it is
#   a separate section with its own source file, and its input is not one of
#   the Philadelphia extracts.
# =============================================================================
#
# HOW THE BENCHMARK IS DEFINED - read this before quoting a ratio.
#
#   `baltimore_overall` averages every region present in the file, which is
#   every neighborhood in the Baltimore METRO area (Baltimore City plus
#   Baltimore County and Harford County neighborhoods). It is an unweighted
#   mean of neighborhood medians, not a citywide median, and its level in
#   2012 is about $160,000 against roughly $92,000 for Baltimore City. Say
#   "average Baltimore-area neighborhood", never "city average".
#
#   The window is 2012 against 2025, both complete calendar years in the
#   delivered file. Each year's price is the mean of that year's monthly
#   median sale prices, which is the measure the comparison has always used.
#   Sparse neighborhoods carry fewer months: Union Square has 4 months of
#   2012 data against 7 of 2025, so its percentage rests on the thinnest
#   sample of the five.
# =============================================================================

# Load the shared configuration whether this file is run from the project root,
# from the code folder, or from this folder. `run_all.R` sets `code_dir` before
# any stage, so in a full run nothing here executes.
if (!exists("code_dir")) {
  config_candidates <- c(
    "00_config.R",
    file.path("code", "00_config.R"),
    file.path("..", "00_config.R"),
    file.path("..", "..", "code", "00_config.R")
  )
  config_path <- config_candidates[file.exists(config_candidates)][1]
  if (is.na(config_path)) {
    stop(
      "Could not find 00_config.R. Run this script from the project root ",
      "(source(\"code/20_baltimore_comparison.R\")) or from the code folder.",
      call. = FALSE
    )
  }
  source(config_path)
}

library(tidyverse)
library(lubridate)
library(scales)

# =============================================================================
# 1. LOAD THE REDFIN NEIGHBORHOOD PANEL
# =============================================================================

redfin_path <- file.path(
  project_root, "external_data", "raw", "baltimore_redfin_neighborhoods.csv"
)

if (!file.exists(redfin_path)) {
  stop(
    "Baltimore input not found at ", redfin_path,
    "\n  Expected: external_data/raw/baltimore_redfin_neighborhoods.csv",
    call. = FALSE
  )
}

redfin_blt_final <- readr::read_csv(redfin_path, show_col_types = FALSE)

# ============================================================
# SELECT FIVE BALTIMORE NEIGHBORHOODS
# ============================================================

redfin_blt_five <- redfin_blt_final %>%
  filter(`REGION NAME` %in% c(
    "Highlandtown",
    "Remington",
    "Patterson Park",
    "Washington Village-Pigtown",
    "Union Square"
  ))

# ============================================================
# CALCULATE PRICE CHANGE FOR FIVE NEIGHBORHOODS
# ============================================================

baltimore_price_rankings <- redfin_blt_five %>%
  mutate(
    YEAR = year(as.Date(`PERIOD BEGIN`))
  ) %>%
  filter(YEAR %in% c(2012, 2025)) %>%
  group_by(`REGION NAME`, YEAR) %>%
  summarise(
    median_sale_price = mean(`MEDIAN SALE PRICE NSA ($)`, na.rm = TRUE),
    homes_sold = sum(`HOMES SOLD`, na.rm = TRUE),
    months_observed = sum(!is.na(`MEDIAN SALE PRICE NSA ($)`)),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = YEAR,
    values_from = c(median_sale_price, homes_sold, months_observed)
  ) %>%
  filter(
    !is.na(median_sale_price_2012),
    !is.na(median_sale_price_2025),
    median_sale_price_2012 > 0
  ) %>%
  mutate(
    dollar_price_change =
      median_sale_price_2025 - median_sale_price_2012,
    percent_price_change =
      ((median_sale_price_2025 - median_sale_price_2012) /
         median_sale_price_2012) * 100
  ) %>%
  arrange(desc(percent_price_change)) %>%
  mutate(Rank = row_number()) %>%
  select(
    Rank,
    Neighborhood = `REGION NAME`,
    median_sale_price_2012,
    median_sale_price_2025,
    dollar_price_change,
    percent_price_change,
    homes_sold_2012,
    homes_sold_2025,
    months_observed_2012,
    months_observed_2025
  )

# ============================================================
# CALCULATE BALTIMORE AVERAGE
# ============================================================

baltimore_overall <- redfin_blt_final %>%
  mutate(
    YEAR = year(as.Date(`PERIOD BEGIN`))
  ) %>%
  filter(YEAR %in% c(2012, 2025)) %>%
  group_by(`REGION NAME`, YEAR) %>%
  summarise(
    median_sale_price = mean(`MEDIAN SALE PRICE NSA ($)`, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(YEAR) %>%
  summarise(
    avg_baltimore_price = mean(median_sale_price, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = YEAR,
    values_from = avg_baltimore_price,
    names_prefix = "price_"
  ) %>%
  mutate(
    percent_price_change =
      ((price_2025 - price_2012) / price_2012) * 100
  )

# How many regions sit behind each year's benchmark. The two years do not cover
# the same set of neighborhoods, which is why the benchmark is reported as an
# average rather than as a like-for-like basket.
baltimore_coverage <- redfin_blt_final %>%
  mutate(YEAR = year(as.Date(`PERIOD BEGIN`))) %>%
  filter(YEAR %in% c(2012, 2025)) %>%
  distinct(YEAR, `REGION NAME`) %>%
  count(YEAR, name = "regions_observed")

# Store Baltimore average
baltimore_avg_change <- baltimore_overall$percent_price_change

# ============================================================
# CHECK BALTIMORE NUMBERS
# ============================================================

message(
  "Baltimore benchmark: ", round(baltimore_overall$price_2012), " (2012) -> ",
  round(baltimore_overall$price_2025), " (2025), ",
  round(baltimore_avg_change, 1), "% change"
)
message(
  "Regions behind the benchmark: ",
  paste(baltimore_coverage$regions_observed, collapse = " and ")
)

# ============================================================
# VIEW FIVE NEIGHBORHOOD RESULTS
# ============================================================

# The five-neighborhood table is the result; print it for an interactive run.
print(baltimore_price_rankings, n = Inf, width = Inf)

# ============================================================
# CREATE CHART DATA
# ============================================================

chart_data <- baltimore_price_rankings %>%
  select(Neighborhood, percent_price_change) %>%
  bind_rows(
    tibble(
      Neighborhood = "Baltimore Average",
      percent_price_change = baltimore_avg_change
    )
  ) %>%
  mutate(
    Group = if_else(
      Neighborhood == "Baltimore Average",
      "Baltimore Average",
      "Selected Neighborhoods"
    )
  )

# ============================================================
# CREATE CHART
# ============================================================

baltimore_chart <- ggplot(
  chart_data,
  aes(
    x = reorder(Neighborhood, percent_price_change),
    y = percent_price_change,
    fill = Group
  )
) +
  geom_col(width = 0.7) +
  geom_text(
    aes(label = paste0(round(percent_price_change, 0), "%")),
    hjust = -0.1,
    size = 4.5,
    fontface = "bold"
  ) +
  coord_flip() +
  scale_fill_manual(
    values = c(
      "Baltimore Average" = "#2166AC",
      "Selected Neighborhoods" = "#B2182B"
    )
  ) +
  scale_y_continuous(
    labels = function(x) paste0(round(x, 0), "%"),
    expand = expansion(mult = c(0, 0.15))
  ) +
  labs(
    title = "Baltimore Neighborhood Home Price Appreciation",
    subtitle = "Percent change in median sale price from 2012 to 2025",
    x = NULL,
    y = "Median Price Increase %",
    caption = "Source: Redfin"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 17),
    plot.subtitle = element_text(size = 12),
    axis.text.y = element_text(
      size = ifelse(
        levels(reorder(chart_data$Neighborhood, chart_data$percent_price_change)) == "Baltimore Average",
        15, 11
      ),
      face = ifelse(
        levels(reorder(chart_data$Neighborhood, chart_data$percent_price_change)) == "Baltimore Average",
        "bold", "plain"
      )
    ),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "none"
  )

print(baltimore_chart)  # the same figure is written to PNG below

# =============================================================================
# 2. WRITE OUTPUTS
# =============================================================================

clean_out <- file.path(project_root, "external_data", "baltimore_neighborhood_prices.csv")
analysis_out <- file.path(project_root, "tableau_data", "week07_baltimore_comparison.csv")
chart_out <- file.path(project_root, "visualizations", "week07_baltimore_comparison.png")

readr::write_csv(baltimore_price_rankings, clean_out, na = "")
readr::write_csv(chart_data, analysis_out, na = "")

ggplot2::ggsave(
  filename = chart_out, plot = baltimore_chart,
  width = 9, height = 6, dpi = 200, bg = "white"
)

cat("\nWrote:\n  ", clean_out, "\n  ", analysis_out, "\n  ", chart_out, "\n", sep = "")
