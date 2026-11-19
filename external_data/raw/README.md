# Local external-data cache

This folder is excluded from GitHub and holds downloaded or extracted source
files used by the ETL scripts.

Expected Redfin files:

- `redfin_zip_market_tracker_philadelphia.tsv` — Philadelphia 191xx, ZIP-code,
  All Residential subset from the official Redfin ZIP Code Market Tracker;
- `redfin_zip_prices_normalized.csv` — normalized output created by
  `R/redfin_zip_etl.R`.

The economic and affordability scripts also cache FRED, Zillow, and ACS files
here. Clean compact outputs and source citations are written one level above to
`external_data/`.

Expected Week 5 caches:

- `week05_opa_selected_zips.csv` — current OPA parcel characteristics for
  19132 and 19143, queried from `opa_properties_public`;
- `week05_opa_zip_property_mix.csv` — OPA property-class aggregates for all
  Philadelphia 191xx ZIPs;
- `week05_permit_zip_year.csv` — L&I permit aggregates from 2014 forward,
  queried from `permits`;
- `week05_eviction_pa_monthly.csv` — Eviction Lab Pennsylvania ZIP-level
  monthly filing file; and
- `week05_eviction_dictionary.xlsx` — Eviction Lab source dictionary.

OPA and permit SQL, fields, and refresh behavior are implemented in
`R/week05_property_permit_validation.R`. Eviction cleaning is implemented in
`R/week05_eviction_market_signals.R`. The raw files remain excluded from Git;
the compact analytical outputs, source catalog, and calculation notes are
tracked for reproducibility.

