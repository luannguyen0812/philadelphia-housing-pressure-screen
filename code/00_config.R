# =============================================================================
# 00. RUN CONFIGURATION
# =============================================================================
# IDENTIFIERS  BSAN 710 Group 4 - Philadelphia housing pressure - November 2026
# PURPOSE      Tells every other stage two things: where the project folder is
#              and where this code folder is. No other file in the package
#              hard-codes an absolute path, so a new user edits nothing but
#              this file (or sets one environment variable).
# INPUTS       the folder structure described below; no data is read here
# OUTPUTS      none; sets `code_dir`, `project_root`, and run options
# RUNS AFTER   nothing - it is always the first file loaded
#
# HOW TO POINT THE CODE AT YOUR COPY OF THE PROJECT
#   The pipeline reads and writes folders that sit at the project root:
#       data/raw/            raw Real Estate Transfers extract
#       external_data/       cached external downloads and clean external tables
#       team_data/           the two cleaned tables, dictionaries and metadata
#       tableau_data/        dashboard facts and analysis-ready CSVs
#       visualizations/      presentation PNGs
#   Resolution order, first match wins:
#     1. environment variable BSAN710_PROJECT_ROOT
#     2. the folder that contains this code folder (submission layout)
#     3. this code folder itself
#     4. the current working directory, then its parent
#   If none of them contains the folders above, the script stops and says so.
# =============================================================================

# ---- 1. Where is this file? -------------------------------------------------
# `ofile` is set on the frame of every source() call. Walking the frames and
# taking the innermost one whose filename is this file keeps the path correct
# whether this file is sourced directly, sourced by run_all.R, or reached from
# a stage script that was itself sourced.
find_own_path <- function() {
  ofiles <- vapply(
    sys.frames(),
    function(frame) {
      path <- frame$ofile
      if (is.null(path)) NA_character_ else as.character(path)[1]
    },
    character(1)
  )
  ofiles <- ofiles[!is.na(ofiles)]
  if (!length(ofiles)) return(NA_character_)
  own <- ofiles[basename(ofiles) == "00_config.R"]
  chosen <- if (length(own)) own[[length(own)]] else ofiles[[length(ofiles)]]
  normalizePath(chosen, winslash = "/", mustWork = FALSE)
}

config_path <- tryCatch(find_own_path(), error = function(e) NA_character_)

code_dir <- if (is.na(config_path)) {
  normalizePath(getwd(), winslash = "/")
} else {
  dirname(config_path)
}

# ---- 2. Where is the project? ----------------------------------------------
looks_like_project <- function(path) {
  markers <- c("data", "external_data", "team_data", "tableau_data")
  dir.exists(file.path(path, markers)) |> sum() >= 2
}

from_env <- Sys.getenv("BSAN710_PROJECT_ROOT", unset = NA_character_)

candidates <- c(
  from_env,
  dirname(code_dir),
  code_dir,
  getwd(),
  dirname(getwd())
)
candidates <- unique(candidates[!is.na(candidates)])
candidates <- unique(normalizePath(candidates, winslash = "/", mustWork = FALSE))

project_root <- candidates[vapply(candidates, looks_like_project, logical(1))][1]

if (is.na(project_root)) {
  stop(
    "Could not find the project folders (data/, external_data/, team_data/,\n",
    "tableau_data/). The code looked in:\n  ",
    paste(candidates, collapse = "\n  "),
    "\n\nFix it one of two ways:\n",
    "  1. Set the environment variable BSAN710_PROJECT_ROOT to the project\n",
    "     folder, for example in .Renviron:\n",
    "         BSAN710_PROJECT_ROOT=/Users/you/BSAN_Proj\n",
    "  2. Open BSAN_Proj.Rproj so the working directory is already the project\n",
    "     root, then run this code from there.\n",
    call. = FALSE
  )
}

setwd(project_root)

# Safety net: if the path above did not land on the shared code folder, use the
# conventional <project>/code location when it exists.
if (!file.exists(file.path(code_dir, "00_config.R"))) {
  alt <- file.path(project_root, "code")
  if (file.exists(file.path(alt, "00_config.R"))) code_dir <- alt
}

# ---- 3. Run options ---------------------------------------------------------
# Everything that costs a download or a long rebuild is off by default, so an
# ordinary run reproduces the submitted numbers from the cached inputs. Turn a
# flag on only when the upstream source has actually changed.
options(
  # re-download the OPA, L&I and Eviction Lab extracts
  bsan.refresh_week05_external = FALSE,
  bsan.refresh_week05_eviction = FALSE,
  # re-download FRED / FHFA / Zillow series
  bsan.refresh_external = FALSE,
  # re-query the Census API instead of reusing cached ACS files
  bsan.refresh_acs = FALSE,
  bsan.refresh_week04_acs = FALSE,
  # five-ZIP scenario length, 10 to 15 years
  bsan.zip_projection_years = 10L,
  # "similar_to_citywide" is the documented rule; "highest_growth" is the
  # alternative that was considered and not adopted
  bsan.zip_selection_rule = "similar_to_citywide",
  # do not pop plot windows during a scripted run
  bsan.show_core_plots = FALSE
)

message(
  "Project root : ", project_root, "\n",
  "Code folder  : ", code_dir
)
