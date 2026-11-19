# Redfin ZIP Price Handoff

## Purpose

The affordability pipeline can use Redfin as a residential-price benchmark
alongside the Philadelphia transfer-record series. Redfin does not supply the
income denominator; `R/zip_affordability_etl.R` obtains that separately from the
U.S. Census ACS.

## Required file

Save the normalized teammate handoff as:

`external_data/raw/redfin_zip_prices_normalized.csv`

Use `external_data/redfin_zip_input_template.csv` as the header template.

The file must contain one row per ZIP and month with these columns:

| Column | Type | Required meaning |
|---|---|---|
| `zip5` | Text | Five-character ZIP code, including any leading zero |
| `period` | Date | First day of the observation month in `YYYY-MM-DD` format |
| `median_sale_price` | Number | Redfin median sale price for that ZIP-month |
| `homes_sold` | Number | Homes sold for that ZIP-month; may be missing if unavailable |
| `property_type` | Text | Use one consistent residential category across every row |
| `source_url` | Text | Redfin source or download URL |

## Required checks before handoff

1. Select one consistent residential property category. Do not stack several
   property types for the same ZIP-month.
2. Confirm that `zip5 + period` is unique.
3. Preserve missing values as missing rather than replacing them with zero.
4. Keep monetary values numeric and unformatted.
5. Record the download date and Redfin metric definition in the team notes.

## Integration

After the file is added, run:

```r
source("R/zip_affordability_etl.R")
```

The script will add Redfin as a second `price_source` in:

- `tableau_data/fact_zip_price_income.csv`
- `tableau_data/model_zip_price_income_correlations.csv`

The annual Redfin value is currently defined as the median of the available
monthly median sale prices. It is not mathematically identical to a median
calculated from every individual sale during the year, so the dashboard must
retain the `price_measure` label.

## Interpretation boundary

The RTT benchmark includes eligible property deeds and is not restricted to
residential property use. Redfin should be the preferred numerator when the
team makes a housing-affordability claim. Use the RTT series to describe the
recorded property market or to test whether conclusions depend on the price
source.

