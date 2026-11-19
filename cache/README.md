# Reproducible local cache

This folder contains large intermediate R objects and parsing diagnostics that
speed up reruns. Cache files are excluded from GitHub because they can be
rebuilt from `data/raw/rtt_summary.csv` by running `R/BSAN_Proj.R`.

Increment `clean_cache_version` in the main script whenever the cleaning schema
or rules change.

