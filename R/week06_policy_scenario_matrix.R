library(tidyverse)
source("R/week05_plot_theme.R")

# =============================================================================
# WEEK 06: EVIDENCE-TO-RESPONSE POLICY MATRIX
# =============================================================================
# ABSTRACT
# Translate the validated Week 4-5 signals into differentiated, conditional
# City responses for 19132 and 19143. The matrix identifies the evidence
# trigger, proposed operational response, lead time, and monitoring metric for
# each action. It does not claim that the proposed policy caused—or will
# prevent—displacement. Every other qualifying ZIP receives an explicit
# monitoring-only record so a Tableau selection never produces a misleading
# blank recommendation panel.

# =============================================================================
# 1. LOAD THE FINAL ZIP EVIDENCE PROFILE
# =============================================================================
# Caption: Use only the relationship-safe Week 6 profile so recommendations
# and dashboard figures cannot drift to different versions of the evidence.

profile_path <- file.path("tableau_data", "week06_zip_evidence_profile.csv")
ingestion_dir <- file.path("tableau_data", "tableau_ingestion")

if (!file.exists(profile_path)) {
  stop("Missing ", profile_path, ". Run R/week06_dashboard_exports.R first.")
}

profile <- read_csv(
  profile_path,
  col_types = cols(zip5 = col_character()),
  show_col_types = FALSE
) |>
  filter(!is.na(zip5))

case_profile <- profile |>
  filter(zip5 %in% c("19132", "19143"))

if (nrow(case_profile) != 2L) {
  stop("Expected one evidence-profile row for each case-study ZIP.")
}

value_for <- function(zip, field) {
  case_profile |>
    filter(zip5 == zip) |>
    pull(all_of(field)) |>
    first()
}

# =============================================================================
# 2. CONSTRUCT DIFFERENTIATED CASE-STUDY RESPONSES
# =============================================================================
# Caption: Link every response to a reported condition and a measurable
# follow-up indicator. Priority describes the current evidence-alignment, not
# a funding allocation or a causal impact estimate.

policy_case_studies <- tribble(
  ~zip5, ~action_category, ~priority, ~priority_score,
  ~evidence_trigger, ~proposed_city_response, ~delivery_lead_time,
  ~monitoring_metric, ~claim_boundary, ~dashboard_order,

  "19132", "Renter stabilization", "High", 3,
  paste0(
    "2025 eviction filings were ",
    round(value_for("19132", "eviction_filings_per_1000_renters_2025"), 1),
    " per 1,000 estimated renter households, above the City benchmark of 40.2; ",
    "vulnerability was at the ",
    scales::percent(value_for("19132", "vulnerability_percentile"), accuracy = 0.1),
    " percentile and transaction activity fell ",
    scales::percent(abs(value_for("19132", "transaction_change_pct")), accuracy = 0.1),
    " between 2015-17 and 2022-24."
  ),
  paste(
    "Prioritize eviction-prevention outreach, legal representation referral,",
    "and emergency rental-assistance navigation before a filing becomes a",
    "completed displacement."
  ),
  "Immediate to 12 months",
  "Filings per 1,000 renter households; cases receiving legal or rental-assistance referral",
  "Filings are court cases, not unique households or completed evictions.",
  1,

  "19132", "Affordable-housing preservation", "High", 3,
  paste0(
    "Median sale-price CAGR was ",
    scales::percent(value_for("19132", "redfin_2015_2024_cagr"), 0.1),
    ", the fastest in the qualifying set. Prices rose ",
    scales::percent(value_for("19132", "price_change_pct"), accuracy = 0.1),
    " from 2014 to 2024 versus income growth of ",
    scales::percent(value_for("19132", "income_change_pct"), accuracy = 0.1),
    ", a gap of ",
    round(value_for("19132", "affordability_growth_gap") * 100, 1),
    " percentage points. Vulnerability was ",
    scales::percent(value_for("19132", "vulnerability_percentile"), accuracy = 0.1), "."
  ),
  paste(
    "Begin targeted preservation and acquisition screening for naturally",
    "occurring affordable rental properties; evaluate land-bank or community",
    "land-trust pathways where parcel-level due diligence supports action."
  ),
  "12 to 36 months",
  "At-risk affordable units screened, preserved, or acquired; price and rent trajectory",
  "ZIP-level price growth does not identify a specific property at risk.",
  2,

  "19132", "Homeowner stabilization", "Medium", 2,
  paste0(
    "The ZIP has rapid price growth (",
    scales::percent(value_for("19132", "redfin_2015_2024_cagr"), accuracy = 0.1),
    ") and an estimated homeowner share of ",
    scales::percent(1 - value_for("19132", "renter_share"), accuracy = 0.1),
    "; the analysis does not yet contain parcel-level tax delinquency or ",
    "assessment-growth data."
  ),
  paste(
    "Pair outreach for LOOP, installment agreements, tangled-title support,",
    "and housing counseling with a future delinquency/assessment eligibility",
    "screen before targeting individual owners."
  ),
  "6 to 24 months",
  "Eligible owners contacted and enrolled; delinquency and assessment-growth indicators",
  "This is a prevention pathway, not evidence that tax pressure caused current sales patterns.",
  3,

  "19132", "Development and market monitoring", "Medium", 2,
  paste0(
    round(value_for("19132", "permitted_units_2023_2025")),
    " dwelling units were reported on 2023-2025 new-construction permits (",
    scales::percent(value_for("19132", "permit_pipeline_percentile"), accuracy = 0.1),
    " percentile; ",
    round(value_for("19132", "permitted_units_per_1000_occupied_2023_2025"), 1),
    " per 1,000 occupied units); reported units are a pipeline measure, ",
    "not completed supply."
  ),
  paste(
    "Track permit issuance, completion, affordability commitments, investor",
    "ownership, inventory, and days on market together before interpreting",
    "development as either relief or added displacement pressure."
  ),
  "Quarterly monitoring",
  "Permitted versus completed units; affordable-unit commitments; inventory and days on market",
  "Permit records do not prove construction, completion, net supply, or affordability.",
  4,

  "19143", "Affordable-rental preservation", "High", 3,
  paste0(
    "The 2024 price-to-income ratio was ",
    round(value_for("19143", "price_to_income_2024"), 2),
    "x and prices rose ",
    scales::percent(value_for("19143", "price_change_pct"), accuracy = 0.1),
    " from 2014 to 2024 versus income growth of ",
    scales::percent(value_for("19143", "income_change_pct"), accuracy = 0.1),
    ", a gap of ",
    round(value_for("19143", "affordability_growth_gap") * 100, 1),
    " percentage points. Renter share was ",
    scales::percent(value_for("19143", "renter_share"), accuracy = 0.1),
    " and renter cost burden ",
    scales::percent(value_for("19143", "renter_cost_burden"), accuracy = 0.1), "."
  ),
  paste(
    "Prioritize preservation screening for renter-occupied properties and",
    "connect expiring or unsubsidized affordable stock to acquisition, repair,",
    "or affordability-preservation resources."
  ),
  "12 to 36 months",
  "Renter-occupied units screened and preserved; price-to-income and rent-burden trajectory",
  "Median changes can reflect household composition as well as within-household change.",
  1,

  "19143", "Permit-pipeline accountability", "High", 3,
  paste0(
    round(value_for("19143", "permitted_units_2023_2025")),
    " dwelling units were reported on 2023-2025 new-construction permits, ",
    "slightly above 19132's 191. 19132 has the higher pipeline percentile (",
    scales::percent(value_for("19132", "permit_pipeline_percentile"), accuracy = 0.1),
    " vs ",
    scales::percent(value_for("19143", "permit_pipeline_percentile"), accuracy = 0.1),
    ") and rate per 1,000 occupied units (",
    round(value_for("19132", "permitted_units_per_1000_occupied_2023_2025"), 1),
    " vs ",
    round(value_for("19143", "permitted_units_per_1000_occupied_2023_2025"), 1),
    "); 19143's High priority reflects its ",
    round(value_for("19143", "price_to_income_2024"), 2),
    "x price-to-income ratio and ",
    scales::percent(value_for("19143", "renter_share"), accuracy = 0.1),
    " renter share."
  ),
  paste(
    "Track whether permitted projects start, complete, and include affordable",
    "units; connect high-impact projects to preservation and community-benefit",
    "review where existing City authority applies."
  ),
  "Quarterly through project completion",
  "Units permitted, started, completed, and affordability-restricted",
  "Reported permit units are proposed pipeline, not delivered or affordable units.",
  2,

  "19143", "Targeted renter support", "Medium", 2,
  paste0(
    "The 2025 filing rate was ",
    round(value_for("19143", "eviction_filings_per_1000_renters_2025"), 1),
    " per 1,000 estimated renter households, below the City benchmark of 40.2 ",
    "and the ",
    scales::percent(value_for("19143", "eviction_rate_percentile"), accuracy = 0.1),
    " percentile. Renter share was ",
    scales::percent(value_for("19143", "renter_share"), accuracy = 0.1),
    " and renter cost burden ",
    scales::percent(value_for("19143", "renter_cost_burden"), accuracy = 0.1), "."
  ),
  paste(
    "Maintain targeted legal-aid and rental-assistance outreach, but do not",
    "describe 19143 as the higher filing-rate case; use building- or tract-level",
    "hotspots if operational targeting is required."
  ),
  "Immediate monitoring; targeted outreach as triggered",
  "Filing rate, renter burden, and service uptake",
  "A below-city filing rate does not mean that no renter households are at risk.",
  3,

  "19143", "Market-access monitoring", "Medium", 2,
  paste0(
    "The 2024 price-to-income ratio was ",
    round(value_for("19143", "price_to_income_2024"), 2),
    "x and transaction activity fell ",
    scales::percent(abs(value_for("19143", "transaction_change_pct")), accuracy = 0.1),
    " between 2015-17 and 2022-24, a milder contraction than 19132. ",
    "The dashboard lacks mortgage origination and denial data, so buyer-side ",
    "barriers cannot be assigned yet."
  ),
  paste(
    "Monitor mortgage access, first-time-buyer participation, inventory, and",
    "days on market before proposing buyer-side assistance; test whether the",
    "barrier is price, credit, supply, or another mechanism."
  ),
  "6 to 18 months",
  "Originations by borrower and property type; inventory; days on market; denial reasons",
  "Current RTT and Redfin data do not identify mortgage applicants or denial causes.",
  4
) |>
  mutate(
    geography_key = paste0("ZIP_", zip5),
    recommendation_key = paste0(
      geography_key, "_", str_to_upper(str_replace_all(action_category, "[^A-Za-z0-9]+", "_"))
    ),
    recommendation_status = "Case-study recommendation",
    evidence_standard = "Conditionally supported by current descriptive evidence"
  ) |>
  select(
    recommendation_key, geography_key, zip5, action_category, priority,
    priority_score, evidence_trigger, proposed_city_response,
    delivery_lead_time, monitoring_metric, claim_boundary,
    recommendation_status, evidence_standard, dashboard_order
  )

# =============================================================================
# 3. ADD A NON-CASE AVAILABILITY RECORD FOR EVERY OTHER ZIP
# =============================================================================
# Caption: Keep the shared ZIP filter functional while clearly distinguishing
# dashboard-wide evidence from recommendations validated only for the cases.

policy_other_zips <- profile |>
  filter(!zip5 %in% c("19132", "19143")) |>
  transmute(
    recommendation_key = paste0("ZIP_", zip5, "_MONITORING_ONLY"),
    geography_key = paste0("ZIP_", zip5),
    zip5,
    action_category = "Monitoring and deeper review",
    priority = "Not assessed",
    priority_score = 0,
    evidence_trigger = paste(
      "This ZIP passed the dashboard coverage gate but was not selected for",
      "the two detailed policy case studies."
    ),
    proposed_city_response = paste(
      "Use the citywide profile and annual signals to determine whether a",
      "property-, tract-, or household-level review is warranted before",
      "assigning a case-specific intervention."
    ),
    delivery_lead_time = "Monitoring",
    monitoring_metric = paste(
      "Price growth, vulnerability, transactions, price-to-income, eviction",
      "filings, permits, inventory, and days on market"
    ),
    claim_boundary = paste(
      "Comparable dashboard evidence is available; a ZIP-specific policy",
      "recommendation has not been validated."
    ),
    recommendation_status = "Dashboard monitoring only",
    evidence_standard = "Requires case-specific validation",
    dashboard_order = 99L
  )

fact_policy_response <- bind_rows(policy_case_studies, policy_other_zips) |>
  arrange(geography_key, dashboard_order)

if (anyDuplicated(fact_policy_response$recommendation_key)) {
  stop("recommendation_key must be unique.")
}

write_csv(
  fact_policy_response,
  file.path(ingestion_dir, "fact_policy_response.csv")
)
write_csv(
  policy_case_studies,
  "tableau_data/week06_case_study_policy_matrix.csv"
)

# =============================================================================
# VISUALIZATION 2 — EVIDENCE-TO-RESPONSE PRIORITY MATRIX
# =============================================================================
# Caption: Show which response families are currently high or medium priority
# for each case. The chart is a decision aid; it is not an impact evaluation or
# a claim that one intervention will prevent displacement.

policy_plot_data <- policy_case_studies |>
  mutate(
    action_label = str_wrap(action_category, width = 27),
    action_label = factor(
      action_label,
      levels = rev(unique(action_label[order(dashboard_order)]))
    ),
    priority = factor(priority, levels = c("Medium", "High"))
  )

policy_priority_plot <- ggplot(
  policy_plot_data,
  aes(zip5, action_label, fill = priority)
) +
  geom_tile(color = "white", linewidth = 1.3) +
  geom_text(
    aes(label = priority),
    fontface = "bold",
    size = 4.2,
    color = "white"
  ) +
  scale_fill_manual(values = c("Medium" = "#3182BD", "High" = "#D95F0E")) +
  labs(
    title = "Validated Signals Lead to Different City Responses",
    subtitle = "Priority reflects evidence alignment and operational urgency—not causal impact",
    x = "Case-study ZIP/ZCTA",
    y = NULL,
    fill = "Current priority",
    caption = paste(
      "Each recommendation retains an evidence trigger, lead time, monitoring",
      "metric, and claim boundary in the Tableau policy table."
    )
  ) +
  week05_presentation_theme()

ggsave(
  "visualizations/week06_evidence_to_response_matrix.png",
  policy_priority_plot,
  width = 10.5,
  height = 7.5,
  dpi = 300
)

# =============================================================================
# 4. PRINT THE WEEK 6 POLICY OUTPUT TO THE R PLOT CANVAS
# =============================================================================

if (interactive()) {
  print(policy_priority_plot)
}

policy_case_studies
