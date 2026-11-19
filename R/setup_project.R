# =============================================================================
# ONE-TIME PROJECT SETUP: REQUIRED R PACKAGES
# =============================================================================
# Run this script once in the same R installation used by the IDE:
#   source("R/setup_project.R")
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
  "jsonlite"
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
