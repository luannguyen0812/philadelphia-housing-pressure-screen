# Philadelphia Real Estate Transfers

## Data cleaning decisions, justification, and cross-check procedure

**Project:** BSAN 710 group project  
**Source:** OpenDataPhilly Real Estate Transfers  
**Raw file:** `data/raw/rtt_summary.csv`  
**Analysis period:** January 1, 2000 through July 31, 2026  
**Main script:** `R/BSAN_Proj.R`  
**Cleaning version:** 6

**Validated build:** October 9, 2026; 5,067,868 parcel rows, 4,401,686
document rows, zero readr parsing problems, and an $11,152,916.98 high-value
sale cutoff.

## 1. Purpose

This document is the group specification for cleaning the Philadelphia Real
Estate Transfers data. It defines the rules that both data cleaners must
implement, the two output grains, the checks required before publication, and
the way downstream analyses must use the cleaned data.

The PowerPoint presentation informed these decisions but is not executable
documentation. If a slide, an older CSV, and this specification disagree, the
version 6 rules in this document and `R/BSAN_Proj.R` control.

## 2. Group decisions

The group agreed to:

1. Keep the raw source unchanged.
2. Use the recording date, with display date as a fallback.
3. Limit the analysis to January 2000-July 2026, the latest complete month
   approved by the group; exclude the partial August 2026 records.
4. Remove rows explicitly marked `discrepancy = True` by the source.
5. Preserve repeated `document_id` values because one filing can cover several
   properties.
6. Keep identifiers and ZIP codes as text.
7. Leave missing financial, assessment, and geographic values missing.
8. Create both a detailed `activity_type` and a broad `transaction_type`.
9. Flag deed variants, nominal transfers, unknown consideration, and the upper
   0.1% of non-nominal sale prices.
10. Retain high-value sales in transaction counts but exclude their flagged
    values from typical-price summaries.
11. Publish a parcel-record table as the central clean source and derive a
    separate document table for transaction-level analysis.

## 3. Source structure and analytical grains

The current raw snapshot contains 5,168,394 rows and 47 columns. There are 36
source document types and 16,203 raw rows explicitly marked
`discrepancy = True`.

A source row is a document-property record. One deed may contain several
properties, so repeated `document_id` values are not automatically duplicates.

The pipeline therefore produces two related tables:

| Output | Key | Grain | Main use |
|---|---|---|---|
| `team_data/data_clean.csv.gz` | `record_id` | One property record | Property, assessment, geography, and mapping work |
| `team_data/data_document.csv.gz` | `document_id` | One legal filing | Transaction counts, document totals, forecasting, ward summaries, and Tableau |

`data_clean` is the central cleaned source. `data_document` is a reproducible
derivative, not a competing version of the same table.

## 4. Cleaning rules

### 4.1 Controlled import

The CSV is read with `address_low_frac` forced to text so fractional address
values such as `1/2` are not converted to missing or logical values. Readr
parsing problems are written to `cache/raw_parse_problems.csv`.

`street_postdir` is also forced to text so compass values such as `E`, `W`,
`N`, `S`, and `SW` are preserved rather than misread as logical values.

The following identifiers are stored as text in the shared export:

- `record_id`
- `document_id`
- `opa_account_num`
- `zip5`

They are imported as text directly from the raw CSV. They must not be imported
as floating-point numbers and converted afterward. In particular, very large
`record_id` values can collapse to the same scientific-notation string after a
numeric round trip, creating false duplicate keys.

### 4.2 Source discrepancy removal

The source field is normalized to text before testing. Values equivalent to
`True`, including `true`, `t`, `1`, `yes`, and `y`, are treated as source
discrepancies and removed. `False` and missing values remain.

The number removed is written to the cleaning metadata. The final parcel CSV
does not retain the `discrepancy` column because all explicitly flagged rows
have already been excluded.

### 4.3 Canonical date and time window

The canonical analysis date is:

```r
record_date = as_date(coalesce(recording_date, display_date))
```

Rows are retained only when `record_date` falls from 2000-01-01 through
2026-07-31. This removes records that cannot be placed in a month, sparse
pre-2000 coverage, implausible date years, and the incomplete August 2026
period. Because 2026 contains seven months, annual summaries must label it as
year-to-date or compare January-July consistently across years.

The pipeline derives `year`, `month`, `yr_mo`, and `quarter` from
`record_date`. Supporting `document_date` values outside 1800-2025 are set to
missing in the clean export. The downloaded source file remains unchanged in
Downloads; the project keeps a working copy as its reproducible raw snapshot.

### 4.4 ZIP standardization

`zip_code` is converted to text and truncated to its first five characters as
`zip5`. Missing ZIPs remain missing. The pipeline does not invent a ZIP from
another geography.

This rule standardizes five-digit and concatenated ZIP+4 values. It does not
claim that every nonmissing five-character value is a verified Philadelphia
ZIP; a stricter geographic validity rule would require a separate approved
reference table.

### 4.5 Document classification

The detailed `document_type` remains available. The project derives:

| Rule | `activity_type` | `transaction_type` |
|---|---|---|
| Any known document type containing `DEED` | `sale_deed` | `Sale` |
| `MORTGAGE` or `ORIGINAL FINANCING STATEMENT` | `new_mortgage` | `Loan` |
| Satisfaction, release, or assignment types | `mortgage_lifecycle` | `Loan` |
| Other known types | `other` | `Other` |
| Missing document type | `unknown` | `Other` |

The satisfaction, release, and assignment group includes the explicit mortgage
labels and the source's standalone `SATISFACTION`, `RELEASE`, and `ASSIGNMENT`
labels.

`deed_variant` is `TRUE` when a row is classified as `sale_deed` but its
detailed type is not the exact value `DEED`. Variant deeds remain in sale
counts and can be isolated for sensitivity analysis.

### 4.6 Duplicate handling

`record_id` must be complete and unique in `data_clean`. Repeated
`document_id` values remain because they can represent distinct properties on
the same filing.

No cleaner may use `distinct(document_id, .keep_all = TRUE)` to create the
central parcel file. Transaction counts must come from `data_document` or from
an explicit distinct-document count.

### 4.7 Missing values

The general rule is to leave unknown values unknown.

| Situation | Treatment |
|---|---|
| Missing usable record date | Exclude from the January 2000-July 2026 analytical dataset |
| Missing document ID | Keep in `data_clean`; exclude from document aggregation |
| Missing consideration | Keep and flag when the row is a deed |
| Missing assessment | Leave missing |
| Missing ward or ZIP | Leave missing; charts may display `Unknown` |
| Missing financial amount | Do not replace with zero or an average |

### 4.8 Financial fields

The parcel table keeps reported document amounts separate from adjusted parcel
allocations. For consideration and transfer taxes it contains the original
reported value, the adjusted parcel value, and a convenient parcel value that
prefers the adjusted amount and uses the reported amount as a fallback.

Reported totals may repeat on every parcel row and must not be summed across
`data_clean` without accounting for document grain.

At document grain, the aggregation rule is:

1. Sum adjusted parcel values when every parcel row has an adjusted value.
2. Otherwise use one consistent reported document value.
3. Return missing when adjusted coverage is incomplete and reported values
   conflict.

Coverage percentages, method labels, reconciliation differences, and conflict
flags remain in `data_document`.

### 4.9 Nominal and unknown consideration

`nominal_transfer` identifies a sale deed with known document consideration of
$100 or less. `unknown_consideration` identifies a sale deed whose document
consideration cannot be determined.

Nominal transfers are retained in volume counts but excluded from ordinary
market-price summaries. Missing consideration is not treated as zero or as a
nominal transfer.

### 4.10 High-value sale outliers

High-value transactions are retained. The pipeline calculates the 99.9th
percentile among document-level, non-nominal sale deeds with consideration
above $100. A document strictly above that cutoff receives
`high_value_sale_outlier = TRUE`.

The document-level calculation prevents multi-property filings from receiving
extra weight merely because they contain several parcel rows. The flag is then
copied to every associated parcel row.

The flag affects price summaries, not transaction counts:

- deed and transaction counts retain the flagged documents;
- median price, price distributions, ward price features, clustering price
  inputs, and the Solver price proxy exclude flagged values;
- the metadata records the quantile and calculated dollar cutoff.

## 5. Document-level derivative

`data_document` contains one row per nonmissing `document_id` and sets
`transaction_count = 1`.

When parcel rows disagree, the table retains conflict flags. It uses the
earliest canonical record date and applies the documented financial aggregation
rules. Every document receives at most one `primary_ward` and one
`primary_zip5`, selected by the greatest number of parcel rows with the lowest
code breaking a tie.

The full `document_ward_bridge` remains available for questions about every
ward touched by a filing. It must not be summed for citywide transaction counts.

## 6. Downstream analysis rules

All later sections must select the table that matches the question:

- Use `data_clean` for property records, assessments, property geography, and
  geometry.
- Use `data_document` for deeds, mortgages, tax totals, forecasts, regression
  outcomes, additive ward summaries, optimization, and Tableau document facts.
- Use `activity_type == "new_mortgage"` for new-lending volume. Do not combine
  mortgage lifecycle filings with new mortgages merely because both have
  `transaction_type == "Loan"`.
- Keep nominal deeds and high-value outliers in counts.
- Exclude nominal deeds, unknown prices, and flagged high-value sale prices
  from typical-price calculations.
- Treat recorded transfer tax as a filing amount, not automatically as cash
  revenue received by the City.

## 7. Independent cleaning and cross-check procedure

The second cleaner should create a separate script and output, such as
`data_clean_colleague.csv.gz`. The independent output must not overwrite the
canonical team files.

### 7.1 Before cleaning

Both cleaners must confirm:

- the same raw filename, size, modification date, and preferably checksum;
- 5,168,394 raw rows and 47 columns;
- 36 document-type categories;
- 16,203 raw source-discrepancy rows.

### 7.2 Required comparison report

| Check | Required result |
|---|---|
| Final column names and order | Exact match |
| Parcel row count | Exact match |
| Unique parcel key | `record_id` count equals row count |
| Date range | All dates from 2000-01-01 through 2026-07-31 |
| Counts by year and activity type | Exact match |
| Counts by transaction type and deed variant | Exact match |
| Nominal, unknown-price, and outlier flags | Exact match |
| Column missingness | Exact match |
| Distinct nonmissing document IDs | Exact match |
| Document row count | Equals distinct nonmissing document IDs |
| Financial aggregation methods and conflicts | Exact match |
| Monetary totals | Exact match or approved numeric tolerance |

After comparing summaries, join the parcel versions by `record_id` and compare
the high-risk fields row by row. Repeat the document comparison by
`document_id`.

Every mismatch must be classified as an input-version difference, parsing
difference, business-rule difference, coding error, or approved numeric
rounding. The team must not average two conflicting results.

## 8. Publication and version control

Only one designated publisher should rebuild the canonical files after the two
cleaners reconcile their results. The publisher must:

1. Increment the cache and export versions whenever a cleaning rule or schema
   changes.
2. Rebuild both clean tables and their dictionaries.
3. Confirm all scripted assertions pass.
4. Check that metadata includes both grains, dimensions, discrepancy-removal
   count, outlier quantile, and cutoff.
5. Replace the old shared files only with the validated build.
6. Tell analysts never to edit the shared CSVs manually.

## 9. Scope boundary

The Redfin data described in the presentation has a different
neighborhood-period grain. It must remain a separate cleaned dataset and should
be joined only after the team defines compatible geography and time keys. It is
not appended to the Philadelphia parcel-level `data_clean` file.

## 10. Final rationale

The design preserves valid property detail while preventing transaction
double-counting. It removes source-flagged discrepancies according to the group
decision, exposes document classifications at two useful levels, avoids hidden
imputation, and handles monetary aggregation at the correct grain. The outlier
rule protects typical-price measures without erasing legitimate large
transactions from volume analysis.

```text
Raw RTT source
    -> remove source discrepancies and apply shared cleaning rules
    -> data_clean: one row per record_id
        -> property, assessment, geography, and mapping analysis
        -> data_document: one row per document_id
            -> counts, prices, tax summaries, models, Solver, and Tableau
```
