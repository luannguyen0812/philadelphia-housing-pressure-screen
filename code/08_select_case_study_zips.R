# =============================================================================
# 08. APPLY THE COVERAGE GATE AND SELECT THE CASE-STUDY ZIPS
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Scores every measurable Philadelphia ZIP/ZCTA on growth and vulnerability,
#   applies the coverage gate (48 measured, 37 pass), retains 19132 and 19143
#   as the detailed pair, and reproduces the sale-to-assessment method for the
#   internal record only.
# INPUTS
#   tableau_data/fact_zip_price_income.csv
#   external_data/acs_zcta_vulnerability.csv
#   external_data/raw/FRED_CPIAUCSL.csv
# OUTPUTS
#   tableau_data/week04_zip_selection_scorecard.csv
#   tableau_data/week04_two_zip_panel.csv
#   tableau_data/week04_coverage_report.csv
#   tableau_data/week04_five_zip_transaction_activity.csv
#   tableau_data/week04_assessment_coverage.csv
#   tableau_data/week04_sale_to_assessment.csv
#   visualizations/week04_*.png  (five charts)
# RUNS AFTER   07
# =============================================================================

# Every stage reads the project root and the code folder from one place.
# If you opened this file on its own, this line loads that configuration
# first; run_all.R has already loaded it when the full pipeline runs.
if (!exists("code_dir")) source("00_config.R")

library(tidyverse)

# =============================================================================
# WEEK 04: TWO-ZIP SELECTION, JOINED PANEL, COVERAGE, AND PRELIMINARY CHARTS
# =============================================================================
# ABSTRACT
# This script screens five Philadelphia ZIP/ZCTAs and evaluates whether 19132
# and 19143 are defensible detailed case studies for the final housing-pressure
# and potential-displacement analysis. It combines
# Redfin market prices, ACS household income and vulnerability measures,
# Philadelphia Realty Transfer Tax sale records and assessed values. A single
# supporting FRED series, CPIAUCSL, is used only to express price and income
# trends in constant 2024 dollars; it is not an additional housing dataset and
# does not affect ZIP selection, vulnerability, price-to-income, or assessment
# ratios. The script checks transaction volume and data coverage, compares
# 2015-2024 market growth with 2024 resident vulnerability, builds a joined
# two-ZIP panel, compares transaction activity across the five candidates, and
# reproduces the previously presented 2014+ sale-to-assessment method for the
# project record. It exports documented CSV tables and presentation-ready
# charts for selection rationale, price-versus-income change, transaction
# activity, vulnerability profiles, and assessment alignment. Results screen
# for housing pressure and potential displacement risk; they do not establish
# that gentrification or household displacement occurred. ZIP and ZCTA
# boundaries are approximate, ACS five-year estimates overlap, and the RTT
# assessed-value field has no explicit assessment-year column.
#
# Run after:
#   source("03_clean_philadelphia_transfers.R")
#   source("04_normalize_redfin_zip_data.R")
#   source("05_build_zip_affordability.R")
#   source("07_build_acs_vulnerability.R")
#
# The group-proposed pair remains explicit and auditable. It is confirmed only
# if the decision-gate fields in week04_zip_selection_scorecard.csv are TRUE.

# =============================================================================
# 1. ANALYSIS SETTINGS AND REQUIRED FILES
# =============================================================================
# Caption: Define the proposed case-study ZIPs and every upstream file used by
# this script. Keeping these choices together makes reruns and review easier.

# “ZIP codes 19132 and 19143 were preselected and then retained as comparative Philadelphia 
# case studies because both met predefined data-coverage thresholds across Redfin, ACS, 
# and RTT records, while the pair showed a meaningful contrast in housing-price 
# growth and/or resident vulnerability.”

selected_zips <- getOption("bsan.week04_selected_zips", c("19132", "19143"))
if (length(selected_zips) != 2L || anyDuplicated(selected_zips)) {
  stop("bsan.week04_selected_zips must contain exactly two distinct ZIPs.")
}

# Caption: Limit the presentation matrix to five interpretable candidates. The
# selected pair represents high growth and high vulnerability; 19122, 19138,
# and 19119 provide upper-left, lower-right, and lower-left contrasts using the
# citywide qualifying-candidate medians as quadrant boundaries.
candidate_zips <- getOption(
  "bsan.week04_candidate_zips",
  c("19132", "19143", "19122", "19138", "19119")
)
if (
  length(candidate_zips) != 5L ||
    anyDuplicated(candidate_zips) ||
    !all(selected_zips %in% candidate_zips)
) {
  stop(
    "bsan.week04_candidate_zips must contain five distinct ZIPs, including ",
    "both selected case-study ZIPs."
  )
}

paths <- list(
  affordability = file.path("tableau_data", "fact_zip_price_income.csv"),
  vulnerability = file.path("external_data", "acs_zcta_vulnerability.csv"),
  parcels = file.path("team_data", "data_clean.csv.gz"),
  cpi = file.path("external_data", "raw", "FRED_CPIAUCSL.csv")
)

# Caption: Stop early when an upstream build is missing. FRED CPIAUCSL is the
# only supporting input this script may download automatically. It is needed
# solely for the plan's constant-dollar price and income comparison.
missing_inputs <- names(paths)[!file.exists(unlist(paths))]
if (length(missing_inputs) > 0L && !identical(missing_inputs, "cpi")) {
  stop("Missing Week 4 input(s): ", paste(missing_inputs, collapse = ", "))
}

if (!file.exists(paths$cpi)) {
  message("Downloading FRED CPIAUCSL for inflation adjustment...")
  download.file(
    paste0(
      "https://fred.stlouisfed.org/graph/fredgraph.csv?",
      "cosd=2012-01-01&coed=2024-12-31&id=CPIAUCSL"
    ),
    paths$cpi,
    mode = "wb",
    quiet = TRUE
  )
}

# Caption: Create only the two folders that receive Week 4 outputs.
dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# 2. LOAD THE AFFORDABILITY, VULNERABILITY, AND INFLATION INPUTS
# =============================================================================
# Caption: Load the previously validated ZIP price/income and ACS vulnerability
# tables. ZIP codes remain character fields so leading zeroes cannot be lost.

affordability <- read_csv(
  paths$affordability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)
vulnerability <- read_csv(
  paths$vulnerability,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
)

# Caption: Convert monthly FRED CPIAUCSL observations to annual averages. This
# adjustment is used only for `*_2024_dollars` fields and the indexed trend
# chart. Nominal Redfin prices remain the basis for selection CAGR, and CPI is
# unnecessary for price-to-income because both numerator and denominator are
# measured in current dollars for the same year.
cpi_annual <- read_csv(paths$cpi, show_col_types = FALSE) |>
  transmute(
    date = as.Date(observation_date),
    year = lubridate::year(date),
    cpi = as.numeric(CPIAUCSL)
  ) |>
  filter(year %in% 2012:2024) |>
  summarise(cpi = mean(cpi, na.rm = TRUE), .by = year)

cpi_2024 <- cpi_annual$cpi[cpi_annual$year == 2024L]
stopifnot(length(cpi_2024) == 1L, !is.na(cpi_2024))

# =============================================================================
# 3. BUILD THE 2012-2024 REDFIN/ACS MARKET PANEL
# =============================================================================
# Caption: Retain the validated Redfin series, join annual CPI, and create
# inflation-adjusted price and household-income measures.

redfin_panel <- affordability |>
  filter(price_source == "Redfin", year %in% 2012:2024) |>
  select(
    zip5,
    year,
    redfin_period_status = period_status,
    redfin_typical_homes_sold = n_eligible_sales,
    redfin_median_sale_price = median_property_price,
    redfin_price_q25 = property_price_q25,
    redfin_price_q75 = property_price_q75,
    redfin_months_observed = months_observed,
    meets_minimum_redfin_sales = meets_minimum_sales,
    median_household_income,
    median_household_income_moe,
    income_moe_pct,
    acs_income_period = acs_estimate_period,
    price_to_income_ratio
  ) |>
  left_join(cpi_annual, by = "year") |>
  mutate(
    redfin_price_2024_dollars = redfin_median_sale_price * cpi_2024 / cpi,
    income_2024_dollars = median_household_income * cpi_2024 / cpi
  )

# Caption: Build a Philadelphia comparison as the median across qualifying
# 191xx ZIP/ZCTA rows. This is not a transaction-weighted city estimate.
philadelphia_benchmark <- redfin_panel |>
  filter(meets_minimum_redfin_sales, !is.na(median_household_income)) |>
  summarise(
    redfin_median_sale_price = median(redfin_median_sale_price, na.rm = TRUE),
    redfin_price_2024_dollars = median(redfin_price_2024_dollars, na.rm = TRUE),
    median_household_income = median(median_household_income, na.rm = TRUE),
    income_2024_dollars = median(income_2024_dollars, na.rm = TRUE),
    price_to_income_ratio = median(price_to_income_ratio, na.rm = TRUE),
    .by = year
  ) |>
  mutate(zip5 = "Philadelphia ZIP median", geography_type = "benchmark")

# Caption: Join the proposed two ZIPs to the ACS vulnerability measures and
# flag estimates whose margins of error warrant a presentation warning.
week04_two_zip_panel <- redfin_panel |>
  filter(zip5 %in% selected_zips) |>
  left_join(vulnerability, by = c("zip5", "year")) |>
  mutate(
    geography_type = "selected ZIP/ZCTA case study",
    income_moe_warning = income_moe_pct > 0.20,
    vulnerability_moe_warning = if_any(
      c(
        renter_share_moe,
        renter_cost_burden_moe,
        poverty_rate_moe,
        senior_share_moe,
        recent_mover_share_moe
      ),
      ~ .x > 0.10
    )
  ) |>
  arrange(zip5, year)

# =============================================================================
# 4. BUILD THE CITYWIDE ZIP-SELECTION SCORECARD
# =============================================================================
# Caption: Measure market pressure with the common 2015-2024 Redfin CAGR and
# require adequate Redfin activity at both endpoints.

selection_growth <- redfin_panel |>
  filter(year %in% c(2015L, 2024L)) |>
  select(zip5, year, redfin_median_sale_price, meets_minimum_redfin_sales) |>
  pivot_wider(
    names_from = year,
    values_from = c(redfin_median_sale_price, meets_minimum_redfin_sales),
    names_sep = "_"
  ) |>
  mutate(
    redfin_2015_2024_cagr =
      (redfin_median_sale_price_2024 / redfin_median_sale_price_2015)^(1 / 9) - 1,
    adequate_endpoint_sales =
      meets_minimum_redfin_sales_2015 & meets_minimum_redfin_sales_2024
  )

# Caption: Verify that annual Philadelphia RTT sale counts are sufficiently
# large throughout the 2012-2024 comparison period.
selection_rtt_coverage <- affordability |>
  filter(price_source == "Philadelphia RTT", year %in% 2012:2024) |>
  summarise(
    rtt_years = n_distinct(year),
    minimum_annual_rtt_sales = min(n_eligible_sales, na.rm = TRUE),
    rtt_years_below_30_sales = sum(n_eligible_sales < 30, na.rm = TRUE),
    .by = zip5
  )

# Caption: Summarize resident vulnerability using the mean Philadelphia
# percentile for renter share, rent burden, poverty, and senior population.
selection_vulnerability <- vulnerability |>
  filter(year == 2024L) |>
  select(
    zip5,
    renter_share,
    renter_cost_burden,
    poverty_rate,
    senior_share,
    owner_cost_burden,
    recent_mover_share
  ) |>
  mutate(
    across(
      c(renter_share, renter_cost_burden, poverty_rate, senior_share),
      ~ percent_rank(.x),
      .names = "pct_rank_{.col}"
    ),
    vulnerability_percentile = rowMeans(
      pick(starts_with("pct_rank_")), na.rm = TRUE
    )
  )

# Caption: Evaluate Redfin/ACS income coverage for every candidate ZIP. This is
# calculated citywide rather than only after the two ZIPs have been selected.
first_year_or_na <- function(x) {
  if (length(x) == 0L) NA_integer_ else min(x)
}

last_year_or_na <- function(x) {
  if (length(x) == 0L) NA_integer_ else max(x)
}

coverage_by_zip <- redfin_panel |>
  summarise(
    common_years = n_distinct(year[!is.na(redfin_median_sale_price) &
      !is.na(median_household_income)]),
    first_common_year = first_year_or_na(
      year[!is.na(redfin_median_sale_price) & !is.na(median_household_income)]
    ),
    last_common_year = last_year_or_na(
      year[!is.na(redfin_median_sale_price) & !is.na(median_household_income)]
    ),
    complete_redfin_years = sum(redfin_months_observed == 12L, na.rm = TRUE),
    low_redfin_volume_years = sum(!meets_minimum_redfin_sales, na.rm = TRUE),
    income_moe_warning_years = sum(income_moe_pct > 0.20, na.rm = TRUE),
    .by = zip5
  )

# Caption: Count vulnerability MOE warnings separately because keyless ACS
# bulk files supply those measures for 2021-2024 rather than the full panel.
vulnerability_coverage_by_zip <- vulnerability |>
  mutate(
    vulnerability_moe_warning = if_any(
      c(
        renter_share_moe,
        renter_cost_burden_moe,
        poverty_rate_moe,
        senior_share_moe,
        recent_mover_share_moe
      ),
      ~ .x > 0.10
    )
  ) |>
  summarise(
    vulnerability_years = n_distinct(year),
    vulnerability_moe_warning_years = sum(
      vulnerability_moe_warning, na.rm = TRUE
    ),
    .by = zip5
  )

# Caption: Combine market growth, vulnerability, transaction coverage, and
# uncertainty checks into one auditable candidate table.
week04_zip_selection_scorecard <- selection_growth |>
  left_join(selection_vulnerability, by = "zip5") |>
  left_join(selection_rtt_coverage, by = "zip5") |>
  left_join(coverage_by_zip, by = "zip5") |>
  left_join(vulnerability_coverage_by_zip, by = "zip5") |>
  mutate(
    market_growth_rank = min_rank(desc(redfin_2015_2024_cagr)),
    vulnerability_rank = min_rank(desc(vulnerability_percentile)),
    included_in_five_zip_screen = zip5 %in% candidate_zips,
    selected_for_case_study = zip5 %in% selected_zips,
    coverage_gate_pass = adequate_endpoint_sales &
      coalesce(rtt_years == 13L, FALSE) &
      coalesce(rtt_years_below_30_sales == 0L, FALSE) &
      coalesce(common_years >= 13L, FALSE) &
      coalesce(last_common_year == 2024L, FALSE),
    selection_rule = paste(
      "Adequate 2015/2024 sales and complete 2012-2024 Redfin/ACS coverage;",
      "retain the proposed pair when it shows a meaningful contrast in",
      "2015-2024 market growth and/or 2024 resident vulnerability."
    )
  ) |>
  arrange(desc(selected_for_case_study), desc(redfin_2015_2024_cagr))

# Caption: Apply the predeclared pair-level contrast rule. The proposed pair
# passes when growth differs by at least 3 points or vulnerability by 15 points.
selected_pair_metrics <- week04_zip_selection_scorecard |>
  filter(selected_for_case_study) |>
  summarise(
    selected_pair_growth_gap = diff(range(redfin_2015_2024_cagr)),
    selected_pair_vulnerability_gap = diff(range(vulnerability_percentile)),
    meaningful_contrast_gate_pass =
      selected_pair_growth_gap >= 0.03 |
      selected_pair_vulnerability_gap >= 0.15,
    selected_pair_coverage_gate_pass = all(coverage_gate_pass)
  )

# Caption: Build an annual transaction-activity panel for the five presentation
# candidates. Dividing eligible RTT sales by the 2024 ACS occupied-housing-unit
# estimate makes ZIPs of different sizes more comparable. The housing-stock
# denominator is held fixed, so changes reflect transaction counts rather than
# shifts in the ACS denominator.
candidate_housing_stock <- vulnerability |>
  filter(year == 2024L, zip5 %in% candidate_zips) |>
  select(zip5, occupied_housing_units)

week04_five_zip_transaction_activity <- affordability |>
  filter(
    price_source == "Philadelphia RTT",
    zip5 %in% candidate_zips,
    year %in% 2015:2024
  ) |>
  select(
    zip5,
    year,
    n_eligible_sales,
    median_property_price,
    meets_minimum_sales
  ) |>
  left_join(candidate_housing_stock, by = "zip5") |>
  mutate(
    transactions_per_1000_occupied_units =
      1000 * n_eligible_sales / occupied_housing_units,
    comparison_period = case_when(
      year %in% 2015:2017 ~ "2015-2017",
      year %in% 2022:2024 ~ "2022-2024",
      TRUE ~ "Intermediate year"
    )
  ) |>
  arrange(zip5, year)

# Caption: Average three years at each endpoint so the presentation comparison
# is less sensitive to an unusual single transaction year.
transaction_period_summary <- week04_five_zip_transaction_activity |>
  filter(comparison_period != "Intermediate year") |>
  summarise(
    average_annual_transactions = mean(n_eligible_sales, na.rm = TRUE),
    average_transactions_per_1000 = mean(
      transactions_per_1000_occupied_units,
      na.rm = TRUE
    ),
    .by = c(zip5, comparison_period)
  ) |>
  left_join(
    week04_zip_selection_scorecard |>
      select(zip5, redfin_2015_2024_cagr, vulnerability_percentile),
    by = "zip5"
  ) |>
  mutate(
    comparison_period = factor(
      comparison_period,
      levels = c("2015-2017", "2022-2024")
    ),
    zip5 = factor(zip5, levels = candidate_zips)
  )

# Caption: Attach the pair-level decision gates only to the two selected rows so
# the reason for retaining the pair is visible in the exported scorecard.
week04_zip_selection_scorecard <- week04_zip_selection_scorecard |>
  mutate(
    selected_pair_growth_gap = if_else(
      selected_for_case_study,
      selected_pair_metrics$selected_pair_growth_gap,
      NA_real_
    ),
    selected_pair_vulnerability_gap = if_else(
      selected_for_case_study,
      selected_pair_metrics$selected_pair_vulnerability_gap,
      NA_real_
    ),
    meaningful_contrast_gate_pass = if_else(
      selected_for_case_study,
      selected_pair_metrics$meaningful_contrast_gate_pass,
      NA
    ),
    selected_pair_coverage_gate_pass = if_else(
      selected_for_case_study,
      selected_pair_metrics$selected_pair_coverage_gate_pass,
      NA
    )
  )

# =============================================================================
# 5. REPRODUCE THE PRESENTED SALE-TO-ASSESSMENT METHOD FOR THE PROJECT RECORD
# =============================================================================
# Caption: Load the parcel-level RTT fields used in the presented citywide
# chart. The slide specifies exact DEED, single-property, known-price,
# non-nominal, non-outlier sales and begins in 2014 after Philadelphia's Actual
# Value Initiative. The source still has no explicit assessment-year column,
# so this output is retained as a reproducible internal record with that caveat.
parcel_assessment <- read_csv(
  paths$parcels,
  col_select = c(
    record_id,
    document_id,
    document_type,
    activity_type,
    record_date,
    year,
    zip5,
    property_count,
    total_consideration,
    assessed_value,
    nominal_transfer,
    unknown_consideration,
    high_value_sale_outlier
  ),
  col_types = cols(
    record_id = col_character(),
    document_id = col_character(),
    document_type = col_character(),
    activity_type = col_character(),
    record_date = col_date(),
    year = col_integer(),
    zip5 = col_character(),
    property_count = col_integer(),
    total_consideration = col_double(),
    assessed_value = col_double(),
    nominal_transfer = col_logical(),
    unknown_consideration = col_logical(),
    high_value_sale_outlier = col_logical()
  ),
  show_col_types = FALSE
) |>
  filter(zip5 %in% selected_zips, year %in% 2014:2025)

# Caption: Apply the slide's eligibility rule once at property level. Computing
# each property's ratio before the annual median avoids a ratio-of-medians error.
eligible_assessment_sales <- parcel_assessment |>
  filter(
    document_type == "DEED",
    activity_type == "sale_deed",
    property_count == 1L,
    !nominal_transfer,
    !unknown_consideration,
    !high_value_sale_outlier,
    total_consideration > 100,
    assessed_value > 0
  ) |>
  mutate(sale_to_assessment_ratio = total_consideration / assessed_value)

# Caption: Report the annual median, middle 50%, and eligible sale count for
# each selected ZIP using the same summary displayed in the provided slide.
week04_sale_to_assessment <- eligible_assessment_sales |>
  summarise(
    n_eligible_sales = n(),
    median_sale_price = median(total_consideration),
    median_assessed_value = median(assessed_value),
    sale_to_assessment_q25 = quantile(
      sale_to_assessment_ratio, 0.25, names = FALSE
    ),
    median_sale_to_assessment_ratio = median(sale_to_assessment_ratio),
    sale_to_assessment_q75 = quantile(
      sale_to_assessment_ratio, 0.75, names = FALSE
    ),
    assessment_timing_status = paste(
      "Reproduces presented RTT method; assessed_value has no explicit",
      "assessment-year column."
    ),
    .by = c(zip5, year)
  ) |>
  arrange(zip5, year)

# Caption: Preserve the broader denominator and assessment availability by ZIP
# and year, including records that fail the final assessed-value requirement.
week04_assessment_coverage <- parcel_assessment |>
  summarise(
    all_parcel_records = n(),
    exact_deed_records = sum(document_type == "DEED"),
    eligible_single_property_sales = sum(
      document_type == "DEED" &
        activity_type == "sale_deed" &
        property_count == 1L &
        !nominal_transfer &
        !unknown_consideration &
        !high_value_sale_outlier &
        total_consideration > 100,
      na.rm = TRUE
    ),
    eligible_with_assessment = sum(
      document_type == "DEED" &
        activity_type == "sale_deed" &
        property_count == 1L &
        !nominal_transfer &
        !unknown_consideration &
        !high_value_sale_outlier &
        total_consideration > 100 &
        assessed_value > 0,
      na.rm = TRUE
    ),
    assessment_coverage_pct =
      eligible_with_assessment / eligible_single_property_sales,
    assessment_year_available = FALSE,
    publish_sale_to_assessment = FALSE,
    hold_reason = paste(
      "Reproduced for the Week 4 record using the presented 2014+ method;",
      "assessment timing cannot be independently verified from RTT alone."
    ),
    .by = c(zip5, year)
  ) |>
  arrange(zip5, year)

# =============================================================================
# 6. BUILD THE YEAR-LEVEL COVERAGE AND MISSINGNESS REPORT
# =============================================================================
# Caption: Combine market, income, vulnerability, and assessment diagnostics in
# one row per selected ZIP-year for review before Week 5.

week04_coverage_report <- week04_two_zip_panel |>
  transmute(
    zip5,
    year,
    redfin_months_observed,
    redfin_typical_homes_sold,
    meets_minimum_redfin_sales,
    has_income = !is.na(median_household_income),
    has_vulnerability_fields = if_all(
      c(renter_share, renter_cost_burden, poverty_rate, senior_share),
      ~ !is.na(.x)
    ),
    income_moe_pct,
    income_moe_warning,
    vulnerability_moe_warning
  ) |>
  left_join(
    week04_assessment_coverage |>
      select(
        zip5,
        year,
        eligible_single_property_sales,
        eligible_with_assessment,
        assessment_coverage_pct,
        assessment_year_available,
        publish_sale_to_assessment
      ),
    by = c("zip5", "year")
  ) |>
  arrange(zip5, year)

# =============================================================================
# 7. EXPORT THE WEEK 4 ANALYTICAL TABLES
# =============================================================================
# Caption: Write compact, Git-friendly CSV outputs for Tableau and team review.

write_csv(
  week04_two_zip_panel,
  file.path("tableau_data", "week04_two_zip_panel.csv")
)
write_csv(
  week04_zip_selection_scorecard,
  file.path("tableau_data", "week04_zip_selection_scorecard.csv")
)
write_csv(
  week04_coverage_report,
  file.path("tableau_data", "week04_coverage_report.csv")
)
write_csv(
  week04_assessment_coverage,
  file.path("tableau_data", "week04_assessment_coverage.csv")
)
write_csv(
  week04_sale_to_assessment,
  file.path("tableau_data", "week04_sale_to_assessment.csv")
)
write_csv(
  week04_five_zip_transaction_activity,
  file.path("tableau_data", "week04_five_zip_transaction_activity.csv")
)

# =============================================================================
# VISUALIZATION 1 — INFLATION-ADJUSTED PRICE AND INCOME TRENDS
# =============================================================================
# How many mismatches within 2015-2024 that we can't join, and whether it has any effects. 
# Purpose: Compare how real sale prices and household incomes changed after
# setting both measures equal to 100 in the common 2015 base year.
# Caption: Index price and income to 2015 so different dollar scales do not
# obscure whether sale prices are separating from resident incomes.

plot_panel <- bind_rows(
  week04_two_zip_panel |>
    select(
      zip5,
      year,
      price = redfin_price_2024_dollars,
      income = income_2024_dollars,
      price_to_income_ratio
    ) |>
    mutate(geography_type = "Selected ZIP/ZCTA"),
  philadelphia_benchmark |>
    select(zip5, year, price = redfin_price_2024_dollars,
      income = income_2024_dollars, price_to_income_ratio, geography_type)
) |>
  group_by(zip5) |>
  mutate(
    indexed_price = 100 * price / price[year == 2015L],
    indexed_income = 100 * income / income[year == 2015L]
  ) |>
  ungroup() |>
  select(zip5, year, `Sale price` = indexed_price, Income = indexed_income) |>
  pivot_longer(c(`Sale price`, Income), names_to = "measure", values_to = "index")

preliminary_plot <- ggplot(
  plot_panel,
  aes(year, index, color = zip5, linetype = measure)
) +
  geom_hline(yintercept = 100, color = "grey75", linewidth = 0.4) +
  geom_line(linewidth = 0.9) +
  facet_wrap(vars(zip5), ncol = 1) +
  scale_x_continuous(breaks = seq(2015, 2024, 3)) +
  scale_color_manual(values = c(
    "19132" = "#D95F0E",
    "19143" = "#08519C",
    "Philadelphia ZIP median" = "#555555"
  )) +
  labs(
    title = "Preliminary Inflation-Adjusted Price and Income Trends",
    subtitle = "2015 = 100; selected ZIP/ZCTAs and median across qualifying Philadelphia ZIPs",
    x = NULL,
    y = "Index (2015 = 100)",
    color = NULL,
    linetype = NULL,
    caption = paste(
      "Redfin rolling 90-day price observations; ACS 5-year household income;",
      "CPIAUCSL annual average. ZIP/ZCTA joins are approximate."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
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

ggsave(
  file.path("visualizations", "week04_preliminary_indexed_trends.png"),
  preliminary_plot,
  width = 9,
  height = 8,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 2 — ZIP-SELECTION MATRIX
# =============================================================================
# Purpose: Compare a readable five-ZIP candidate set while retaining citywide
# qualifying-candidate medians as the quadrant thresholds.
# Caption: The two selected case studies occupy the high-growth,
# high-vulnerability quadrant. Three comparison ZIPs show why the other
# quadrants imply different levels or types of housing-pressure concern.

selection_reference_data <- week04_zip_selection_scorecard |>
  filter(
    coverage_gate_pass,
    !is.na(redfin_2015_2024_cagr),
    !is.na(vulnerability_percentile)
  )

selection_growth_median <- median(
  selection_reference_data$redfin_2015_2024_cagr
)
selection_vulnerability_median <- median(
  selection_reference_data$vulnerability_percentile
)

selection_plot_data <- selection_reference_data |>
  filter(zip5 %in% candidate_zips) |>
  mutate(
    display_group = if_else(
      selected_for_case_study,
      "Detailed case study",
      "Comparison ZIP/ZCTA"
    ),
    quadrant = case_when(
      redfin_2015_2024_cagr >= selection_growth_median &
        vulnerability_percentile >= selection_vulnerability_median ~
        "High growth / high vulnerability",
      redfin_2015_2024_cagr >= selection_growth_median ~
        "High growth / lower vulnerability",
      vulnerability_percentile >= selection_vulnerability_median ~
        "Lower growth / high vulnerability",
      TRUE ~ "Lower growth / lower vulnerability"
    )
  )

stopifnot(
  nrow(selection_plot_data) == 5L,
  all(
    selection_plot_data$quadrant[selection_plot_data$selected_for_case_study] ==
      "High growth / high vulnerability"
  )
)

selection_matrix_plot <- ggplot(
  selection_plot_data,
  aes(redfin_2015_2024_cagr, vulnerability_percentile)
) +
  geom_vline(
    xintercept = selection_growth_median,
    color = "black",
    linetype = "dashed",
    linewidth = 1.1
  ) +
  geom_hline(
    yintercept = selection_vulnerability_median,
    color = "black",
    linetype = "dashed",
    linewidth = 1.1
  ) +
  geom_point(
    aes(color = display_group, size = display_group),
    alpha = 0.95
  ) +
  geom_text(
    aes(label = zip5),
    nudge_y = 0.018,
    show.legend = FALSE,
    size = 4,
    fontface = "bold"
  ) +
  scale_color_manual(values = c(
    "Detailed case study" = "#D95F0E",
    "Comparison ZIP/ZCTA" = "#08519C"
  )) +
  scale_size_manual(values = c(
    "Detailed case study" = 5.2,
    "Comparison ZIP/ZCTA" = 3.6
  )) +
  scale_x_continuous(
    labels = scales::label_percent(accuracy = 1),
    expand = expansion(mult = c(0.10, 0.14))
  ) +
  scale_y_continuous(
    labels = scales::label_percent(accuracy = 1),
    expand = expansion(mult = c(0.10, 0.16))
  ) +
  labs(
    title = "19132 and 19143 Combine High Growth with High Vulnerability",
    subtitle = "Five-ZIP screen; dashed lines are medians across all qualifying Philadelphia ZIP/ZCTAs",
    x = "Redfin median-price CAGR, 2015-2024",
    y = "2024 vulnerability composite percentile",
    color = NULL,
    size = NULL,
    caption = str_wrap(
      paste(
        "Vulnerability is the mean citywide percentile of renter share, renter",
        "burden, poverty, and senior share. This screens for housing pressure;",
        "it does not establish that gentrification or displacement occurred."
      ),
      width = 115
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
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
    axis.text.x = element_text(
      size = 12,
      face = "bold"
    ),
    axis.text.y = element_text(
      size = 12,
      face = "bold"
    ),
    axis.title.x = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(t = 12)
    ),
    axis.title.y = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5
    )
  )

ggsave(
  file.path("visualizations", "week04_zip_selection_matrix.png"),
  selection_matrix_plot,
  width = 10,
  height = 7,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 3 — SELECTED-ZIP VULNERABILITY PROFILE
# =============================================================================
# Purpose: Compare the specific resident characteristics underlying each ZIP's
# composite vulnerability ranking.
# Caption: Show the components behind the composite so the class can see that
# the ZIPs face different combinations of renter, poverty, age, and owner risk.

vulnerability_plot_data <- week04_two_zip_panel |>
  filter(year == 2024L) |>
  transmute(
    zip5,
    `Renter share` = renter_share,
    `Renter cost burden` = renter_cost_burden,
    `Severe renter burden` = severe_renter_cost_burden,
    `Poverty rate` = poverty_rate,
    `Senior share` = senior_share,
    `Owner cost burden` = owner_cost_burden
  ) |>
  pivot_longer(-zip5, names_to = "criterion", values_to = "share")

vulnerability_profile_plot <- ggplot(
  vulnerability_plot_data,
  aes(criterion, share, fill = zip5)
) +
  geom_col(position = position_dodge(width = 0.75), width = 0.68) +
  geom_text(
    aes(label = scales::percent(share, accuracy = 0.1)),
    position = position_dodge(width = 0.75),
    hjust = -0.08,
    size = 3.2
  ) +
  coord_flip(clip = "off") +
  scale_y_continuous(
    labels = scales::label_percent(),
    limits = c(0, 0.75),
    expand = expansion(mult = c(0, 0.06))
  ) +
  scale_fill_manual(values = c("19132" = "#D95F0E", "19143" = "#08519C")) +
  labs(
    title = "The Selected ZIPs Have Different Vulnerability Profiles",
    subtitle = "ACS 2020-2024 five-year estimates; higher values indicate greater exposure",
    x = NULL,
    y = "Share",
    fill = "ZIP/ZCTA",
    caption = paste(
      "ACS five-year estimates overlap across releases. Estimates and 90%",
      "margins of error are retained in the Week 4 analytical panel."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.major.y = element_blank(),
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
    axis.text.x = element_text(
      size = 12,
      face = "bold"
    ),
    axis.text.y = element_text(
      size = 12,
      face = "bold"
    ),
    axis.title.x = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(t = 12)
    ),
    axis.title.y = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(r = 12)
    ),
    plot.caption = element_text(
      hjust = 0.5
    )
  )

ggsave(
  file.path("visualizations", "week04_selected_zip_vulnerability_profile.png"),
  vulnerability_profile_plot,
  width = 10,
  height = 7,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 4 — FIVE-ZIP TRANSACTION ACTIVITY
# =============================================================================
# Purpose: Add transaction activity to the market-pressure story instead of
# treating price growth alone as evidence of neighborhood change.
# Caption: Use one common-scale dumbbell chart to compare three-year-average
# eligible RTT sales per 1,000 occupied housing units at the beginning and end
# of the analysis period. The fixed 2024 housing-stock denominator supports
# comparison across differently sized ZIPs.

transaction_dumbbell_data <- transaction_period_summary |>
  select(zip5, comparison_period, average_transactions_per_1000) |>
  mutate(comparison_period = as.character(comparison_period)) |>
  pivot_wider(
    names_from = comparison_period,
    values_from = average_transactions_per_1000
  ) |>
  mutate(
    zip5 = forcats::fct_reorder(zip5, `2022-2024`)
  )

transaction_activity_plot <- ggplot(
  transaction_dumbbell_data,
  aes(y = zip5)
) +
  geom_segment(
    aes(x = `2015-2017`, xend = `2022-2024`, yend = zip5),
    color = "#667788",
    linewidth = 1.4,
    lineend = "round"
  ) +
  geom_point(
    aes(x = `2015-2017`, color = "2015-2017"),
    size = 4.2
  ) +
  geom_point(
    aes(x = `2022-2024`, color = "2022-2024"),
    size = 4.2
  ) +
  geom_text(
    aes(
      x = `2015-2017`,
      label = scales::number(`2015-2017`, accuracy = 0.1)
    ),
    nudge_y = 0.18,
    color = "#202020",
    size = 3.3,
    show.legend = FALSE
  ) +
  geom_text(
    aes(
      x = `2022-2024`,
      label = scales::number(`2022-2024`, accuracy = 0.1)
    ),
    nudge_y = -0.18,
    color = "#202020",
    size = 3.3,
    show.legend = FALSE
  ) +
  scale_color_manual(values = c(
    "2015-2017" = "#08519C",
    "2022-2024" = "#D95F0E"
  )) +
  scale_x_continuous(
    limits = c(0, NA),
    breaks = scales::breaks_pretty(n = 6),
    expand = expansion(mult = c(0, 0.10))
  ) +
  labs(
    title = "Transaction Activity Changed Differently Across the Five ZIPs",
    subtitle = "Common-scale comparison of three-year-average eligible property sales",
    x = "Eligible sales per 1,000 occupied units",
    y = "ZIP/ZCTA",
    color = "Period",
    caption = str_wrap(
      paste(
        "Philadelphia RTT single-property, non-nominal, known-price, non-outlier",
        "sales. Rates use 2024 ACS occupied housing units as a fixed denominator.",
        "19132 and 19143 are the detailed case studies."
      ),
      width = 115
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(
      face = "plain",
      hjust = 0.5,
      margin = margin(b = 12)
    ),
    axis.text.x = element_text(
      size = 12,
      face = "bold"
    ),
    axis.text.y = element_text(
      size = 12,
      face = "bold"
    ),
    axis.title.x = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(t = 12)
    ),
    axis.title.y = element_text(
      size = 13.5,
      face = "bold",
      margin = margin(r = 12)
    ),
    plot.caption = element_text(hjust = 0.5)
  )

ggsave(
  file.path("visualizations", "week04_five_zip_transaction_activity.png"),
  transaction_activity_plot,
  width = 10,
  height = 7,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 5 — SALE-TO-ASSESSMENT TREND
# =============================================================================
# Purpose: Reproduce the previously presented assessment-alignment method for
# 19132 and 19143, including the annual median and interquartile range.
# Caption: Reproduce the presented median-and-middle-50% design separately for
# the two case-study ZIPs. This is an assessment-alignment indicator, not an
# affordability measure or proof of a future tax increase.

sale_to_assessment_plot <- ggplot(
  week04_sale_to_assessment,
  aes(year, median_sale_to_assessment_ratio, color = zip5, fill = zip5)
) +
  geom_hline(yintercept = 1, color = "#B22222", linetype = "dashed") +
  geom_ribbon(
    aes(ymin = sale_to_assessment_q25, ymax = sale_to_assessment_q75),
    alpha = 0.30,
    color = NA
  ) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  facet_wrap(vars(zip5), ncol = 1) +
  scale_x_continuous(breaks = seq(2014, 2025, 2)) +
  scale_color_manual(values = c("19132" = "#D95F0E", "19143" = "#08519C")) +
  scale_fill_manual(values = c("19132" = "#D95F0E", "19143" = "#08519C")) +
  labs(
    title = "Sale-to-Assessment Ratio in the Two Case-Study ZIPs",
    subtitle = "Annual median; shaded band is the middle 50% of eligible property sales",
    x = NULL,
    y = "Sale price / assessed value",
    color = NULL,
    fill = NULL,
    caption = str_wrap(
      paste(
        "Philadelphia RTT exact DEED, single-property, non-nominal, known-price,",
        "non-outlier sales. Starts in 2014 after AVI; RTT has no explicit",
        "assessment-year field, so timing cannot be independently verified."
      ),
      width = 115
    )
  ) + 
  geom_text(
  data = week04_sale_to_assessment |>
    filter(year %in% c(2014, 2016, 2018, 2020, 2022, 2024)),
  aes(label = scales::number(
    median_sale_to_assessment_ratio,
    accuracy = 0.01
  )),
  vjust = -0.8,
  size = 3,
  fontface = "bold",
  show.legend = FALSE
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

ggsave(
  file.path("visualizations", "week04_sale_to_assessment_record.png"),
  sale_to_assessment_plot,
  width = 10,
  height = 8,
  dpi = 300
)

# =============================================================================
# PRINT ALL WEEK 4 VISUALIZATIONS IN THE RSTUDIO PLOTS PANE
# =============================================================================
# Purpose: Display the five completed ggplot objects sequentially in RStudio so
# the analyst can review them with the Plots-pane back and forward controls.
# Caption: This block runs only in an interactive R session. It is skipped by
# command-line Rscript builds so automated reruns do not open graphics devices.

if (interactive() && isTRUE(getOption("bsan.show_week04_plots", TRUE))) {
  print(preliminary_plot)
  print(selection_matrix_plot)
  print(vulnerability_profile_plot)
  print(transaction_activity_plot)
  print(sale_to_assessment_plot)
}

# To build the files without previewing the plots in an interactive session:
# options(bsan.show_week04_plots = FALSE)
# source("08_select_case_study_zips.R")
# options(bsan.show_week04_plots = TRUE)

# =============================================================================
# COMPLETION MESSAGE
# =============================================================================
# Caption: Confirm the selected ZIPs and remind the analyst to review the score
# and assessment-timing caveats before using these outputs in Week 5.
message(
  "Week 4 outputs written for ", paste(selected_zips, collapse = " and "),
  ". Review the scorecard and assessment-timing caveat before Week 5."
)
