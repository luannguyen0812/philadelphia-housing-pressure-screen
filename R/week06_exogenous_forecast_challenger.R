library(tidyverse)
library(tsibble)
library(fabletools)
library(fable)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 06: EXOGENOUS FORECAST CHALLENGER
# =============================================================================
# ABSTRACT
# Test whether a small, interpretable set of lagged external market variables
# improves unseen-period monthly transaction forecasts. The challenger adds the
# prior month's 30-year mortgage rate, Redfin inventory, and Redfin median days
# on market to the pandemic-aware Auto-ARIMA specification. All candidates are
# restricted to the same February 2015-December 2023 training window and scored
# on January 2024-December 2025. Actual predictor values are available in that
# historical holdout, so this is a conditional explanatory/short-term
# challenger—not a deployable 2035 forecast. A long-horizon ARIMAX path would
# first require explicit future scenarios for every predictor.

# =============================================================================
# 1. BUILD THE COMMON MONTHLY TARGET AND PREDICTOR PANEL
# =============================================================================
# Caption: Use one-month lags so each predictor precedes the transaction month.
# Redfin measures are published 90-day rolling ZIP observations, not unit-level
# listings, and remain market-context variables rather than causal mechanisms.

selected_zips <- c("19132", "19143")
redfin_path <- file.path(
  "external_data", "raw", "redfin_zip_market_tracker_philadelphia.tsv"
)
econ_path <- file.path("tableau_data", "dim_econ_indicators.csv")
document_path <- file.path("team_data", "data_document.csv.gz")

missing_inputs <- c(redfin_path, econ_path, document_path)[
  !file.exists(c(redfin_path, econ_path, document_path))
]
if (length(missing_inputs)) {
  stop("Missing exogenous-challenger input(s): ", paste(missing_inputs, collapse = ", "))
}

monthly_sales <- read_csv(
  document_path,
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
    year %in% 2015:2025,
    document_type == "DEED",
    activity_type == "sale_deed",
    n_parcel_rows == 1L,
    !nominal_transfer,
    !unknown_consideration,
    !high_value_sale_outlier,
    total_consideration > 100
  ) |>
  count(zip5 = primary_zip5, month = yr_mo, name = "eligible_sales") |>
  complete(
    zip5 = selected_zips,
    month = seq.Date(
      as.Date("2015-01-01"), as.Date("2025-12-01"), by = "month"
    ),
    fill = list(eligible_sales = 0L)
  )

redfin_monthly <- read_tsv(
  redfin_path,
  col_types = cols(.default = col_guess()),
  show_col_types = FALSE
) |>
  transmute(
    month = floor_date(as.Date(PERIOD_END), "month"),
    zip5 = str_extract(REGION, "[0-9]{5}"),
    property_type = PROPERTY_TYPE,
    period_duration = PERIOD_DURATION,
    inventory = as.double(INVENTORY),
    median_days_on_market = as.double(MEDIAN_DOM)
  ) |>
  filter(
    zip5 %in% selected_zips,
    property_type == "All Residential",
    period_duration == 90,
    month >= as.Date("2015-01-01"),
    month <= as.Date("2025-12-01")
  ) |>
  summarise(
    inventory = mean(inventory, na.rm = TRUE),
    median_days_on_market = mean(median_days_on_market, na.rm = TRUE),
    .by = c(zip5, month)
  )

econ_monthly <- read_csv(
  econ_path,
  col_types = cols(yr_mo = col_date()),
  show_col_types = FALSE
) |>
  transmute(month = floor_date(yr_mo, "month"), mortgage_rate_30y)

challenger_panel <- monthly_sales |>
  left_join(redfin_monthly, by = c("zip5", "month")) |>
  left_join(econ_monthly, by = "month") |>
  arrange(zip5, month) |>
  mutate(
    mortgage_rate_lag1 = lag(mortgage_rate_30y),
    log_inventory_lag1 = lag(log1p(inventory)),
    median_dom_lag1 = lag(median_days_on_market),
    pandemic_intervention = as.integer(
      month >= as.Date("2020-03-01") & month <= as.Date("2021-06-01")
    ),
    recording_backlog_intervention = as.integer(
      month >= as.Date("2021-07-01") & month <= as.Date("2022-04-01")
    ),
    .by = zip5
  ) |>
  filter(
    month >= as.Date("2015-02-01"),
    complete.cases(
      mortgage_rate_lag1, log_inventory_lag1, median_dom_lag1
    )
  ) |>
  mutate(month = yearmonth(month)) |>
  as_tsibble(key = zip5, index = month)

# =============================================================================
# 2. FIT SAME-SAMPLE AUTO-ARIMA CANDIDATES AND SCORE 2024-2025
# =============================================================================
# Caption: Compare the primary intervention structure, a mortgage-only model,
# and a parsimonious mortgage-plus-market model on exactly the same observations.

challenger_train <- challenger_panel |>
  filter(month <= yearmonth("2023 Dec"))
challenger_test <- challenger_panel |>
  filter(month >= yearmonth("2024 Jan"), month <= yearmonth("2025 Dec"))

challenger_fit <- challenger_train |>
  model(
    `Interventions only` = ARIMA(
      eligible_sales ~ pandemic_intervention + recording_backlog_intervention
    ),
    `+ Lagged mortgage rate` = ARIMA(
      eligible_sales ~ pandemic_intervention +
        recording_backlog_intervention + mortgage_rate_lag1
    ),
    `+ Mortgage, inventory, DOM` = ARIMA(
      eligible_sales ~ pandemic_intervention +
        recording_backlog_intervention + mortgage_rate_lag1 +
        log_inventory_lag1 + median_dom_lag1
    )
  )

challenger_forecasts <- challenger_fit |>
  forecast(new_data = challenger_test)

challenger_accuracy <- challenger_forecasts |>
  accuracy(challenger_test) |>
  select(zip5, specification = .model, RMSE, MAE, MAPE) |>
  arrange(zip5, RMSE) |>
  mutate(
    rmse_rank = row_number(),
    improves_same_sample_intervention = RMSE < RMSE[
      specification == "Interventions only"
    ],
    .by = zip5
  )

challenger_decision <- challenger_accuracy |>
  slice_min(RMSE, n = 1, with_ties = FALSE, by = zip5) |>
  transmute(
    zip5,
    best_specification = specification,
    best_rmse = RMSE,
    promote_to_primary_long_horizon = FALSE,
    decision_reason = paste(
      "Historical holdout uses observed predictor paths; a 2035 ARIMAX forecast",
      "requires separately validated mortgage, inventory, and DOM scenarios."
    )
  )

write_csv(
  challenger_accuracy,
  "tableau_data/week06_exogenous_challenger_accuracy.csv"
)
write_csv(
  challenger_decision,
  "tableau_data/week06_exogenous_challenger_decision.csv"
)
write_csv(
  tidy(challenger_fit),
  "tableau_data/week06_exogenous_challenger_coefficients.csv"
)

# =============================================================================
# VISUALIZATION 4 — EXOGENOUS CHALLENGER HOLDOUT ERROR
# =============================================================================
# Caption: Make the test result visible without implying that the best
# conditional holdout model can be extended through 2035 without predictor
# scenarios.

challenger_plot <- ggplot(
  challenger_accuracy,
  aes(RMSE, fct_reorder(specification, RMSE), color = specification)
) +
  geom_segment(
    aes(x = 0, xend = RMSE, yend = specification),
    color = "#BDBDBD",
    linewidth = 1
  ) +
  geom_point(size = 4.8) +
  geom_text(
    aes(label = scales::number(RMSE, accuracy = 0.1)),
    nudge_x = 0.6,
    fontface = "bold",
    size = 4,
    show.legend = FALSE
  ) +
  facet_wrap(vars(zip5), ncol = 1, scales = "free_x") +
  scale_color_manual(values = c(
    "Interventions only" = "#636363",
    "+ Lagged mortgage rate" = "#3182BD",
    "+ Mortgage, inventory, DOM" = "#D95F0E"
  )) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Do Lagged Market Drivers Improve the 2024-2025 Holdout?",
    subtitle = "Same February 2015-December 2023 training window; lower RMSE is better",
    x = "Root mean squared error (monthly sales)",
    y = NULL,
    color = NULL,
    caption = paste(
      "The challenger is conditional on observed historical predictor values.",
      "It is not promoted to 2035 without explicit future predictor scenarios."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week06_exogenous_forecast_challenger.png",
  challenger_plot,
  width = 11,
  height = 7.5,
  dpi = 300
)

if (interactive()) {
  print(challenger_plot)
}

challenger_decision
