library(tidyverse)
library(lubridate)

# =============================================================================
# CORE VISUALIZATIONS: ACTIVITY, PRICE, ZIP SCENARIO, AND AFFORDABILITY
# =============================================================================
# Run after R/BSAN_Proj.R has created team_data/data_document.csv.gz.
#
# The five outputs intentionally answer one connected research area:
#   1. How transaction activity changed across Philadelphia from 2000 to July
#      2026.
#   2. How the median price of an eligible single-property deed changed over
#      the same period.
#   3. Which five ZIP codes had complete-year price growth most similar to the
#      citywide path, and what a transparent continuation of their recent
#      trends would look like over the next 10-15 years.
#   4. How ZIP-level residential prices, household income, price-to-income,
#      and housing-market activity move together during their common period.
#   5. Whether the typical ZIP-level price-to-income ratio improved or worsened
#      over the 2012-2024 Redfin-ACS overlap period.
#
# Interpretation decisions:
#   * 2026 is included as observed data through July, but never treated as a
#     complete year in annual growth calculations or model fitting.
#   * Activity counts include every document classified as sale_deed or
#     new_mortgage. Price summaries use exact DEED documents with one property,
#     known non-nominal consideration, and no high-value outlier flag.
#   * Prices are nominal dollars and describe recorded properties, not a
#     residential-only housing index.
#   * The ZIP result is a scenario projection, not a causal or precise forecast.

document_path <- file.path("team_data", "data_document.csv.gz")
tableau_dir <- "tableau_data"
tableau_ingestion_dir <- file.path(tableau_dir, "tableau_ingestion")
visual_dir <- "visualizations"

dir.create(tableau_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tableau_ingestion_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(visual_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(document_path)) {
  stop(
    "Missing ", document_path,
    ". Run source(\"R/BSAN_Proj.R\") first."
  )
}

analysis_start <- as.Date("2000-01-01")
analysis_end <- as.Date("2026-07-31")
last_complete_year <- 2025L
selection_start_year <- 2015L
model_start_year <- 2010L
recording_backlog_start <- as.Date("2021-07-01")
recording_backlog_end <- as.Date("2022-04-30")
minimum_zip_sales <- as.integer(getOption("bsan.min_zip_annual_sales", 30L))
projection_years <- as.integer(getOption("bsan.zip_projection_years", 15L))
zip_selection_rule <- getOption(
  "bsan.zip_selection_rule",
  "similar_to_citywide"
)

if (!projection_years %in% 10:15) {
  stop("bsan.zip_projection_years must be an integer from 10 through 15.")
}

if (!zip_selection_rule %in% c("similar_to_citywide", "highest_growth")) {
  stop(
    "bsan.zip_selection_rule must be 'similar_to_citywide' or ",
    "'highest_growth'."
  )
}

required_columns <- c(
  "document_id", "document_type", "activity_type", "record_date",
  "receipt_date", "recording_delay_from_receipt_days", "year", "yr_mo",
  "primary_zip5", "n_parcel_rows", "total_consideration",
  "nominal_transfer", "unknown_consideration", "high_value_sale_outlier"
)

if (exists("data_document", inherits = TRUE) &&
    all(required_columns %in% names(get("data_document", inherits = TRUE)))) {
  document_core <- get("data_document", inherits = TRUE) |>
    select(all_of(required_columns))
} else {
  document_core <- read_csv(
    document_path,
    col_select = all_of(required_columns),
    col_types = cols(
      document_id = col_character(),
      document_type = col_character(),
      activity_type = col_character(),
      record_date = col_date(),
      receipt_date = col_date(),
      recording_delay_from_receipt_days = col_integer(),
      year = col_integer(),
      yr_mo = col_date(),
      primary_zip5 = col_character(),
      n_parcel_rows = col_integer(),
      total_consideration = col_double(),
      nominal_transfer = col_logical(),
      unknown_consideration = col_logical(),
      high_value_sale_outlier = col_logical()
    ),
    show_col_types = FALSE,
    progress = interactive()
  )
}

document_core <- document_core |>
  filter(record_date >= analysis_start, record_date <= analysis_end)

stopifnot(
  !anyDuplicated(document_core$document_id),
  min(document_core$record_date, na.rm = TRUE) >= analysis_start,
  max(document_core$record_date, na.rm = TRUE) <= analysis_end
)

# =============================================================================
# VISUALIZATION 1: MONTHLY PHILADELPHIA ACTIVITY
# =============================================================================

analysis_months <- seq.Date(
  floor_date(analysis_start, "month"),
  floor_date(analysis_end, "month"),
  by = "month"
)

viz1_citywide_activity <- document_core |>
  filter(activity_type %in% c("sale_deed", "new_mortgage")) |>
  count(yr_mo, activity_type, name = "documents") |>
  pivot_wider(
    names_from = activity_type,
    values_from = documents,
    values_fill = 0L
  ) |>
  complete(
    yr_mo = analysis_months,
    fill = list(sale_deed = 0L, new_mortgage = 0L)
  ) |>
  arrange(yr_mo) |>
  transmute(
    month = yr_mo,
    deed_documents = sale_deed,
    new_mortgage_documents = new_mortgage,
    deed_yoy_pct = 100 * (deed_documents / lag(deed_documents, 12L) - 1),
    new_mortgage_yoy_pct =
      100 * (new_mortgage_documents / lag(new_mortgage_documents, 12L) - 1),
    recording_backlog_period = between(
      month,
      floor_date(recording_backlog_start, "month"),
      floor_date(recording_backlog_end, "month")
    ),
    period_status = if_else(
      year(month) == 2026L,
      "Observed through July 2026",
      "Complete month"
    )
  )

stopifnot(
  nrow(viz1_citywide_activity) == length(analysis_months),
  identical(viz1_citywide_activity$month, analysis_months)
)

# Diagnostic table for checking whether record-month activity is distorted by
# the time between receipt and recording. This remains a supporting QA export,
# not a separate client-facing chart.
viz1_recording_delay_diagnostics <- document_core |>
  filter(activity_type %in% c("sale_deed", "new_mortgage")) |>
  mutate(
    month = floor_date(record_date, "month"),
    valid_receipt_delay = if_else(
      recording_delay_from_receipt_days >= 0,
      recording_delay_from_receipt_days,
      NA_integer_
    )
  ) |>
  summarise(
    record_month_documents = n(),
    receipt_date_coverage_pct = mean(!is.na(receipt_date)),
    median_receipt_to_record_days = median(
      valid_receipt_delay,
      na.rm = TRUE
    ),
    p90_receipt_to_record_days = quantile(
      valid_receipt_delay,
      0.90,
      na.rm = TRUE,
      names = FALSE
    ),
    .by = c(month, activity_type)
  ) |>
  left_join(
    document_core |>
      filter(
        activity_type %in% c("sale_deed", "new_mortgage"),
        !is.na(receipt_date),
        receipt_date >= analysis_start,
        receipt_date <= analysis_end
      ) |>
      count(
        month = floor_date(receipt_date, "month"),
        activity_type,
        name = "receipt_month_documents"
      ),
    by = c("month", "activity_type")
  ) |>
  mutate(
    recording_backlog_period = between(
      month,
      floor_date(recording_backlog_start, "month"),
      floor_date(recording_backlog_end, "month")
    )
  ) |>
  arrange(activity_type, month)

activity_plot_data <- viz1_citywide_activity |>
  select(month, Deeds = deed_documents, `New mortgages` = new_mortgage_documents) |>
  pivot_longer(-month, names_to = "activity", values_to = "documents")

plot_activity <- ggplot(
  activity_plot_data,
  aes(x = month, y = documents, color = activity)
) +
  annotate(
    "rect",
    xmin = recording_backlog_start,
    xmax = recording_backlog_end,
    ymin = -Inf,
    ymax = Inf,
    fill = "#FEE6CE",
    alpha = 0.35
  ) +
  geom_line(linewidth = 0.55) +
  facet_wrap(vars(activity), ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("Deeds" = "#2C7FB8", "New mortgages" = "#D95F0E")) +
  scale_x_date(
    breaks = as.Date(c(
      paste0(seq(2000, 2024, 4), "-01-01"),
      "2026-07-01"
    )),
    date_labels = "%Y",
    expand = expansion(mult = c(0.01, 0.02))
  ) +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(
    title = "Philadelphia Property-Market Activity, 2000 - July 2026",
    subtitle = "Monthly recorded deed and new-mortgage documents",
    x = NULL,
    y = "Documents",
    caption = paste(
      "Philadelphia Realty Transfer Tax records; 2026 is observed through July.",
      "Shading marks July 2021-April 2022, when receipt-to-record delays",
      "distorted record-month counts."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(
      face = "bold",
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5
    ),
    axis.title.y = element_text(
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5,
      margin = margin(t = 12)
    )
  )

# =============================================================================
# VISUALIZATION 2: ANNUAL MEDIAN PRICE FOR ELIGIBLE SINGLE-PROPERTY DEEDS
# =============================================================================

eligible_property_sales <- document_core |>
  filter(
    activity_type == "sale_deed",
    document_type == "DEED",
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

viz2_citywide_property_price <- eligible_property_sales |>
  summarise(
    n_eligible_property_sales = n(),
    median_property_price = median(total_consideration),
    property_price_q25 = quantile(total_consideration, 0.25, names = FALSE),
    property_price_q75 = quantile(total_consideration, 0.75, names = FALSE),
    .by = c(year, period_status)
  ) |>
  arrange(year) |>
  mutate(
    geography = "City of Philadelphia",
    price_basis = "Nominal dollars",
    sample_definition = paste(
      "Exact DEED; one property; consideration > $100;",
      "known, non-nominal, and below the project high-value cutoff"
    )
  )

stopifnot(
  all(2000:2026 %in% viz2_citywide_property_price$year),
  viz2_citywide_property_price$period_status[
    viz2_citywide_property_price$year == 2026L
  ] == "January-July YTD"
)

plot_city_price <- ggplot(
  filter(viz2_citywide_property_price, year <= last_complete_year),
  aes(x = year, y = median_property_price)
) +
  geom_ribbon(
    aes(ymin = property_price_q25, ymax = property_price_q75),
    fill = "#08519C",
    alpha = 0.30
  ) +
  geom_line(color = "#08519C", linewidth = 0.9) +
  geom_point(color = "#08519C", size = 1.7) +
  geom_point(
    data = filter(viz2_citywide_property_price, year == 2026L),
    color = "#D95F0E",
    size = 3
  ) +
  geom_errorbar(
    data = filter(viz2_citywide_property_price, year == 2026L),
    aes(ymin = property_price_q25, ymax = property_price_q75),
    color = "#D95F0E",
    width = 0.25
  ) +
  annotate(
    "text",
    x = 2026,
    y = viz2_citywide_property_price$property_price_q75[
      viz2_citywide_property_price$year == 2026L
    ],
    label = "2026 YTD",
    hjust = 1.1,
    vjust = -0.7,
    color = "#D95F0E",
    size = 3.2
  ) +
  scale_x_continuous(
    breaks = c(seq(2000, 2025, 5), 2026),
    labels = c(
      as.character(seq(2000, 2025, 5)),
      "       2026"
    )
  ) +
  scale_y_continuous(labels = scales::label_dollar(scale = 0.001, suffix = "K")) +
  labs(
    title = "Median Recorded Property Price in Philadelphia",
    subtitle = "Eligible single-property deeds; band shows the interquartile range",
    x = NULL,
    y = "Median recorded property price (nominal $)",
    caption = paste(
      "Orange: January-July 2026 median and interquartile range;",
      "recorded deed consideration is not a complete-year observation."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(
      face = "bold",
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5,
      margin = margin(b = 12)
    ),
    axis.title.y = element_text(
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5,
      margin = margin(t = 12)
    )
  )

# =============================================================================
# VISUALIZATION 3: FIVE ZIP CODES WITH SIMILAR HISTORICAL GROWTH
# =============================================================================

zip_annual_prices <- eligible_property_sales |>
  filter(str_detect(zip5, "^191[0-9]{2}$")) |>
  summarise(
    n_eligible_property_sales = n(),
    median_property_price = median(total_consideration),
    property_price_q25 = quantile(total_consideration, 0.25, names = FALSE),
    property_price_q75 = quantile(total_consideration, 0.75, names = FALSE),
    .by = c(zip5, year, period_status)
  ) |>
  arrange(zip5, year) |>
  mutate(meets_minimum_sales = n_eligible_property_sales >= minimum_zip_sales)

citywide_selection_prices <- viz2_citywide_property_price |>
  filter(year %in% c(selection_start_year, last_complete_year))

if (nrow(citywide_selection_prices) != 2L) {
  stop("Citywide start/end prices are unavailable for ZIP selection.")
}

citywide_start_price <- citywide_selection_prices$median_property_price[
  citywide_selection_prices$year == selection_start_year
]
citywide_end_price <- citywide_selection_prices$median_property_price[
  citywide_selection_prices$year == last_complete_year
]
citywide_growth_years <- last_complete_year - selection_start_year
citywide_cagr <- (citywide_end_price / citywide_start_price) ^
  (1 / citywide_growth_years) - 1

zip_selection_candidates <- zip_annual_prices |>
  filter(
    year >= selection_start_year,
    year <= last_complete_year,
    meets_minimum_sales
  ) |>
  summarise(
    qualifying_years = n_distinct(year),
    start_price = first(median_property_price[year == selection_start_year], default = NA_real_),
    end_price = first(median_property_price[year == last_complete_year], default = NA_real_),
    .by = zip5
  ) |>
  filter(
    qualifying_years >= 9L,
    !is.na(start_price),
    !is.na(end_price),
    start_price > 0,
    end_price > 0
  ) |>
  mutate(
    historical_cagr = (end_price / start_price) ^ (1 / citywide_growth_years) - 1,
    citywide_cagr = citywide_cagr,
    absolute_cagr_gap = abs(historical_cagr - citywide_cagr)
  )

if (nrow(zip_selection_candidates) < 5L) {
  stop("Fewer than five ZIP codes meet the configured price-history criteria.")
}

if (zip_selection_rule == "similar_to_citywide") {
  selected_zip_codes <- zip_selection_candidates |>
    arrange(absolute_cagr_gap, desc(qualifying_years), zip5) |>
    slice_head(n = 5L)
} else {
  selected_zip_codes <- zip_selection_candidates |>
    arrange(desc(historical_cagr), desc(qualifying_years), zip5) |>
    slice_head(n = 5L)
}

selected_zip_codes <- selected_zip_codes |>
  mutate(
    selection_rank = row_number(),
    selection_rule = zip_selection_rule,
    selection_window = paste0(selection_start_year, "-", last_complete_year),
    minimum_annual_sales = minimum_zip_sales
  ) |>
  select(
    selection_rank,
    zip5,
    selection_rule,
    selection_window,
    qualifying_years,
    minimum_annual_sales,
    start_price,
    end_price,
    historical_cagr,
    citywide_cagr,
    absolute_cagr_gap
  )

selected_zip_vector <- selected_zip_codes$zip5
future_years <- seq.int(
  last_complete_year + 1L,
  last_complete_year + projection_years
)

fit_zip_scenario <- function(zip_value) {
  model_data <- zip_annual_prices |>
    filter(
      zip5 == zip_value,
      year >= model_start_year,
      year <= last_complete_year,
      meets_minimum_sales
    ) |>
    arrange(year)

  if (nrow(model_data) < 8L) {
    stop("Insufficient model data for ZIP ", zip_value, ".")
  }

  final_model <- lm(log(median_property_price) ~ year, data = model_data)
  prediction_matrix <- predict(
    final_model,
    newdata = tibble(year = future_years),
    interval = "prediction",
    level = 0.95
  )

  scenario <- tibble(
    zip5 = zip_value,
    year = future_years,
    series_type = "Projected scenario",
    n_eligible_property_sales = NA_integer_,
    observed_median_property_price = NA_real_,
    projected_median_property_price = exp(prediction_matrix[, "fit"]),
    projection_lower_95 = exp(prediction_matrix[, "lwr"]),
    projection_upper_95 = exp(prediction_matrix[, "upr"]),
    display_price = projected_median_property_price,
    period_status = "Projection"
  )

  holdout_data <- model_data |>
    filter(year >= 2021L)
  backtest_train <- model_data |>
    filter(year <= 2020L)

  if (nrow(backtest_train) >= 8L && nrow(holdout_data) > 0L) {
    backtest_model <- lm(log(median_property_price) ~ year, data = backtest_train)
    holdout_prediction_matrix <- predict(
      backtest_model,
      newdata = holdout_data,
      interval = "prediction",
      level = 0.95
    )
    holdout_prediction <- exp(holdout_prediction_matrix[, "fit"])
    holdout_lower_95 <- exp(holdout_prediction_matrix[, "lwr"])
    holdout_upper_95 <- exp(holdout_prediction_matrix[, "upr"])
    accuracy <- tibble(
      zip5 = zip_value,
      holdout_period = paste0(min(holdout_data$year), "-", max(holdout_data$year)),
      n_holdout_years = nrow(holdout_data),
      mean_absolute_error = mean(
        abs(holdout_data$median_property_price - holdout_prediction)
      ),
      root_mean_squared_error = sqrt(mean(
        (holdout_data$median_property_price - holdout_prediction) ^ 2
      )),
      mean_absolute_percentage_error = mean(
        abs(
          (holdout_data$median_property_price - holdout_prediction) /
            holdout_data$median_property_price
        )
      ),
      prediction_interval_coverage_95 = mean(
        holdout_data$median_property_price >= holdout_lower_95 &
          holdout_data$median_property_price <= holdout_upper_95
      ),
      mean_prediction_interval_width_95 = mean(
        holdout_upper_95 - holdout_lower_95
      ),
      model = "Log-linear annual trend",
      training_window = paste0(model_start_year, "-2020")
    )
  } else {
    accuracy <- tibble(
      zip5 = zip_value,
      holdout_period = NA_character_,
      n_holdout_years = 0L,
      mean_absolute_error = NA_real_,
      root_mean_squared_error = NA_real_,
      mean_absolute_percentage_error = NA_real_,
      prediction_interval_coverage_95 = NA_real_,
      mean_prediction_interval_width_95 = NA_real_,
      model = "Log-linear annual trend",
      training_window = paste0(model_start_year, "-2020")
    )
  }

  model_summary <- tibble(
    zip5 = zip_value,
    model_training_start = min(model_data$year),
    model_training_end = max(model_data$year),
    model_training_years = nrow(model_data),
    modeled_annual_growth_rate = unname(exp(coef(final_model)[["year"]]) - 1),
    model_r_squared = summary(final_model)$r.squared
  )

  list(scenario = scenario, accuracy = accuracy, model_summary = model_summary)
}

zip_model_results <- map(selected_zip_vector, fit_zip_scenario)
zip_projection_rows <- map_dfr(zip_model_results, "scenario")
viz3_zip_projection_accuracy <- map_dfr(zip_model_results, "accuracy")
zip_model_summaries <- map_dfr(zip_model_results, "model_summary")

selected_zip_codes <- selected_zip_codes |>
  left_join(zip_model_summaries, by = "zip5") |>
  left_join(viz3_zip_projection_accuracy, by = "zip5") |>
  mutate(
    price_basis = "Nominal dollars",
    interpretation = paste(
      "Scenario only; selected by historical complete-year growth and",
      "projected with a log-linear trend"
    )
  )

zip_history_rows <- zip_annual_prices |>
  filter(
    zip5 %in% selected_zip_vector,
    year <= last_complete_year,
    meets_minimum_sales
  ) |>
  transmute(
    zip5,
    year,
    series_type = "Historical",
    n_eligible_property_sales,
    observed_median_property_price = median_property_price,
    projected_median_property_price = NA_real_,
    projection_lower_95 = NA_real_,
    projection_upper_95 = NA_real_,
    display_price = observed_median_property_price,
    period_status
  )

zip_index_anchors <- zip_history_rows |>
  filter(year == last_complete_year) |>
  transmute(
    zip5,
    price_index_base_year = last_complete_year,
    price_index_base_value = observed_median_property_price
  )

viz3_zip_price_projection <- bind_rows(
  zip_history_rows,
  zip_projection_rows
) |>
  left_join(
    selected_zip_codes |>
      select(
        zip5,
        selection_rank,
        selection_rule,
        historical_cagr,
        citywide_cagr,
        modeled_annual_growth_rate,
        model_r_squared
      ),
    by = "zip5"
  ) |>
  left_join(zip_index_anchors, by = "zip5") |>
  mutate(
    model = "Log-linear annual trend",
    projection_horizon_years = projection_years,
    price_basis = "Nominal dollars",
    price_index_2025 = 100 * display_price / price_index_base_value,
    is_projection_checkpoint = series_type == "Projected scenario" &
      (year %% 5L == 0L | year == last_complete_year + projection_years)
  ) |>
  arrange(selection_rank, year, series_type)

stopifnot(
  n_distinct(viz3_zip_price_projection$zip5) == 5L,
  max(viz3_zip_price_projection$year) == last_complete_year + projection_years,
  !anyDuplicated(
    viz3_zip_price_projection[c("zip5", "year", "series_type")]
  )
)

zip_history_plot <- viz3_zip_price_projection |>
  filter(series_type == "Historical", year >= model_start_year)
zip_projection_plot <- viz3_zip_price_projection |>
  filter(series_type == "Projected scenario")

plot_zip_projection <- ggplot() +
  geom_ribbon(
    data = zip_projection_plot,
    aes(
      x = year,
      ymin = projection_lower_95,
      ymax = projection_upper_95,
      group = zip5
    ),
    fill = "#FDAE6B",
    alpha = 0.25
  ) +
  geom_line(
    data = zip_history_plot,
    aes(x = year, y = display_price),
    color = "#2171B5",
    linewidth = 0.8
  ) +
  geom_line(
    data = zip_projection_plot,
    aes(x = year, y = display_price),
    color = "#E6550D",
    linewidth = 0.8,
    linetype = "dashed"
  ) +
  geom_vline(xintercept = 2025.5, color = "grey45", linewidth = 0.4) +
  facet_wrap(vars(zip5), scales = "free_y") +
  scale_x_continuous(breaks = seq(2010, last_complete_year + projection_years, 5)) +
  scale_y_continuous(labels = scales::label_dollar(scale = 0.001, suffix = "K")) +
  labs(
    title = paste(
      "Five Philadelphia ZIP Codes That Most Closely Tracked",
      "Citywide Price Growth"
    ),
    subtitle = paste0(
      "Selected by similarity to Philadelphia's ",
      scales::percent(citywide_cagr, accuracy = 0.01),
      " annual price-growth rate, ", selection_start_year, "-",
      last_complete_year, "\n",
      "Blue shows observed prices; orange shows the ",
      projection_years,
      "-year scenario and 95% prediction interval"
    ),
    x = NULL,
    y = "Median recorded property price (nominal $)",
    caption = paste0(
      "ZIP selection: ", selection_start_year, "-", last_complete_year,
      " CAGR; scenario model: ", model_start_year, "-", last_complete_year,
      " log-linear trend. 2026 YTD excluded; 2021-2025 holdout retained."
    )
  ) +
  theme_minimal(base_size = 10.5) +
  theme(
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(
      face = "bold",
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5
    ),
    axis.title.y = element_text(
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5,
      margin = margin(t = 12)
    )
  )

# =============================================================================
# VISUALIZATION 4: ZIP-LEVEL PRICE AND INCOME CORRELATION MATRIX
# =============================================================================

correlation_input_path <- file.path(
  tableau_dir,
  "model_zip_price_income_correlations.csv"
)

if (!file.exists(correlation_input_path)) {
  stop(
    "Missing ", correlation_input_path,
    ". Run source(\"R/redfin_zip_etl.R\") and then ",
    "source(\"R/zip_affordability_etl.R\") first."
  )
}

correlation_variable_order <- c(
  "log_median_property_price",
  "log_median_household_income",
  "price_to_income_ratio",
  "n_eligible_sales"
)

correlation_variable_labels <- c(
  log_median_property_price = "Median sale price (log)",
  log_median_household_income = "Median household income (log)",
  price_to_income_ratio = "Price-to-income ratio",
  n_eligible_sales = "Median homes sold (rolling 90-day)"
)

all_zip_price_income_correlations <- read_csv(
  correlation_input_path,
  col_types = cols(
    price_source = col_character(),
    correlation_scope = col_character(),
    analysis_year = col_integer(),
    year_start = col_integer(),
    year_end = col_integer(),
    unique_zips = col_integer(),
    variable_x = col_character(),
    variable_y = col_character(),
    observations = col_integer(),
    pearson_correlation = col_double(),
    spearman_correlation = col_double()
  ),
  show_col_types = FALSE
) 

latest_correlation_year <- all_zip_price_income_correlations |>
  filter(
    price_source == "Redfin",
    correlation_scope == "Annual ZIP cross-section"
  ) |>
  summarise(latest_year = max(analysis_year, na.rm = TRUE)) |>
  pull(latest_year)

viz4_zip_price_income_correlations <- all_zip_price_income_correlations |>
  filter(
    price_source == "Redfin",
    correlation_scope == "Annual ZIP cross-section",
    analysis_year == latest_correlation_year,
    variable_x %in% correlation_variable_order,
    variable_y %in% correlation_variable_order
  ) |>
  mutate(
    variable_x_label = factor(
      recode(variable_x, !!!correlation_variable_labels),
      levels = unname(correlation_variable_labels[correlation_variable_order])
    ),
    variable_y_label = factor(
      recode(variable_y, !!!correlation_variable_labels),
      levels = rev(unname(correlation_variable_labels[correlation_variable_order]))
    ),
    displayed_correlation = spearman_correlation,
    displayed_method = "Spearman rank correlation",
    variable_x_index = match(variable_x, correlation_variable_order),
    variable_y_index = match(variable_y, correlation_variable_order),
    show_in_lower_triangle = variable_y_index > variable_x_index,
    label = scales::number(displayed_correlation, accuracy = 0.01)
  ) |>
  arrange(variable_y_label, variable_x_label)

correlation_sample_size <- viz4_zip_price_income_correlations |>
  summarise(sample_size = min(observations, na.rm = TRUE)) |>
  pull(sample_size)

stopifnot(
  nrow(viz4_zip_price_income_correlations) ==
    length(correlation_variable_order)^2,
  !anyDuplicated(
    viz4_zip_price_income_correlations[c("variable_x", "variable_y")]
  ),
  correlation_sample_size > 0,
  all(
    viz4_zip_price_income_correlations$displayed_correlation >= -1 &
      viz4_zip_price_income_correlations$displayed_correlation <= 1
  )
)

plot_affordability_correlation <- ggplot(
  filter(viz4_zip_price_income_correlations, show_in_lower_triangle),
  aes(
    x = variable_x_label,
    y = variable_y_label,
    fill = displayed_correlation
  )
) +
  geom_tile(color = "white", linewidth = 0.8) +
  geom_text(
    aes(
      label = label,
      color = abs(displayed_correlation) >= 0.55
    ),
    fontface = "bold",
    size = 4
  ) +
  scale_fill_gradient2(
    low = "#B2182B",
    mid = "#F7F7F7",
    high = "#2166AC",
    midpoint = 0,
    limits = c(-1, 1),
    breaks = seq(-1, 1, 0.5),
    name = "Spearman\ncorrelation"
  ) +
  scale_color_manual(
    values = c(`TRUE` = "white", `FALSE` = "grey20"),
    guide = "none"
  ) +
  coord_equal() +
  labs(
    title = "Philadelphia ZIP-Level Housing Affordability Relationships",
    subtitle = paste0(
      "Spearman correlations across ", correlation_sample_size,
      " eligible ZIPs in ", latest_correlation_year
    ),
    x = NULL,
    y = NULL,
    caption = paste(
      "One observation is one ZIP in 2024; lower triangle shown.",
      "ACS 2024 income pools 2020-2024 responses; price-to-income",
      "correlations are partly mechanical and do not imply causation.",
      sep = "\n"
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    axis.text.x = element_text(
      angle = 32,
      hjust = 1
    ),
    axis.text.y = element_text(
      hjust = 1
    ),
    # Center plot heading text
    plot.title = element_text(
      face = "bold",
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5
    ),
    # Center the bottom explanatory annotation/caption
    plot.caption = element_text(
      hjust = 0.5,
      margin = margin(t = 13)
    ),
    # Move legend farther right
    legend.position = "right",
    legend.box.margin = margin(
      t = 0,
      r = 0,
      b = 0,
      l = 14
    ),
    # Make legend title smaller and slightly closer/upward
    legend.title = element_text(
      size = 9,
      lineheight = 0.9,
      margin = margin(b = 10)
    ),
    # Make legend scale-number labels smaller
    legend.text = element_text(
      size = 8
    )
  )

# =============================================================================
# VISUALIZATION 5: MEDIAN ZIP-LEVEL PRICE-TO-INCOME TREND
# =============================================================================

affordability_panel_path <- file.path(
  tableau_dir,
  "fact_zip_price_income.csv"
)

if (!file.exists(affordability_panel_path)) {
  stop(
    "Missing ", affordability_panel_path,
    ". Run source(\"R/redfin_zip_etl.R\") and then ",
    "source(\"R/zip_affordability_etl.R\") first."
  )
}

viz5_zip_price_income_trend <- read_csv(
  affordability_panel_path,
  show_col_types = FALSE
) |>
  filter(
    price_source == "Redfin",
    year >= 2012L,
    year <= 2024L,
    meets_minimum_sales,
    !is.na(price_to_income_ratio),
    is.na(income_moe_pct) | income_moe_pct <= 0.50
  ) |>
  summarise(
    n_zip_observations = n(),
    median_price_to_income = median(price_to_income_ratio),
    price_to_income_q25 = quantile(
      price_to_income_ratio,
      0.25,
      names = FALSE
    ),
    price_to_income_q75 = quantile(
      price_to_income_ratio,
      0.75,
      names = FALSE
    ),
    .by = year
  ) |>
  arrange(year) |>
  mutate(
    geography = "Philadelphia ZIP codes",
    price_source = "Redfin All Residential",
    income_source = "ACS 5-year median household income",
    eligibility_definition = paste(
      "Minimum-sale rule, nonmissing price-to-income ratio,",
      "and ACS relative margin of error no greater than 50%"
    ),
    period_note = if_else(
      year == 2012L,
      "Partial Redfin year: available rolling periods",
      "Complete calendar year"
    )
  )

stopifnot(
  identical(as.integer(viz5_zip_price_income_trend$year), 2012:2024),
  all(viz5_zip_price_income_trend$n_zip_observations > 0),
  all(viz5_zip_price_income_trend$median_price_to_income > 0)
)

trend_start_ratio <- first(
  viz5_zip_price_income_trend$median_price_to_income
)
trend_end_ratio <- last(
  viz5_zip_price_income_trend$median_price_to_income
)
trend_peak_row <- viz5_zip_price_income_trend |>
  slice_max(median_price_to_income, n = 1, with_ties = FALSE)

trend_min_zip_count <- min(viz5_zip_price_income_trend$n_zip_observations)
trend_max_zip_count <- max(viz5_zip_price_income_trend$n_zip_observations)

trend_endpoint_labels <- viz5_zip_price_income_trend |>
  filter(year %in% c(min(year), max(year))) |>
  mutate(
    endpoint_label = paste0(
      year,
      ": ",
      scales::number(median_price_to_income, accuracy = 0.1),
      "x"
    )
  )

plot_affordability_trend <- ggplot(
  viz5_zip_price_income_trend,
  aes(x = year, y = median_price_to_income)
) +
  geom_ribbon(
    aes(ymin = price_to_income_q25, ymax = price_to_income_q75),
    fill = "#08519C",
    alpha = 0.30
  ) +
  geom_line(color = "#08519C", linewidth = 1) +
  geom_point(color = "#08519C", size = 2.2) +
  geom_text(
    data = trend_endpoint_labels,
    aes(label = endpoint_label),
    color = "#08519C",
    fontface = "bold",
    vjust = -0.9,
    size = 3.5
  ) +
  scale_x_continuous(breaks = 2012:2024) +
  scale_y_continuous(
    labels = scales::label_number(accuracy = 0.1, suffix = "x"),
    expand = expansion(mult = c(0.03, 0.10))
  ) +
  labs(
    title = "Philadelphia ZIP-Level Price-to-Income Ratio Increased",
    subtitle = paste0(
      "Median ratio rose from ",
      scales::number(trend_start_ratio, accuracy = 0.1),
      "x in 2012 to ",
      scales::number(trend_end_ratio, accuracy = 0.1),
      "x in 2024, after peaking at ",
      scales::number(trend_peak_row$median_price_to_income, accuracy = 0.1),
      "x in ", trend_peak_row$year
    ),
    x = NULL,
    y = "Median sale price / median household income",
    caption = paste(
      "Line: median across", trend_min_zip_count, "to", trend_max_zip_count,
      "eligible ZIPs per year; band: ZIP interquartile range.",
      "Eligibility applies minimum-sale and ACS reliability filters;",
      "2024 ACS income pools 2020-2024 responses."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(
      face = "bold",
      hjust = 0.5
    ),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5
    ),
    axis.title.y = element_text(
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5,
      margin = margin(t = 12)
    )
  )

# =============================================================================
# EXPORTS AND MANIFEST
# =============================================================================

# Show the completed charts in RStudio's Plots pane before writing the files.
# This makes it easier to adjust dimensions, labels, colors, or scales and
# immediately inspect the result. The check prevents plot windows from opening
# during non-interactive command-line runs such as `Rscript`.
if (interactive() && isTRUE(getOption("bsan.show_core_plots", TRUE))) {
  print(plot_activity)
  print(plot_city_price)
  print(plot_zip_projection)
  print(plot_affordability_correlation)
  print(plot_affordability_trend)
}

write_csv(
  viz1_citywide_activity,
  file.path(tableau_ingestion_dir, "viz1_citywide_activity.csv")
)
write_csv(
  viz1_recording_delay_diagnostics,
  file.path(tableau_dir, "viz1_recording_delay_diagnostics.csv")
)
write_csv(
  viz2_citywide_property_price,
  file.path(tableau_ingestion_dir, "viz2_citywide_property_price.csv")
)
write_csv(
  viz3_zip_price_projection,
  file.path(tableau_ingestion_dir, "viz3_zip_price_projection.csv")
)
write_csv(
  selected_zip_codes,
  file.path(tableau_dir, "viz3_selected_zip_codes.csv")
)
write_csv(
  viz3_zip_projection_accuracy,
  file.path(tableau_dir, "viz3_zip_projection_accuracy.csv")
)
write_csv(
  viz4_zip_price_income_correlations,
  file.path(tableau_ingestion_dir, "viz4_zip_price_income_correlations.csv")
)
write_csv(
  viz5_zip_price_income_trend,
  file.path(tableau_ingestion_dir, "viz5_zip_price_income_trend.csv")
)

ggsave(
  file.path(visual_dir, "01_citywide_activity_trends.png"),
  plot_activity,
  width = 11,
  height = 7.5,
  dpi = 200,
  bg = "white"
)
ggsave(
  file.path(visual_dir, "02_citywide_median_property_price.png"),
  plot_city_price,
  width = 11,
  height = 6.5,
  dpi = 200,
  bg = "white"
)
ggsave(
  file.path(visual_dir, "03_five_zip_price_projection.png"),
  plot_zip_projection,
  width = 12,
  height = 8,
  dpi = 200,
  bg = "white"
)
ggsave(
  file.path(visual_dir, "04_zip_price_income_correlation.png"),
  plot_affordability_correlation,
  width = 10.5,
  height = 8,
  dpi = 200,
  bg = "white"
)
ggsave(
  file.path(visual_dir, "05_zip_price_income_trend.png"),
  plot_affordability_trend,
  width = 11,
  height = 6.8,
  dpi = 200,
  bg = "white"
)

manifest_path <- file.path(tableau_dir, "README_export_manifest.csv")
manifest_additions <- tribble(
  ~file, ~grain, ~key, ~purpose,
  "tableau_ingestion/viz1_citywide_activity.csv", "month", "month",
  "Visualization 1: Philadelphia deed and new-mortgage activity through July 2026",
  "viz1_recording_delay_diagnostics.csv", "record month x activity type", "month + activity_type",
  "QA support: record-month versus receipt-month activity and receipt-to-record delay",
  "tableau_ingestion/viz2_citywide_property_price.csv", "year", "year",
  "Visualization 2: annual citywide eligible single-property median price, including 2026 YTD",
  "tableau_ingestion/viz3_zip_price_projection.csv", "ZIP x year x series", "zip5 + year + series_type",
  "Visualization 3: observed prices and 10-15 year scenario for five selected ZIP codes",
  "viz3_selected_zip_codes.csv", "selected ZIP", "zip5",
  "ZIP selection, historical growth, fitted trend, and validation diagnostics",
  "viz3_zip_projection_accuracy.csv", "selected ZIP", "zip5",
  "Five-year holdout accuracy for the ZIP scenario model",
  "tableau_ingestion/viz4_zip_price_income_correlations.csv", "2024 variable pair", "variable_x + variable_y",
  "Visualization 4: 2024 Redfin-ACS cross-sectional correlations with lower-triangle display flag",
  "tableau_ingestion/viz5_zip_price_income_trend.csv", "year", "year",
  "Visualization 5: median ZIP-level price-to-income ratio and interquartile range, 2012-2024"
)

legacy_dashboard_files <- c(
  "viz1_citywide_activity.csv",
  "viz2_citywide_property_price.csv",
  "viz3_zip_price_projection.csv",
  "viz4_zip_price_income_correlations.csv",
  "viz5_zip_price_income_trend.csv"
)

if (file.exists(manifest_path)) {
  existing_manifest <- read_csv(manifest_path, show_col_types = FALSE)
  updated_manifest <- bind_rows(
    filter(
      existing_manifest,
      !file %in% c(manifest_additions$file, legacy_dashboard_files)
    ),
    manifest_additions
  )
} else {
  updated_manifest <- manifest_additions
}

write_csv(updated_manifest, manifest_path)

message(
  "Tableau ingestion files written to ", tableau_ingestion_dir,
  "/; support files remain in ", tableau_dir,
  "/; PNGs written to ", visual_dir, "/. Selected ZIPs: ",
  paste(selected_zip_vector, collapse = ", "), "."
)
