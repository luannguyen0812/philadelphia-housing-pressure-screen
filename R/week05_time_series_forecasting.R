library(tidyverse)
library(tsibble)
library(fabletools)
library(fable)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 05: SELECTED-ZIP TRANSACTION FORECASTING AND VALIDATION
# =============================================================================
# ABSTRACT
# This script moves forecasting into Week 5. It models monthly eligible sale
# counts for 19132 and 19143 using seasonal-naive, ETS, and ARIMA candidates.
# Models are judged in both a pre-pandemic 2019 holdout and a post-disruption
# 2022-2024 holdout before being refit through 2025. A second sensitivity stage
# compares (1) all observations with pandemic/backlog intervention indicators,
# (2) those disruption months treated as missing, and (3) the post-backlog
# regime alone. Forecasts through 2035 are planning baselines with widening
# uncertainty, not causal gentrification forecasts. XGBoost/LightGBM are not
# added because the current sample is a small univariate monthly series; they
# should only be considered later if a validated exogenous feature panel
# materially improves out-of-sample accuracy.

# =============================================================================
# 1. SETTINGS AND ELIGIBLE-SALE DEFINITION
# =============================================================================
# Caption: Use complete years 2010-2025, preserve the Week 4 arm's-length sale
# filters, and reserve two structurally different validation windows.

selected_zips <- c("19132", "19143")
document_path <- file.path("team_data", "data_document.csv.gz")
forecast_end <- yearmonth("2035 Dec")

if (!file.exists(document_path)) {
  stop("Missing ", document_path, ". Run R/BSAN_Proj.R first.")
}

dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

sales <- read_csv(
  document_path,
  col_select = c(
    document_id, document_type, activity_type, record_date, year, yr_mo,
    primary_zip5, n_parcel_rows, total_consideration, nominal_transfer,
    unknown_consideration, high_value_sale_outlier
  ),
  col_types = cols(
    document_id = col_character(),
    record_date = col_date(),
    yr_mo = col_date(),
    primary_zip5 = col_character()
  ),
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
  count(zip5 = primary_zip5, month = yr_mo, name = "eligible_sales")

# Caption: Insert explicit zero-sale months so every ZIP series is regular and
# the models cannot confuse a missing record with a missing time period.

monthly_sales <- sales |>
  complete(
    zip5 = selected_zips,
    month = seq.Date(as.Date("2010-01-01"), as.Date("2025-12-01"), by = "month"),
    fill = list(eligible_sales = 0L)
  ) |>
  arrange(zip5, month) |>
  mutate(month = yearmonth(month)) |>
  as_tsibble(key = zip5, index = month)

# =============================================================================
# 2. REUSABLE MODEL AND HOLDOUT FUNCTIONS
# =============================================================================
# Caption: Always compare statistical models with a seasonal-naive baseline;
# sophistication is useful only when it improves unseen-period accuracy.

fit_candidates <- function(training_data) {
  training_data |>
    model(
      seasonal_naive = SNAIVE(eligible_sales),
      ets = ETS(eligible_sales),
      arima = ARIMA(eligible_sales)
    )
}

score_holdout <- function(training_data, test_data, holdout_name) {
  seasonal_scale <- training_data |>
    as_tibble() |>
    arrange(zip5, month) |>
    mutate(
      seasonal_error = eligible_sales - lag(eligible_sales, 12L),
      .by = zip5
    ) |>
    summarise(
      mase_scale = mean(abs(seasonal_error), na.rm = TRUE),
      rmsse_scale = sqrt(mean(seasonal_error^2, na.rm = TRUE)),
      .by = zip5
    )

  fit_candidates(training_data) |>
    forecast(new_data = test_data) |>
    accuracy(test_data) |>
    mutate(holdout = holdout_name) |>
    select(-MASE, -RMSSE) |>
    left_join(seasonal_scale, by = "zip5") |>
    mutate(
      MASE = MAE / mase_scale,
      RMSSE = RMSE / rmsse_scale
    ) |>
    select(zip5, holdout, .model, RMSE, MAE, MASE, RMSSE, MAPE)
}

# =============================================================================
# 3. VALIDATE BEFORE AND AFTER THE PANDEMIC DISRUPTION
# =============================================================================
# Caption: The 2019 holdout tests ordinary pre-pandemic predictability; the
# 2022-2024 holdout tests whether a model survives the changed market regime.

prepandemic_train <- monthly_sales |> filter(month <= yearmonth("2018 Dec"))
prepandemic_test <- monthly_sales |>
  filter(month >= yearmonth("2019 Jan"), month <= yearmonth("2019 Dec"))

recent_train <- monthly_sales |> filter(month <= yearmonth("2021 Dec"))
recent_test <- monthly_sales |>
  filter(month >= yearmonth("2022 Jan"), month <= yearmonth("2024 Dec"))

forecast_accuracy <- bind_rows(
  score_holdout(prepandemic_train, prepandemic_test, "2019 pre-pandemic"),
  score_holdout(recent_train, recent_test, "2022-2024 changed regime")
)

# Caption: Select one model per ZIP using average within-holdout RMSE rank. This
# prevents the longer recent window from dominating merely because it has more
# forecast months.

baseline_performance <- forecast_accuracy |>
  filter(.model == "seasonal_naive") |>
  summarise(baseline_mean_rmse = mean(RMSE), .by = zip5)

model_selection <- forecast_accuracy |>
  mutate(rmse_rank = min_rank(RMSE), .by = c(zip5, holdout)) |>
  summarise(
    mean_rmse_rank = mean(rmse_rank),
    mean_rmse = mean(RMSE),
    mean_mase = mean(MASE),
    validation_windows = n(),
    .by = c(zip5, .model)
  ) |>
  left_join(baseline_performance, by = "zip5") |>
  mutate(beats_seasonal_naive_rmse = mean_rmse < baseline_mean_rmse) |>
  arrange(zip5, mean_rmse_rank, mean_rmse) |>
  mutate(recommended = row_number() == 1L, .by = zip5)

write_csv(forecast_accuracy, "tableau_data/week05_forecast_accuracy.csv")
write_csv(model_selection, "tableau_data/week05_forecast_model_selection.csv")

# =============================================================================
# 4. REFIT THROUGH 2025 AND FORECAST THROUGH 2035
# =============================================================================
# Caption: Produce every candidate forecast for auditability, then mark the
# independently selected series used in the presentation.

final_models <- fit_candidates(monthly_sales)
months_ahead <- as.integer(forecast_end - max(monthly_sales$month))
final_forecasts <- final_models |> forecast(h = months_ahead)

forecast_intervals <- final_forecasts |>
  hilo(`80%` = 80, `95%` = 95) |>
  unpack_hilo(c(`80%`, `95%`)) |>
  as_tibble() |>
  left_join(
    select(model_selection, zip5, .model, recommended),
    by = c("zip5", ".model")
  ) |>
  transmute(
    zip5,
    month = as.Date(month),
    model = .model,
    forecast_sales = .mean,
    lower_80 = `80%_lower`,
    upper_80 = `80%_upper`,
    lower_95 = `95%_lower`,
    upper_95 = `95%_upper`,
    recommended,
    interpretation = paste(
      "Planning baseline conditional on recorded history;",
      "not a causal or guaranteed transaction path"
    )
  )

write_csv(forecast_intervals, "tableau_data/week05_zip_transaction_forecasts.csv")

# =============================================================================
# 5. PANDEMIC AND RECORDING-BACKLOG SENSITIVITY
# =============================================================================
# Caption: Treat March 2020-April 2022 as an exceptional period rather than
# allowing ARIMA to interpret shutdown, rebound, and delayed recording as a
# normal recurring pattern. Compare three transparent specifications:
#   1. retain all months and identify pandemic/backlog interventions;
#   2. retain a regular monthly index but set disruption observations to NA;
#   3. fit an exploratory nonseasonal model only after the backlog period.

pandemic_start <- yearmonth("2020 Mar")
pandemic_end <- yearmonth("2021 Jun")
backlog_start <- yearmonth("2021 Jul")
backlog_end <- yearmonth("2022 Apr")
recent_regime_start <- yearmonth("2022 May")

monthly_sensitivity <- monthly_sales |>
  mutate(
    pandemic_intervention = as.integer(
      month >= pandemic_start & month <= pandemic_end
    ),
    recording_backlog_intervention = as.integer(
      month >= backlog_start & month <= backlog_end
    ),
    disruption_period =
      pandemic_intervention == 1L | recording_backlog_intervention == 1L
  )

# Caption: Use the same 2024-2025 unseen period for every sensitivity model.
# The post-backlog-only candidate has a short training history and is retained
# as a scenario check, not automatically promoted to the primary forecast.

sensitivity_train <- monthly_sensitivity |>
  filter(month <= yearmonth("2023 Dec"))
sensitivity_test <- monthly_sensitivity |>
  filter(month >= yearmonth("2024 Jan"), month <= yearmonth("2025 Dec"))

full_history_validation <- sensitivity_train |>
  model(
    `Full history, unadjusted` = ARIMA(eligible_sales),
    `Full history + shock indicators` = ARIMA(
      eligible_sales ~ pandemic_intervention + recording_backlog_intervention
    )
  ) |>
  forecast(new_data = sensitivity_test) |>
  accuracy(sensitivity_test) |>
  select(zip5, specification = .model, RMSE, MAE, MAPE)

excluded_validation <- sensitivity_train |>
  mutate(
    eligible_sales = if_else(disruption_period, NA_real_, eligible_sales)
  ) |>
  model(`Pandemic/backlog months excluded` = ARIMA(eligible_sales)) |>
  forecast(new_data = sensitivity_test) |>
  accuracy(sensitivity_test) |>
  select(zip5, specification = .model, RMSE, MAE, MAPE)

recent_validation <- sensitivity_train |>
  filter(month >= recent_regime_start) |>
  model(
    `Post-backlog history only` = ARIMA(
      eligible_sales ~ pdq() + PDQ(0, 0, 0)
    )
  ) |>
  forecast(new_data = sensitivity_test) |>
  accuracy(sensitivity_test) |>
  select(zip5, specification = .model, RMSE, MAE, MAPE)

pandemic_sensitivity_accuracy <- bind_rows(
  full_history_validation,
  excluded_validation,
  recent_validation
) |>
  mutate(
    rmse_rank = min_rank(RMSE),
    .by = zip5
  ) |>
  arrange(zip5, rmse_rank)

write_csv(
  pandemic_sensitivity_accuracy,
  "tableau_data/week05_pandemic_sensitivity_accuracy.csv"
)

# Caption: Refit the three pandemic specifications through 2025 and forecast
# the same horizon. Future intervention fields are zero because the forecast is
# conditional on no recurrence of the identified pandemic/backlog shock.

future_sensitivity <- new_data(monthly_sensitivity, n = months_ahead) |>
  mutate(
    pandemic_intervention = 0L,
    recording_backlog_intervention = 0L,
    disruption_period = FALSE
  )

intervention_forecast <- monthly_sensitivity |>
  model(
    `Full history + shock indicators` = ARIMA(
      eligible_sales ~ pandemic_intervention + recording_backlog_intervention
    )
  ) |>
  forecast(new_data = future_sensitivity)

excluded_forecast <- monthly_sensitivity |>
  mutate(
    eligible_sales = if_else(disruption_period, NA_real_, eligible_sales)
  ) |>
  model(`Pandemic/backlog months excluded` = ARIMA(eligible_sales)) |>
  forecast(h = months_ahead)

recent_regime_forecast <- monthly_sensitivity |>
  filter(month >= recent_regime_start) |>
  model(
    `Post-backlog history only` = ARIMA(
      eligible_sales ~ pdq() + PDQ(0, 0, 0)
    )
  ) |>
  forecast(h = months_ahead)

pandemic_sensitivity_forecasts <- bind_rows(
  intervention_forecast |> as_tibble(),
  excluded_forecast |> as_tibble(),
  recent_regime_forecast |> as_tibble()
) |>
  transmute(
    zip5,
    month = as.Date(month),
    specification = .model,
    forecast_sales = .mean,
    interpretation = case_when(
      specification == "Full history + shock indicators" ~
        "Primary: all observations retained with identified shock periods",
      specification == "Pandemic/backlog months excluded" ~
        "Sensitivity: disruption observations omitted from estimation",
      TRUE ~
        "Exploratory sensitivity: short post-backlog history only"
    )
  )

write_csv(
  pandemic_sensitivity_forecasts,
  "tableau_data/week05_pandemic_sensitivity_forecasts.csv"
)

# Caption: Retain prediction intervals for the intervention-adjusted model used
# in the primary presentation graph.

primary_intervention_forecast <- intervention_forecast |>
  hilo(`80%` = 80, `95%` = 95) |>
  unpack_hilo(c(`80%`, `95%`)) |>
  as_tibble() |>
  transmute(
    zip5,
    month = as.Date(month),
    forecast_sales = .mean,
    lower_80 = `80%_lower`,
    upper_80 = `80%_upper`,
    lower_95 = `95%_lower`,
    upper_95 = `95%_upper`
  )

write_csv(
  primary_intervention_forecast,
  "tableau_data/week05_primary_intervention_forecast.csv"
)

# =============================================================================
# VISUALIZATION 7 — PANDEMIC-ADJUSTED PRIMARY TRANSACTION FORECAST
# =============================================================================
# Caption: Show recent observed history and the full-history ARIMA with explicit
# pandemic and recording-backlog interventions. Dark projector-readable bands
# make the substantial long-horizon uncertainty visible.

observed_plot_data <- monthly_sales |>
  filter(month >= yearmonth("2015 Jan")) |>
  as_tibble() |>
  mutate(month = as.Date(month))

forecast_plot <- ggplot() +
  geom_ribbon(
    data = primary_intervention_forecast,
    aes(month, ymin = pmax(lower_95, 0), ymax = upper_95),
    fill = "#3182BD",
    alpha = 0.38
  ) +
  geom_ribbon(
    data = primary_intervention_forecast,
    aes(month, ymin = pmax(lower_80, 0), ymax = upper_80),
    fill = "#08519C",
    alpha = 0.52
  ) +
  geom_line(
    data = observed_plot_data,
    aes(month, eligible_sales),
    color = "#252525",
    linewidth = 0.9
  ) +
  geom_line(
    data = primary_intervention_forecast,
    aes(month, forecast_sales),
    color = "#D95F0E",
    linewidth = 1.15
  ) +
  facet_wrap(vars(zip5), ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  scale_y_continuous(labels = scales::label_number(accuracy = 1)) +
  labs(
    title = "Pandemic-Adjusted Sale-Activity Baseline Through 2035",
    subtitle = "Full history with shock indicators; 80% and 95% prediction intervals",
    x = NULL,
    y = "Eligible single-property sales per month",
    caption = paste(
      "March 2020-June 2021 and the July 2021-April 2022 recording backlog",
      "are retained as identified disruptions, not assumed recurring behavior."
    )
  ) +
  week05_presentation_theme(legend_position = "none")

ggsave(
  "visualizations/week05_pandemic_adjusted_transaction_forecast.png",
  forecast_plot,
  width = 11,
  height = 8,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 8 — PANDEMIC-TREATMENT FORECAST SENSITIVITY
# =============================================================================
# Caption: Overlay the intervention-adjusted, disruption-excluded, and recent-
# regime paths on a common scale. Separation indicates that the forecast is
# sensitive to pandemic treatment and should be presented as scenarios.

pandemic_sensitivity_plot <- ggplot(
  pandemic_sensitivity_forecasts,
  aes(month, forecast_sales, color = specification, linetype = specification)
) +
  geom_line(linewidth = 1.2) +
  facet_wrap(vars(zip5), ncol = 1, scales = "free_y") +
  scale_color_manual(values = c(
    "Full history + shock indicators" = "#D95F0E",
    "Pandemic/backlog months excluded" = "#08519C",
    "Post-backlog history only" = "#4D4D4D"
  )) +
  scale_linetype_manual(values = c(
    "Full history + shock indicators" = "solid",
    "Pandemic/backlog months excluded" = "dashed",
    "Post-backlog history only" = "dotdash"
  )) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  scale_y_continuous(
    labels = scales::label_number(accuracy = 1),
    limits = c(0, NA)
  ) +
  labs(
    title = "Does Pandemic Treatment Change the Forecast?",
    subtitle = "Alternative ARIMA specifications refitted through 2025",
    x = NULL,
    y = "Forecast eligible sales per month",
    color = NULL,
    linetype = NULL,
    caption = paste(
      "The post-backlog-only path has a much shorter training history and is exploratory.",
      "Large separation means the future path should be presented as scenarios."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_pandemic_forecast_sensitivity.png",
  pandemic_sensitivity_plot,
  width = 11,
  height = 8,
  dpi = 300
)

# =============================================================================
# 7. PRINT WEEK 5 FORECAST OUTPUTS TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(forecast_plot)
  print(pandemic_sensitivity_plot)
}
model_selection |> filter(recommended)
pandemic_sensitivity_accuracy
