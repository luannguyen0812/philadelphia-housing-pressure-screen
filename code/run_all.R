# =============================================================================
# RUN ALL: RAW EXTRACT -> TABLES -> CHARTS -> MODELS -> DASHBOARD PACKAGE
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE      Runs every stage in dependency order so the submitted tables,
#              charts, models and Tableau package can be rebuilt from scratch.
# INPUTS       see README.md "Inputs"; the raw sources are not redistributed
# OUTPUTS      team_data/, tableau_data/, visualizations/ (see README.md)
# RUNS AFTER   nothing
#
# HOW TO RUN
#   Open BSAN_Proj.Rproj (or set BSAN710_PROJECT_ROOT - see 00_config.R), then
#       source("code/run_all.R")
#   Single stages can be re-run on their own once their inputs exist, for
#   example source("code/14_forecast_validation.R").
#
# RUNTIME
#   First full run: about 25-40 minutes, most of it in stage 03 reading the
#   1.9 GB transfer extract. Later runs reuse cache/philly_rtt_clean_v6.rds and
#   finish in a few minutes.
# =============================================================================

# Work out where this file lives so the script can be sourced from either the
# project root or the code folder.
run_from <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
  error = function(e) getwd()
)

source(file.path(run_from, "00_config.R"))

stages <- c(
  "01_setup_packages.R",                 # packages
  "02_build_economic_context.R",         # FRED, FHFA, optional Zillow
  "03_clean_philadelphia_transfers.R",   # main clean + both grains + citywide model
  "04_normalize_redfin_zip_data.R",      # Redfin ZIP tracker -> tidy panel
  "05_build_zip_affordability.R",        # price x income, price-to-income
  "06_build_core_visualizations.R",      # five core charts
  "07_build_acs_vulnerability.R",        # ACS vulnerability measures
  "08_select_case_study_zips.R",         # coverage gate + 19132 / 19143
  "09_build_citywide_benchmark.R",       # 37-ZIP benchmark
  "10_property_and_permit_checks.R",     # OPA class + L&I pipeline
  "11_redfin_rtt_reconciliation.R",      # two price sources cross-checked
  "12_neighborhood_change_endpoints.R",  # price vs income growth
  "13_eviction_and_market_signals.R",    # eviction + inventory / days on market
  "14_forecast_validation.R",            # holdouts + production forecast
  "15_build_dashboard_facts.R",          # dimension + four facts
  "16_forecast_technical_appendix.R",    # methods appendix
  "17_exogenous_forecast_challenger.R",  # external-driver test
  "18_build_response_matrix.R",          # evidence-to-response table
  "19_validate_dashboard_package.R"      # final gate
)

# Optional: skip a stage you have already run, e.g.
#   options(bsan.skip_stages = c("01_setup_packages.R"))
skip <- getOption("bsan.skip_stages", character())
stages <- setdiff(stages, skip)

started <- Sys.time()

for (stage in stages) {
  message("\n", strrep("=", 70), "\n", stage, "\n", strrep("=", 70))
  stage_started <- Sys.time()
  source(file.path(code_dir, stage), echo = FALSE)
  elapsed <- as.numeric(difftime(Sys.time(), stage_started, units = "secs"))
  message(sprintf("--- %s finished in %.1f s", stage, elapsed))
}

total <- as.numeric(difftime(Sys.time(), started, units = "mins"))

message(
  "\nPipeline finished in ", sprintf("%.1f", total), " minutes.\n",
  "Dashboard inputs : ", file.path(project_root, "tableau_data", "tableau_ingestion"),
  "\n",
  "Charts           : ", file.path(project_root, "visualizations"), "\n",
  "Package audit    : ",
  file.path(project_root, "tableau_data", "week06_final_package_audit.csv")
)
