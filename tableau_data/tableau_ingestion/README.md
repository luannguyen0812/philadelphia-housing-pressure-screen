# Final Tableau ingestion package

This folder contains only the five CSVs required for the final interactive
dashboard. Analytical support files, model diagnostics, and presentation-only
exports remain one level up in `tableau_data/` so Tableau users can immediately
identify the production inputs.

## Relationship model

Use Tableau's **logical relationship layer**, not physical joins. Drag
`dim_geography.csv` onto the data model first, then relate each fact to it on
`geography_key`.

```text
                          dim_geography
                        geography_key (PK)
                  /          |          |          \
                 /           |          |           \
 fact_zip_profile  fact_annual_signals  fact_monthly_forecast  fact_policy_response
 geography_key FK  geography_key FK     geography_key FK       geography_key FK
```

All four facts relate directly to `dim_geography`. Do **not** relate one fact
to another.

For every relationship, use:

- fields: `geography_key = geography_key`;
- cardinality: `dim_geography` is **One**, fact is **Many** (the ZIP-profile
  fact is technically one-to-one, but One-to-Many is safe for a uniform model);
- referential integrity: **All records match**; and
- join type: relationship/automatic, not a fixed physical inner or left join.

## Required files and grains

| File | Grain / primary key | Dashboard purpose |
|---|---|---|
| `dim_geography.csv` | one row per `geography_key` | The shared ZIP filter, default-case flags, labels, and availability flags |
| `fact_zip_profile.csv` | one row per `geography_key` | Citywide selection scatter, KPI cards, vulnerability, price/income, outcome, and percentile comparison |
| `fact_annual_signals.csv` | `geography_key` + `year` | Price, income, RTT sales, permits, eviction filings, inventory, days on market, and ACS measures over time |
| `fact_monthly_forecast.csv` | `geography_key` + `month` + `series_type` | Observed monthly sales and the primary forecast with 80%/95% intervals; case-study-only |
| `fact_policy_response.csv` | one row per `recommendation_key` | Evidence trigger, conditional City response, lead time, monitoring metric, and claim boundary |

The build validates primary-key uniqueness and orphan foreign keys. Results are
written to `tableau_data/week06_final_package_audit.csv`.

## One-dashboard design

Build one 16:9 dashboard titled **Philadelphia Housing Pressure: Context,
Trajectory, and Response**. It should contain these sheets:

1. **ZIP context scatter** — all 37 qualifying ZIP/ZCTAs remain visible;
   selected ZIPs are highlighted. Use price CAGR on x, vulnerability percentile
   on y, with bold median reference lines.
2. **Selected ZIP evidence profile** — show market growth, vulnerability,
   transaction contraction, price-to-income, filing rate, and permit-pipeline
   percentiles on a 0-100 common scale. Do not average them into one score.
3. **Annual signal trend** — use a measure parameter to switch between Redfin
   price, ACS income, RTT eligible sales, eviction filing rate, permitted units,
   inventory, and days on market. Keep the Philadelphia benchmark available.
4. **Observed and forecast activity** — observed monthly activity in charcoal,
   forecast in orange, and dark-blue 80%/95% bands. Label this sheet
   **Case-study-only conditional baseline**.
5. **Evidence-to-response table** — display action, priority, evidence trigger,
   response, lead time, monitoring metric, and claim boundary for the selection.
6. **Limitations footer** — ACS sampling/MOE, ZIP-ZCTA approximation,
   property-versus-unit definition, Redfin-versus-RTT definitions, filings not
   completed evictions, permits not completed units, and forecast uncertainty.

## Filter behavior

- Create a Tableau set named **Selected ZIPs** from
  `dim_geography[zip5]` and show its multi-select set control. Use the set as
  the shared selector instead of a destructive ordinary ZIP filter.
- Publish/open the workbook with **19132 and 19143 selected**. Tableau does not
  encode set membership from a CSV, so save the workbook in that state.
- Add a **Reset to 19132 + 19143** dashboard button or saved custom view.
- Add an **All qualifying ZIPs** reset/view.
- On the context scatter, color by **Selected ZIPs** and do not filter the
  sheet, so the other 35 comparison points remain visible.
- On annual detail sheets, filter with a calculated field such as
  `[Geography Level] = "City benchmark" OR [Selected ZIPs]`. This preserves
  the City row while limiting ZIP lines to the selected set.
- Other detail sheets respond to the set. The forecast sheet uses
  `forecast_available`; a non-case selection must show “Forecast not built for
  this ZIP” rather than a blank chart.
- Policy rows for non-case ZIPs explicitly say “Monitoring only—case-specific
  recommendation not validated.”

## Color and interpretation rules

- 19132: orange `#D95F0E`
- 19143: dark blue `#08519C`
- Philadelphia benchmark: charcoal `#252525`
- other qualifying ZIPs: gray `#7F7F7F`
- uncertainty bands: dark blues `#3182BD` and `#08519C`

Never describe the dashboard as proof that gentrification or displacement
occurred. It identifies housing pressure, resident exposure, observed outcome
signals, and conditional policy pathways.

The previous five-chart Tableau package and workbook were moved to
`tableau_data/archive_pre_week06_ingestion/`; they are retained for recovery
but are not part of the final dashboard connection.
