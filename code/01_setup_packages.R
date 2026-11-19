# =============================================================================
# 01. INSTALL REQUIRED R PACKAGES
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE
#   Checks for the packages the pipeline needs and installs only the missing
#   ones. Re-running is safe. Kept separate so the analysis scripts never
#   silently change a user's R library.
# INPUTS
#   nothing (reads the R library)
# OUTPUTS
#   nothing (installs missing packages into the R library)
# RUNS AFTER   nothing
# NOTES        Run once before the first full build.
# =============================================================================

# =============================================================================
# ONE-TIME PROJECT SETUP: REQUIRED R PACKAGES
# =============================================================================
# Run this script once in the same R installation used by the IDE:
#   source("01_setup_packages.R")
#
# It installs only packages that are missing. Re-running it is safe. The main
# analysis deliberately does not install packages itself because reproducible
# analysis scripts should not silently change a user's R environment.

required_packages <- c(
  "tidyverse",
  "lubridate",
  "tsibble",
  "feasts",
  "fabletools",
  "fable",
  "lpSolve",
  "readxl",
  "jsonlite",
  "scales",   # chart axis labels (stages 05-20)
  "ragg",     # PNG device in stages 09 and 12
  "slider",   # rolling 12-month eviction filings in stage 13
  "cluster"   # silhouette check in stage 03
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) == 0) {
  message("All required R packages are installed.")
} else {
  message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

still_missing <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(still_missing) > 0) {
  stop(
    "These packages are still unavailable: ",
    paste(still_missing, collapse = ", "),
    ". Confirm that the IDE and installer are using the same R version/library."
  )
}

message("Project package setup is complete.")
