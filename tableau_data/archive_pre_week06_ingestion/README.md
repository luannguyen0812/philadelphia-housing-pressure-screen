# Tableau ingestion files

Connect the five CSV files in this folder to the final Tableau workbook. Each
file supports one worksheet; the worksheets can then be arranged together on
one client-facing dashboard.

| File | Tableau worksheet | Grain |
|---|---|---|
| `viz1_citywide_activity.csv` | Citywide deed and new-mortgage activity | Month |
| `viz2_citywide_property_price.csv` | Citywide median eligible-property price | Year |
| `viz3_zip_price_projection.csv` | Five-ZIP history and scenario | ZIP × year × series type |
| `viz4_zip_price_income_correlations.csv` | 2024 price-income correlation matrix | Variable pair, with a lower-triangle display flag |
| `viz5_zip_price_income_trend.csv` | Median ZIP price-to-income trend | Year |

Do not join all five CSVs into one physical table: they have different grains.
Add each as a data source, build one worksheet from each source, and combine
the worksheets on the dashboard.

Files elsewhere in `tableau_data/` are supporting facts, model diagnostics,
selection evidence, or possible future dashboard inputs. They do not need to
be connected for the current five-view dashboard. In particular:

- `viz3_selected_zip_codes.csv` explains why the five ZIPs were selected;
- `viz3_zip_projection_accuracy.csv` supports a technical appendix;
- `viz1_recording_delay_diagnostics.csv` compares record-month and
  receipt-month activity and quantifies the 2021-2022 recording delay;
- `model_zip_price_income_correlations.csv` retains annual cross-sectional and
  pooled correlation matrices for technical review;
- `README_export_manifest.csv` documents every export;
- `source_catalog.csv` records data provenance; and
- `TABLEAU_COLUMN_LINEAGE.xlsx` defines every exported column, its data type,
  R formula or transformation, upstream fields, producing script, and any
  fact-checking caveat. Use that workbook for audit and documentation; do not
  connect it as a Tableau data source.

