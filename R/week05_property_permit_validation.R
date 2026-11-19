library(tidyverse)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 05: PROPERTY-TYPE SENSITIVITY AND DEVELOPMENT-PERMIT SIGNALS
# =============================================================================
# ABSTRACT
# This script tests whether the two-ZIP sale-price story changes after property
# type is introduced, and measures local development activity with official OPA
# and L&I data. OPA supplies parcel classifications, not a dependable dwelling-
# unit count for every parcel. L&I's numberofunits describes permitted project
# units, not the existing housing stock. The analysis therefore reports sale
# price by property class and permit/unit pipelines without pretending that a
# complete historic sale-price-per-unit measure exists.

# =============================================================================
# 1. SETTINGS, SOURCE QUERIES, AND CACHE RULES
# =============================================================================
# Caption: Raw public extracts are cached outside Git. Set the refresh option
# TRUE to rerun the official Carto SQL queries.

selected_zips <- c("19132", "19143")
raw_dir <- file.path("external_data", "raw")
opa_path <- file.path(raw_dir, "week05_opa_selected_zips.csv")
opa_mix_path <- file.path(raw_dir, "week05_opa_zip_property_mix.csv")
permit_path <- file.path(raw_dir, "week05_permit_zip_year.csv")
sales_path <- file.path("team_data", "data_clean.csv.gz")
refresh_external <- isTRUE(getOption("bsan.refresh_week05_external", FALSE))

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create("tableau_data", recursive = TRUE, showWarnings = FALSE)
dir.create("visualizations", recursive = TRUE, showWarnings = FALSE)

carto_download <- function(sql, destination) {
  query <- paste0(
    "https://phl.carto.com/api/v2/sql?format=csv&q=",
    URLencode(sql, reserved = TRUE)
  )
  download.file(query, destination, mode = "wb", quiet = TRUE)
}

# Caption: Retrieve only fields required for property classification and a
# compact citywide property-mix benchmark.
if (!file.exists(opa_path) || refresh_external) {
  carto_download(
    paste(
      "SELECT parcel_number, zip_code, building_code_new,",
      "building_code_description_new, category_code,",
      "category_code_description, total_livable_area, unit, year_built",
      "FROM opa_properties_public",
      "WHERE left(zip_code,5) IN ('19132','19143')"
    ),
    opa_path
  )
}

if (!file.exists(opa_mix_path) || refresh_external) {
  carto_download(
    paste(
      "SELECT left(zip_code,5) AS zip5, category_code_description,",
      "building_code_description_new, count(*) AS n_properties,",
      "sum(total_livable_area) AS total_livable_area",
      "FROM opa_properties_public WHERE left(zip_code,3)='191'",
      "GROUP BY 1,2,3"
    ),
    opa_mix_path
  )
}

# Caption: Aggregate permit records at source to keep the reproducible cache
# compact while retaining permit type, residential status, and permitted units.
if (!file.exists(permit_path) || refresh_external) {
  carto_download(
    paste(
      "SELECT left(zip,5) AS zip5, extract(year from permitissuedate)::int AS year,",
      "coalesce(typeofwork,'Unknown') AS typeofwork,",
      "coalesce(permitdescription,'Unknown') AS permitdescription,",
      "coalesce(commercialorresidential,'Unknown') AS commercialorresidential,",
      "count(DISTINCT permitnumber) AS n_permits,",
      "sum(CASE WHEN numberofunits > 0 THEN numberofunits ELSE 0 END) AS permitted_units",
      "FROM permits WHERE permitissuedate >= '2014-01-01'",
      "AND left(zip,3)='191' GROUP BY 1,2,3,4,5"
    ),
    permit_path
  )
}

required_paths <- c(opa_path, opa_mix_path, permit_path, sales_path)
if (any(!file.exists(required_paths))) {
  stop("Missing Week 5 OPA, permit, or RTT input. See paths at top of script.")
}

# =============================================================================
# 2. CLASSIFY OPA PARCELS AND AUDIT UNIT COVERAGE
# =============================================================================
# Caption: Consolidate OPA categories into interpretable housing groups. The
# `unit` field is an address/unit designator and is not used as a unit count.

opa <- read_csv(
  opa_path,
  col_types = cols(parcel_number = col_character(), zip_code = col_character()),
  show_col_types = FALSE
) |>
  transmute(
    opa_account_num = parcel_number,
    zip5 = str_sub(zip_code, 1, 5),
    category = str_to_upper(coalesce(category_code_description, "UNKNOWN")),
    building_description = str_to_upper(
      coalesce(building_code_description_new, "UNKNOWN")
    ),
    total_livable_area,
    opa_unit_designator = unit,
    year_built,
    property_group = case_when(
      str_detect(category, "SINGLE FAMILY") ~ "Single family",
      str_detect(category, "MULTI FAMILY|APARTMENT") ~ "Multifamily/apartment",
      str_detect(category, "MIXED USE") ~ "Mixed use",
      str_detect(category, "VACANT") ~ "Vacant land",
      TRUE ~ "Other/nonresidential"
    )
  )

unit_coverage_audit <- opa |>
  summarise(
    opa_parcels = n(),
    parcels_with_address_unit_designator = sum(!is.na(opa_unit_designator)),
    address_unit_designator_coverage = mean(!is.na(opa_unit_designator)),
    parcels_with_livable_area = sum(total_livable_area > 0, na.rm = TRUE),
    explicit_dwelling_unit_count_available = FALSE,
    valid_price_per_dwelling_unit_possible = FALSE,
    limitation = paste(
      "OPA's unit field identifies an address/unit and is not a dwelling-unit count;",
      "L&I permitted_units describes projects, not all existing parcels."
    ),
    .by = zip5
  )

# =============================================================================
# 3. JOIN ELIGIBLE SALES TO OPA PROPERTY CLASSES
# =============================================================================
# Caption: Reapply the Week 4 eligible-sale definition at parcel level, then
# join to the current OPA classification by account number.

eligible_sales <- read_csv(
  sales_path,
  col_select = c(
    document_id, document_type, activity_type, record_date, year, zip5,
    opa_account_num, property_count, total_consideration, nominal_transfer,
    unknown_consideration, high_value_sale_outlier
  ),
  col_types = cols(
    document_id = col_character(),
    record_date = col_date(),
    zip5 = col_character(),
    opa_account_num = col_character()
  ),
  show_col_types = FALSE
) |>
  filter(
    zip5 %in% selected_zips,
    year %in% 2015:2024,
    document_type == "DEED",
    activity_type == "sale_deed",
    property_count == 1L,
    !nominal_transfer,
    !unknown_consideration,
    !high_value_sale_outlier,
    total_consideration > 100
  ) |>
  distinct(document_id, .keep_all = TRUE) |>
  left_join(
    select(opa, opa_account_num, opa_zip5 = zip5, property_group),
    by = "opa_account_num"
  ) |>
  mutate(
    property_group = coalesce(property_group, "Unmatched OPA parcel"),
    period = if_else(year <= 2019L, "2015-2019", "2020-2024")
  )

# Caption: Export match coverage so audiences can judge how representative the
# property-type comparison is.
property_join_coverage <- eligible_sales |>
  summarise(
    eligible_sales = n(),
    opa_matched_sales = sum(property_group != "Unmatched OPA parcel"),
    opa_match_rate = mean(property_group != "Unmatched OPA parcel"),
    .by = zip5
  )

sale_property_sensitivity <- eligible_sales |>
  filter(property_group != "Unmatched OPA parcel") |>
  summarise(
    eligible_sales = n(),
    median_sale_price = median(total_consideration, na.rm = TRUE),
    price_q25 = quantile(total_consideration, 0.25, na.rm = TRUE),
    price_q75 = quantile(total_consideration, 0.75, na.rm = TRUE),
    .by = c(zip5, period, property_group)
  ) |>
  filter(eligible_sales >= 10L)

# =============================================================================
# 4. BUILD CITYWIDE PROPERTY-MIX AND PERMIT SIGNALS
# =============================================================================
# Caption: Benchmark the selected ZIPs' parcel composition against all valid
# Philadelphia 191xx ZIP rows in the compact OPA aggregate.

property_mix <- read_csv(
  opa_mix_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(str_detect(zip5, "^191[0-9]{2}$")) |>
  mutate(
    category = str_to_upper(coalesce(category_code_description, "UNKNOWN")),
    property_group = case_when(
      str_detect(category, "SINGLE FAMILY") ~ "Single family",
      str_detect(category, "MULTI FAMILY|APARTMENT") ~ "Multifamily/apartment",
      str_detect(category, "MIXED USE") ~ "Mixed use",
      str_detect(category, "VACANT") ~ "Vacant land",
      TRUE ~ "Other/nonresidential"
    )
  ) |>
  summarise(n_properties = sum(n_properties), .by = c(zip5, property_group)) |>
  mutate(property_share = n_properties / sum(n_properties), .by = zip5)

# Caption: Separate all permits from new-construction permits and sum project
# units only where L&I supplies them. Permit counts are regulatory activity,
# not completed homes; permitted units are a development pipeline indicator.

permit_signals <- read_csv(
  permit_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(str_detect(zip5, "^191[0-9]{2}$"), year %in% 2014:2025) |>
  mutate(
    is_new_construction = str_detect(
      str_to_upper(typeofwork),
      "NEW CONSTRUCTION"
    ),
    geography = if_else(zip5 %in% selected_zips, zip5, "Other Philadelphia ZIPs")
  ) |>
  summarise(
    all_permits = sum(n_permits, na.rm = TRUE),
    new_construction_permits = sum(n_permits[is_new_construction], na.rm = TRUE),
    permitted_units = sum(permitted_units[is_new_construction], na.rm = TRUE),
    .by = c(zip5, year)
  )

write_csv(unit_coverage_audit, "tableau_data/week05_unit_coverage_audit.csv")
write_csv(property_join_coverage, "tableau_data/week05_property_join_coverage.csv")
write_csv(
  sale_property_sensitivity,
  "tableau_data/week05_sale_price_by_property_type.csv"
)
write_csv(property_mix, "tableau_data/week05_opa_property_mix.csv")
write_csv(permit_signals, "tableau_data/week05_permit_signals.csv")

# =============================================================================
# VISUALIZATION 3 — PROPERTY-TYPE SALE-PRICE SENSITIVITY
# =============================================================================
# Caption: Compare periods within like property groups so a changing mix of
# single-family and multifamily parcels cannot silently drive the ZIP median.

property_sensitivity_plot <- ggplot(
  sale_property_sensitivity |>
    filter(property_group %in% c("Single family", "Multifamily/apartment", "Mixed use")),
  aes(period, median_sale_price, fill = period)
) +
  geom_col(width = 0.68) +
  geom_text(
    aes(label = scales::dollar(median_sale_price, accuracy = 1000)),
    vjust = -0.35,
    fontface = "bold",
    size = 3.7
  ) +
  facet_grid(property_group ~ zip5, scales = "free_y") +
  scale_fill_manual(values = c("2015-2019" = "#08519C", "2020-2024" = "#D95F0E")) +
  scale_y_continuous(
    labels = scales::label_dollar(scale_cut = scales::cut_short_scale()),
    expand = expansion(mult = c(0, 0.18))
  ) +
  labs(
    title = "Sale-Price Change Persists After Separating Property Classes",
    subtitle = "Median eligible RTT consideration; groups with at least 10 sales per period",
    x = NULL,
    y = "Median sale price",
    fill = NULL,
    caption = paste(
      "OPA classifications describe parcels, not dwelling-unit counts.",
      "This is a property-type sensitivity test, not price per housing unit."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_property_type_price_sensitivity.png",
  property_sensitivity_plot,
  width = 11,
  height = 8,
  dpi = 300
)

# =============================================================================
# VISUALIZATION 4 — NEW-CONSTRUCTION PERMIT AND UNIT PIPELINE
# =============================================================================
# Caption: Show both project count and units reported on permits, because one
# large multifamily project and many single-unit projects imply different scale.

permit_plot_data <- permit_signals |>
  filter(zip5 %in% selected_zips) |>
  select(zip5, year, new_construction_permits, permitted_units) |>
  pivot_longer(
    c(new_construction_permits, permitted_units),
    names_to = "measure",
    values_to = "value"
  ) |>
  mutate(measure = recode(
    measure,
    new_construction_permits = "New-construction permits",
    permitted_units = "Units reported on new-construction permits"
  ))

permit_pipeline_plot <- ggplot(
  permit_plot_data,
  aes(year, value, color = zip5)
) +
  geom_line(linewidth = 1.25) +
  geom_point(size = 2.5) +
  facet_wrap(vars(measure), ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("19132" = "#D95F0E", "19143" = "#08519C")) +
  scale_x_continuous(breaks = seq(2014, 2025, 2)) +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(
    title = "Development Pipeline in the Two Case-Study ZIPs",
    subtitle = "L&I permits issued, 2014-2025",
    x = NULL,
    y = "Count",
    color = "ZIP code",
    caption = paste(
      "Permits indicate authorized activity, not completed or occupied housing.",
      "Units are summed only for new-construction records reporting numberofunits."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week05_permit_unit_pipeline.png",
  permit_pipeline_plot,
  width = 11,
  height = 8,
  dpi = 300
)

# =============================================================================
# 7. PRINT WEEK 5 PROPERTY/PERMIT OUTPUTS TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(property_sensitivity_plot)
  print(permit_pipeline_plot)
}
property_join_coverage
unit_coverage_audit
