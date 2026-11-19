library(tidyverse)
library(tsibble)
library(fabletools)
library(fable)
library(feasts)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 06: FORECAST TECHNICAL APPENDIX AND DIAGNOSTICS
# =============================================================================
# ABSTRACT
# Refit and document the primary transaction forecast so a technical audience
# can see exactly how the curve was constructed. The model uses 192 monthly
# observations per ZIP from January 2010 through December 2025. Auto-ARIMA
# selects the ARIMA error order separately for each ZIP, while two supplied
# historical intervention variables identify the pandemic and recording-
# backlog periods. No mortgage-rate, inventory, price, income, permit, or
# eviction predictors enter the primary model. The forecast is therefore a
# conditional time-series baseline, not a causal housing-market forecast.

# =============================================================================
# 1. REBUILD THE PRIMARY MONTHLY TRAINING PANEL
# =============================================================================
# Caption: Apply the same eligible-sale definition and zero-month completion
# used in Week 5 so diagnostics refer to the exact presented forecast.

selected_zips <- c("19132", "19143")
document_path <- file.path("team_data", "data_document.csv.gz")

if (!file.exists(document_path)) {
  stop("Missing ", document_path, ". Run R/BSAN_Proj.R first.")
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
    year %in% 2010:2025,
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
      as.Date("2010-01-01"), as.Date("2025-12-01"), by = "month"
    ),
    fill = list(eligible_sales = 0L)
  ) |>
  arrange(zip5, month) |>
  mutate(
    month = yearmonth(month),
    pandemic_intervention = as.integer(
      month >= yearmonth("2020 Mar") & month <= yearmonth("2021 Jun")
    ),
    recording_backlog_intervention = as.integer(
      month >= yearmonth("2021 Jul") & month <= yearmonth("2022 Apr")
    )
  ) |>
  as_tsibble(key = zip5, index = month)

training_counts <- monthly_sales |>
  as_tibble() |>
  summarise(
    training_start = as.Date(min(month)),
    training_end = as.Date(max(month)),
    training_observations = n(),
    pandemic_indicator_months = sum(pandemic_intervention),
    backlog_indicator_months = sum(recording_backlog_intervention),
    .by = zip5
  )

if (any(training_counts$training_observations != 192L)) {
  stop("Primary forecast requires 192 monthly observations per case-study ZIP.")
}

# =============================================================================
# 2. REFIT AUTO-ARIMA WITH THE TWO HISTORICAL INTERVENTIONS
# =============================================================================
# Caption: ARIMA() performs automatic order selection within the ARIMA family;
# it does not discover external predictors. The intervention variables are
# supplied explicitly and future values are assumed to be zero.

primary_fit <- monthly_sales |>
  model(
    auto_arima_intervention = ARIMA(
      eligible_sales ~ pandemic_intervention + recording_backlog_intervention
    )
  )

model_description <- as_tibble(primary_fit) |>
  transmute(
    zip5,
    selected_model = map_chr(
      auto_arima_intervention,
      fabletools::model_sum
    )
  )

model_glance <- glance(primary_fit) |>
  select(zip5, sigma2, log_lik, AIC, AICc, BIC)

model_coefficients <- tidy(primary_fit) |>
  mutate(
    coefficient_type = case_when(
      str_detect(term, "^ar|^ma") ~ "ARIMA error term",
      str_detect(term, "intervention") ~ "Historical intervention",
      TRUE ~ "Other"
    )
  )

# Caption: Use a 24-month Ljung-Box check on one-step innovations. Degrees of
# freedom equal the number of estimated AR and MA terms in each selected model.

arma_df <- model_coefficients |>
  filter(coefficient_type == "ARIMA error term") |>
  count(zip5, name = "arma_degrees_of_freedom")

residual_diagnostics <- augment(primary_fit) |>
  as_tibble() |>
  left_join(arma_df, by = "zip5") |>
  summarise(
    residual_mean = mean(.innov, na.rm = TRUE),
    residual_sd = sd(.innov, na.rm = TRUE),
    ljung_box_lag = 24L,
    ljung_box_statistic = unname(Box.test(
      .innov,
      lag = 24,
      type = "Ljung-Box",
      fitdf = first(arma_degrees_of_freedom)
    )$statistic),
    ljung_box_p_value = Box.test(
      .innov,
      lag = 24,
      type = "Ljung-Box",
      fitdf = first(arma_degrees_of_freedom)
    )$p.value,
    .by = zip5
  )

# =============================================================================
# 3. COMBINE CONSTRUCTION, VALIDATION, AND SENSITIVITY METADATA
# =============================================================================
# Caption: Put the model order, sample size, display window, forecast horizon,
# validation criterion, and missing exogenous drivers in one appendix table.

model_selection <- read_csv(
  "tableau_data/week05_forecast_model_selection.csv",
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(recommended) |>
  select(
    zip5,
    selected_candidate = .model,
    validation_mean_rmse = mean_rmse,
    validation_mean_mase = mean_mase,
    seasonal_naive_mean_rmse = baseline_mean_rmse,
    beats_seasonal_naive_rmse
  )

sensitivity_best <- read_csv(
  "tableau_data/week05_pandemic_sensitivity_accuracy.csv",
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  arrange(zip5, RMSE) |>
  slice_head(n = 1, by = zip5) |>
  select(
    zip5,
    best_pandemic_sensitivity = specification,
    best_sensitivity_rmse = RMSE
  )

forecast_technical_summary <- training_counts |>
  left_join(model_description, by = "zip5") |>
  left_join(model_glance, by = "zip5") |>
  left_join(residual_diagnostics, by = "zip5") |>
  left_join(model_selection, by = "zip5") |>
  left_join(sensitivity_best, by = "zip5") |>
  mutate(
    chart_display_start = as.Date("2015-01-01"),
    chart_display_end = as.Date("2035-12-01"),
    forecast_start = as.Date("2026-01-01"),
    forecast_end = as.Date("2035-12-01"),
    forecast_horizon_months = 120L,
    candidate_models = "Seasonal naive; ETS; Auto-ARIMA",
    validation_windows = paste(
      "2019 pre-pandemic (12 months);",
      "2022-2024 changed regime (36 months)"
    ),
    selection_criterion = paste(
      "Mean within-holdout RMSE rank; selected model also checked against",
      "seasonal-naive mean RMSE"
    ),
    included_exogenous_variables = paste(
      "Pandemic indicator (2020-03 to 2021-06);",
      "recording-backlog indicator (2021-07 to 2022-04)"
    ),
    future_exogenous_assumption =
      "Both historical intervention variables equal zero after 2025-12",
    external_market_predictors_included = FALSE,
    excluded_external_predictors = paste(
      "Mortgage rates; Redfin inventory and days on market; price; income;",
      "permits; eviction filings"
    ),
    interpretation = paste(
      "Conditional historical sale-activity baseline with prediction",
      "intervals; not a causal displacement or economic-driver forecast"
    ),
    long_horizon_caution = paste(
      "The 120-month forecast is long relative to 192 training months; use",
      "near-term values operationally and 2035 as a planning scenario."
    )
  )

write_csv(
  forecast_technical_summary,
  "tableau_data/week06_forecast_technical_summary.csv"
)
write_csv(
  model_coefficients,
  "tableau_data/week06_forecast_coefficients.csv"
)

# =============================================================================
# VISUALIZATION 3 — OUT-OF-SAMPLE MODEL VALIDATION
# =============================================================================
# Caption: Show the unseen-period RMSE behind the Auto-ARIMA choice. Selection
# used mean RMSE across the two windows, not every window: for 19132 the 2019
# window is a near-tie favouring seasonal naive (12.83 vs 12.96), and for 19143
# the 2019 window favours ETS (10.60 vs 10.91). Both exceptions are disclosed
# on the slide. The intervention model is documented separately as the primary
# pandemic-aware specification.

forecast_accuracy <- read_csv(
  "tableau_data/week05_forecast_accuracy.csv",
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  mutate(
    model_label = recode(
      .model,
      seasonal_naive = "Seasonal naive",
      ets = "ETS",
      arima = "Auto-ARIMA"
    ),
    model_label = factor(
      model_label,
      levels = c("Seasonal naive", "ETS", "Auto-ARIMA")
    )
  )

forecast_validation_plot <- ggplot(
  forecast_accuracy,
  aes(model_label, RMSE, color = model_label)
) +
  geom_segment(
    aes(xend = model_label, y = 0, yend = RMSE),
    color = "#BDBDBD",
    linewidth = 1
  ) +
  geom_point(size = 4.5) +
  geom_text(
    aes(label = scales::number(RMSE, accuracy = 0.1)),
    vjust = -1.15,
    fontface = "bold",
    size = 3.7,
    show.legend = FALSE
  ) +
  facet_grid(zip5 ~ holdout, scales = "free_y") +
  scale_color_manual(values = c(
    "Seasonal naive" = "#636363",
    "ETS" = "#3182BD",
    "Auto-ARIMA" = "#D95F0E"
  )) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(
    title = "Auto-ARIMA Was Chosen on Unseen-Period Error",
    subtitle = "Lower RMSE is better; two time-ordered validation windows per ZIP",
    x = NULL,
    y = "Root mean squared error (monthly sales)",
    color = "Candidate model",
    caption = paste(
      "Selection compares model families. The final Auto-ARIMA specification",
      "adds explicit pandemic and recording-backlog indicators."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week06_forecast_validation.png",
  forecast_validation_plot,
  width = 12,
  height = 8,
  dpi = 300
)

# =============================================================================
# 4. PRINT WEEK 6 FORECAST DIAGNOSTICS TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(forecast_validation_plot)
}

forecast_technical_summary
