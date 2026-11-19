# Week 6 Tableau build steps — reconstructed from the repo

This guide reconstructs the step-by-step Tableau build for the final Week 6
interactive dashboard. It is based on the actual files in
`tableau_data/tableau_ingestion/`, the R export script
`R/week06_dashboard_exports.R`, and the package specification in
`tableau_data/tableau_ingestion/README.md`.

The lost chat history is not recoverable, but the repo is specific enough to
rebuild the workbook without guessing.

---

## 0. What is in the final package

Connect only the five CSVs in `tableau_data/tableau_ingestion/`.

| File | Rows | Grain / primary key | Dashboard use |
|---|---:|---|---|
| `dim_geography.csv` | 38 | one row per `geography_key` | Shared ZIP selector, labels, case flags, forecast availability |
| `fact_zip_profile.csv` | 38 | one row per `geography_key` | All-ZIP scatter, KPI table, evidence percentile profile |
| `fact_annual_signals.csv` | 456 | `geography_key` + `year` | Annual trend with a measure selector |
| `fact_monthly_forecast.csv` | 624 | `geography_key` + `month` + `series_type` | Observed monthly sales and 2026–2035 forecast with intervals |
| `fact_policy_response.csv` | 43 | one row per `recommendation_key` | Evidence-to-response matrix and detail table |

The dimension has 37 selectable ZIP/ZCTAs plus one non-selectable
Philadelphia benchmark row (`CITY_PHL`). The 43 policy rows are 35
monitoring-only rows plus 4 case-study recommendations for 19132 and 4 for
19143.

`tableau_data/week06_final_package_audit.csv` confirms that the dimension key is
unique and that every fact's `geography_key` resolves to the dimension.

### Version assumptions

- **Tableau Desktop 2020.2 or newer** for the logical relationship layer and
  Measure Names/Values. Relationships are not available in older versions.
- **2020.2 or newer** for Small Multiples; fallbacks are given in Worksheet 5.
- **2022.3 or newer** for Dynamic Zone Visibility; this is optional. Use the
  permanent forecast note if your version does not support it.
- If you are on an older version, use a separate data source per fact and place
  the sheets side by side; still do not physically join the facts.

### Build order at a glance

1. Connect the five CSVs.
2. Set data types and create `ZIP5 Clean`.
3. Build the logical relationship model.
4. Create the `Selected ZIPs` set and the display helpers.
5. Create the annual parameter and the forecast/policy helpers.
6. Build the six worksheets.
7. Assemble the 1600×900 dashboard.
8. Add the set control, highlight action, and response filter action.
9. Run the QA checklist and save in the default 19132 + 19143 state.
10. Build the second dashboard (forecast + response) — section 12.2.
11. Replace the ZIP list with a map selector — section 12.3.

---

## 1. Build principles

Follow these rules or the dashboard will show inflated counts.

1. **Use Tableau relationships, not physical joins.** The facts have different
   grains. A physical join would repeat annual, monthly, or policy rows.
2. **Build one fact per worksheet.** Do not put a profile measure, an annual
   measure, and a monthly measure on the same sheet. Tableau may create a
   query-time join across facts.
3. **Relate every fact directly to `dim_geography` on `geography_key`.** Never
   relate one fact to another.
4. **Treat `zip5` as text.** Do not let Tableau convert it to a number or give
   it a geographic role.
5. **Use the `Selected ZIPs` set as the shared selector.** Do not put an
   ordinary ZIP filter on the context scatter.
6. **Keep all 37 qualifying ZIPs in the scatter.** The set membership changes
   color and size, not the distribution.
7. **Keep the City benchmark on annual sheets.** Use
   `City benchmark OR Selected ZIPs`, not the set alone.
8. **Label the forecast case-study-only.** It exists only for 19132 and 19143.

---

## 2. Connect the five CSVs

1. Open Tableau Desktop and choose **Connect > Text file**.
2. Select `tableau_data/tableau_ingestion/dim_geography.csv`.
3. In the data source page, rename the connection something clear, for example
   `Week 6 Final Model`.
4. Add the other four CSVs:
   - `fact_zip_profile.csv`
   - `fact_annual_signals.csv`
   - `fact_monthly_forecast.csv`
   - `fact_policy_response.csv`
5. Do not add the files in `tableau_data/` itself, and do not add
   `README.md` or the audit CSVs.

Recommended source name: **Week 6 Final Model**.

---

## 3. Set data types before building anything

In the data source page, click the data-type icon above each column and set:

| Column | Type | Notes |
|---|---|---|
| `geography_key` | String | Key field in all tables |
| `zip5` | String | ZIP codes must stay text; set geographic role to **None** |
| `year` | Number (Whole) | Annual fact only |
| `month` | Date | Monthly fact only |
| `priority_score`, `dashboard_order`, `geography_sort` | Number (Whole) | Sorting |
| boolean flags (`selectable_zip`, `default_dashboard_selection`, `case_study_detail_available`, `forecast_available`, `training_observation`, `displayed_in_default_view`) | Boolean | If Tableau infers String, change to Boolean |
| all price, income, rate, percentile, count, and unit fields | Number (Decimal or Whole) | Use Whole for counts/units |

After the types are set, right-click `year` and `dashboard_order` in the Data
pane and choose **Convert to Dimension**. They are numeric identifiers, not
additive measures. `year` must be a dimension for `MAKEDATE([year], 1, 1)` to
work correctly.

### The `"NA"` issue

The CSVs were written by R with `NA` as the literal string `"NA"` for missing
values. Tableau may infer some numeric columns as String because of those
values. After setting a column to Number, verify that `NA` appears as **Null**,
not as a text value.

If a numeric column still behaves like text, create a cleaned calculated field
with this pattern:

```tableau
IF [median_household_income] = "NA" THEN NULL
ELSE FLOAT([median_household_income])
END
```

Do this only for columns that actually misbehave. Do not convert `zip5` to a
number.

### Create `ZIP5 Clean`

The City benchmark has `zip5 = "NA"`, not a true null. Create this calculated
field on `dim_geography`:

```tableau
IF ISNULL([zip5]) OR [zip5] = "NA" OR [zip5] = "" THEN NULL
ELSE [zip5]
END
```

Name it **ZIP5 Clean**. Use it for the set, labels, and tooltips. This prevents
the City benchmark from appearing as the literal ZIP `"NA"`.

---

## 4. Build the logical relationship model

1. In the data source page, open the **Logical** layer (not **Physical**).
2. Drag `dim_geography` onto the logical canvas first.
3. Drag `fact_zip_profile` onto the canvas.
4. If Tableau auto-creates a relationship, click the relationship line and edit
   it. If it relates the fact to another fact, delete that line.
5. Create or edit each relationship with these settings:

| Left table | Right table | Field pair | Cardinality | Referential integrity | Join type |
|---|---|---|---|---|---|
| `dim_geography` | `fact_zip_profile` | `geography_key = geography_key` | One to Many (One to One is also safe) | All records match | Relationship / Automatic |
| `dim_geography` | `fact_annual_signals` | `geography_key = geography_key` | One to Many | All records match | Relationship / Automatic |
| `dim_geography` | `fact_monthly_forecast` | `geography_key = geography_key` | One to Many | All records match | Relationship / Automatic |
| `dim_geography` | `fact_policy_response` | `geography_key = geography_key` | One to Many | All records match | Relationship / Automatic |

Resulting model:

```text
                         dim_geography
                       geography_key (PK)
                 /           |           |           \
                /            |           |            \
 fact_zip_profile  fact_annual_signals  fact_monthly_forecast  fact_policy_response
  geography_key FK  geography_key FK     geography_key FK       geography_key FK
```

Do **not** create a relationship from `fact_zip_profile` to
`fact_annual_signals`, or any other fact-to-fact line. Their grains differ.

### Quick model validation

Create a scratch sheet with `dim_geography[geography_key]` on Rows. It should
show 38 rows, one per key. Alternatively, drag `COUNTD([geography_key])` to Text
with no dimension on Rows; it should show 38. If it shows more, a physical join
or duplicate relationship has multiplied rows.

---

## 5. Create the calculated fields and parameters

Create these in the data source. The table is named where the calculation must live on a specific fact.

### 5.1 Create `ZIP5 Clean` first

If you did not create it in section 3, create **ZIP5 Clean** on
`dim_geography` now:

```tableau
IF ISNULL([zip5]) OR [zip5] = "NA" OR [zip5] = "" THEN NULL
ELSE [zip5]
END
```

This field is a prerequisite for the set and every display helper below.

### 5.2 Create the `Selected ZIPs` set

1. Right-click `ZIP5 Clean` in the Data pane.
2. Choose **Create > Set**.
3. Name it **Selected ZIPs**.
4. Select **19132** and **19143**.
5. Click OK.
6. Right-click the set and choose **Show Set** so the multi-select control is
   available on the dashboard.

If the set control shows a `Null` member for the City benchmark, leave it
unselected. The ZIP-only sheets also filter `selectable_zip = TRUE`, so the City
row cannot leak into the KPI, evidence, or policy views.

The CSV's `default_dashboard_selection = TRUE` is only a documentation flag.
Tableau does not read it as a workbook selection. You must set 19132 and 19143
manually and save the workbook in that state.

### 5.3 Selection and display helpers

Create these on `dim_geography` after the set exists.

| Name | Formula | Purpose |
|---|---|---|
| `ZIP Color Group` | see below | Consistent 19132/19143/City/other colors |
| `ZIP Point Size` | see below | Slightly larger selected points |
| `Scatter Label` | see below | Label only selected ZIPs on the scatter |
| `City Benchmark Flag` | `[geography_level] = "City benchmark"` | Optional color/size helper |

`ZIP Color Group`:

```tableau
IF [ZIP5 Clean] = "19132" THEN "19132"
ELSEIF [ZIP5 Clean] = "19143" THEN "19143"
ELSEIF [geography_level] = "City benchmark" THEN "Philadelphia benchmark"
ELSEIF [Selected ZIPs] THEN "Other selected ZIP"
ELSE "Other qualifying ZIPs"
END
```

`ZIP Point Size`:

```tableau
IF [Selected ZIPs] THEN 2 ELSE 1 END
```

`Scatter Label`:

```tableau
IF [Selected ZIPs] THEN [ZIP5 Clean] ELSE "" END
```

### 5.4 Annual trend parameter and measure

The annual selector intentionally uses only measures that are comparable
between the City benchmark and a single ZIP. That means no raw pooled counts.
Raw RTT sales, raw permitted units, and raw Redfin inventory are excluded from
the menu; their normalized per-1,000-occupied-unit versions replace them.

#### 5.4.1 Create the normalized volume measures first

Create **Occupied Units 2024** on `fact_annual_signals`:

```tableau
{ FIXED [geography_key] : MAX([occupied_housing_units]) }
```

`occupied_housing_units` is populated only in the 2024 ACS row, so this LOD
carries the 2024 denominator to every year.

Then create these three measures:

```tableau
// RTT Sales per 1,000 Occupied Units
IF [Occupied Units 2024] > 0 THEN
  [rtt_eligible_sales] / [Occupied Units 2024] * 1000
END
```

```tableau
// Permitted Units per 1,000 Occupied Units
IF [Occupied Units 2024] > 0 THEN
  [permitted_units] / [Occupied Units 2024] * 1000
END
```

```tableau
// Inventory per 1,000 Occupied Units
IF [Occupied Units 2024] > 0 THEN
  [redfin_inventory] / [Occupied Units 2024] * 1000
END
```

Do **not** use `permitted_units_2023_2025` or
`permitted_units_per_1000_occupied_2023_2025` from `fact_zip_profile` in the
annual calculation. Those are 3-year cumulative profile fields and produce a
flat 13.2 / 7.0 line. The annual measure must use `[permitted_units]` from
`fact_annual_signals`, which is the single-year flow.

Permitted-unit values at a glance:

| Measure | 19132 | 19143 | What it is |
|---|---:|---:|---|
| `permitted_units`, 2025 | 50 | 90 | Single-year raw count |
| `Permitted Units per 1,000 Occupied Units`, 2025 | 3.5 | 3.1 | Single-year flow rate |
| `permitted_units_per_1000_occupied_2023_2025` | 13.2 | 7.0 | Three-year cumulative pipeline rate |
| `SUM([permitted_units])`, 2014–2025 | 913 | 764 | Twelve-year raw total |
| `AVG([permitted_units])`, 2014–2025 | 76 | 64 | Twelve-year average annual raw count |
| Average annual per 1,000, 2014–2025 | 5.3 | 2.2 | Twelve-year average annual flow rate |

If you see **913 / 764**, you are summing annual permitted units across the
entire 2014–2025 panel because there is no year filter or year axis on the
sheet. If you see **76 / 64**, you changed the aggregation to `AVG`, which
averages the same 12 annual counts. If you see **13.2 / 7.0**, you are using
the 3-year profile measure. If you see **3.5 / 3.1**, you have the correct 2025
annual per-1,000 rate.

#### 5.4.2 Create the parameter

Create a parameter **Select Annual Measure**:

- Data type: String
- Allowable values: List
- Values, in this order:
  1. `Redfin median sale price`
  2. `ACS median household income`
  3. `RTT Sales per 1,000 Occupied Units`
  4. `Eviction filings per 1,000 renters`
  5. `Permitted Units per 1,000 Occupied Units`
  6. `Inventory per 1,000 Occupied Units`
  7. `Redfin median days on market`
- Current value: `Redfin median sale price`

This is the final seven-item menu. Do not include raw `RTT eligible sales`,
raw `Permitted units`, or raw `Redfin inventory`; those are the distorted
pooled-count views.

The parameter is only the menu label. `Selected Annual Measure` maps each
label to a field. If you rename or add a menu item later, update both objects
with exactly the same text.

#### 5.4.3 Create `Selected Annual Measure`

```tableau
CASE [Select Annual Measure]
WHEN "Redfin median sale price" THEN [redfin_median_sale_price]
WHEN "ACS median household income" THEN [median_household_income]
WHEN "RTT Sales per 1,000 Occupied Units" THEN [RTT Sales per 1,000 Occupied Units]
WHEN "Eviction filings per 1,000 renters" THEN [eviction_filings_per_1000_renters]
WHEN "Permitted Units per 1,000 Occupied Units" THEN [Permitted Units per 1,000 Occupied Units]
WHEN "Inventory per 1,000 Occupied Units" THEN [Inventory per 1,000 Occupied Units]
WHEN "Redfin median days on market" THEN [redfin_median_days_on_market]
ELSE NULL
END
```

#### 5.4.4 Create `Selected Annual Measure Unit`

```tableau
CASE [Select Annual Measure]
WHEN "Redfin median sale price" THEN "USD"
WHEN "ACS median household income" THEN "USD"
WHEN "RTT Sales per 1,000 Occupied Units" THEN "eligible sales per 1,000 occupied housing units"
WHEN "Eviction filings per 1,000 renters" THEN "filings per 1,000 renter households"
WHEN "Permitted Units per 1,000 Occupied Units" THEN "permitted units per 1,000 occupied housing units"
WHEN "Inventory per 1,000 Occupied Units" THEN "homes per 1,000 occupied housing units"
WHEN "Redfin median days on market" THEN "days"
ELSE ""
END
```

#### 5.4.5 Annual filter, date, and line helpers

Create **Annual ZIP Filter** on `fact_annual_signals`:

```tableau
[geography_level] = "City benchmark" OR [Selected ZIPs]
```

Create **Year Date** on `fact_annual_signals`:

```tableau
MAKEDATE([year], 1, 1)
```

Create **Line Weight** on `fact_annual_signals`:

```tableau
IF [geography_level] = "City benchmark" THEN 3
ELSEIF [ZIP5 Clean] = "19132" OR [ZIP5 Clean] = "19143" THEN 2.5
ELSE 1
END
```

### 5.5 Forecast helpers

Create these on `fact_monthly_forecast`:

```tableau
// Observed Sales
IF [series_type] = "Observed" THEN [monthly_sales] END

// Forecast Sales
IF [series_type] = "Forecast" THEN [monthly_sales] END
```

The four interval fields (`lower_80`, `upper_80`, `lower_95`, `upper_95`) can
be used directly; they are null for observed rows.

Create **Forecast Month** if Tableau does not parse `month` as a date:

```tableau
MAKEDATE(INT(LEFT([month], 4)), INT(MID([month], 6, 2)), 1)
```

Do this only if the `month` column is text. If it is already a Date, use it as
is.

### 5.6 Policy table helpers

Create these on `fact_policy_response`:

```tableau
// Priority Sort
CASE [priority]
WHEN "High" THEN 1
WHEN "Medium" THEN 2
ELSE 3
END
```

```tableau
// Response Card
"PRIORITY: " + IFNULL([priority], "") + CHAR(10) +
"EVIDENCE: " + IFNULL([evidence_trigger], "") + CHAR(10) +
"RESPONSE: " + IFNULL([proposed_city_response], "") + CHAR(10) +
"LEAD TIME: " + IFNULL([delivery_lead_time], "") + CHAR(10) +
"MONITOR: " + IFNULL([monitoring_metric], "") + CHAR(10) +
"BOUNDARY: " + IFNULL([claim_boundary], "")
```

If Tableau displays `CHAR(10)` as a visible symbol, use `CHAR(13)` or insert a
literal line break in the calculation editor.

---

## 6. Build the worksheets

### Worksheet 1 — All-ZIP context scatter

**Purpose:** show where 19132 and 19143 sit among all 37 qualifying ZIP/ZCTAs
without hiding the other 35 comparison points.

Shelves:

| Shelf | Field |
|---|---|
| Columns | `AVG([redfin_2015_2024_cagr])` |
| Rows | `AVG([vulnerability_percentile])` |
| Detail | `ZIP5 Clean`, `geography_label` |
| Color | `ZIP Color Group` |
| Size | `AVG([ZIP Point Size])` |
| Label | `Scatter Label` |
| Tooltip | ZIP, case group, CAGR, vulnerability, transaction change, price-to-income, eviction rate, permitted units |

Filters:

- `selectable_zip = TRUE` (this removes the City benchmark and keeps exactly 37
  ZIP points).
- **Do not** add `Selected ZIPs` as a filter. The set only controls color and
  size.

Reference lines:

1. Right-click the x-axis > **Add Reference Line**.
2. Scope: **Entire Table**.
3. Line: **Median** of `redfin_2015_2024_cagr`.
4. Label: `Median price CAGR`, bold, dashed, charcoal `#252525`.
5. Repeat on the y-axis with the median of `vulnerability_percentile`.
6. Label: `Median vulnerability`.

Formatting:

- x-axis: percent, 1 decimal; title `Redfin price CAGR, 2015–2024`.
- y-axis: percent, 0 decimals; title `Resident vulnerability percentile`.
- Mark size range: 4–9; selected points slightly larger.
- Colors:
  - 19132: `#D95F0E`
  - 19143: `#08519C`
  - other selected ZIPs: `#7F7F7F`
  - other qualifying ZIPs: `#BDBDBD`
  - City benchmark: `#252525` (not shown on the scatter)
- Tooltip note: `Screening evidence; not proof of individual displacement.`

QA: the sheet should show `COUNTD([ZIP5 Clean]) = 37`. If it shows 38, the
City row is still included. If it shows 35, the set is filtering the sheet.

Optional quadrant tooltip:

```tableau
IF [redfin_2015_2024_cagr] >= { FIXED : MEDIAN([redfin_2015_2024_cagr]) }
AND [vulnerability_percentile] >= { FIXED : MEDIAN([vulnerability_percentile]) }
THEN "High growth / high vulnerability"
ELSEIF [redfin_2015_2024_cagr] >= { FIXED : MEDIAN([redfin_2015_2024_cagr]) }
THEN "High growth / lower vulnerability"
ELSEIF [vulnerability_percentile] >= { FIXED : MEDIAN([vulnerability_percentile]) }
THEN "Lower growth / high vulnerability"
ELSE "Lower growth / lower vulnerability"
END
```

Keep this in the tooltip, not in the color encoding; the color encoding is
reserved for the case-study palette.

---

### Worksheet 2 — Case-study KPI comparison

**Purpose:** compare the two case ZIPs on the headline measures without
aggregating them into one misleading total.

Shelves:

| Shelf | Field |
|---|---|
| Rows | `ZIP5 Clean` |
| Columns | `Measure Names` |
| Text | `Measure Values` |
| Detail | `case_group`, `display_group` |

Mark type: **Text**. This is a crosstab/KPI table, not a dot plot. Do not put
anything on Size, Shape, or Color, and do not use Circle marks; otherwise you
get stray dots next to the ZIP labels.

Filters:

- `Selected ZIPs` (set) = In
- `selectable_zip = TRUE`

Measure Names filter — start with six headline measures:

- `median_sale_price_2024`
- `redfin_2015_2024_cagr`
- `median_household_income_2024`
- `price_to_income_2024`
- `vulnerability_percentile`
- `eviction_filings_per_1000_renters_2025`

If the KPI zone is at least 700 px wide, add `transaction_change_pct` and
`permitted_units_2023_2025`. Otherwise keep those two in the tooltip or in the
response detail, so the table does not become unreadable.

Alias the Measure Names headers to short labels:

| Field | Alias |
|---|---|
| `median_sale_price_2024` | `2024 price` |
| `redfin_2015_2024_cagr` | `Price CAGR` |
| `median_household_income_2024` | `2024 income` |
| `price_to_income_2024` | `Price / income` |
| `vulnerability_percentile` | `Vulnerability` |
| `eviction_filings_per_1000_renters_2025` | `Eviction rate` |
| `transaction_change_pct` | `Transaction change` |
| `permitted_units_2023_2025` | `Permit units` |

If your Tableau version does not allow Measure Names aliases, use the full
field names and widen the KPI zone, or rename the fields in the Data pane with
short labels. Set the Measure Names order to **Manual** and drag the columns
into the order shown above.

Formatting:

| Measure | Format |
|---|---|
| `median_sale_price_2024` | Currency, 0 decimals |
| `redfin_2015_2024_cagr` | Percent, 1 decimal |
| `median_household_income_2024` | Currency, 0 decimals |
| `price_to_income_2024` | Number, 2 decimals, custom `0.00"x"` |
| `vulnerability_percentile` | Percent, 1 decimal |
| `eviction_filings_per_1000_renters_2025` | Number, 1 decimal |
| `transaction_change_pct` | Percent, 1 decimal |
| `permitted_units_2023_2025` | Number, 0 decimals |

If every KPI cell displays as a huge percentage — for example, `$32,823`
appears as `3,282,300%` — Tableau is applying **Percentage** format to the
entire `Measure Values` field. Reset `Measure Values` to **Automatic**, then
apply the per-measure formats above. Do not set one number format on the
`Measure Values` pill; it applies to every measure in the table.

Sort `ZIP5 Clean` by `MIN([dashboard_selection_order])` ascending so 19132 is
first and 19143 is second.

Add a footnote text box: `Endpoint income MOE status is in the tooltip; ACS
estimates carry sampling error.`

Expected values:

| Measure | 19132 | 19143 |
|---|---:|---:|
| 2024 median sale price | $80,000 | $170,500 |
| 2015–2024 price CAGR | 17.0% | 11.2% |
| 2024 median household income | $32,823 | $43,244 |
| 2024 price-to-income | 2.44x | 3.94x |
| Vulnerability percentile | 73.9% | 63.6% |
| 2025 eviction filing rate | 55.2 | 34.7 |
| Transaction change, 2022–24 vs 2015–17 | -33.2% | -13.9% |
| Permitted units, 2023–2025 | 191 | 201 |

---

### Worksheet 3 — Selected ZIP evidence profile

**Purpose:** put six unlike measures on one common 0–100 percentile scale
without averaging them into a single score.

Shelves:

| Shelf | Field |
|---|---|
| Rows | `Measure Names` |
| Columns | `Measure Values` |
| Color | `ZIP Color Group` |
| Detail | `ZIP5 Clean`, `geography_label` |
| Label | `Measure Values` (optional) |

Filters:

- `Selected ZIPs` (set) = In
- `selectable_zip = TRUE`

This sheet is intentionally a **selected-ZIP detail view**. With the default
set it shows only 19132 and 19143. The all-37 comparison is Worksheet 1, the
context scatter. If you want all 37 in this profile too, remove the
`Selected ZIPs` filter, keep `selectable_zip = TRUE`, and use `ZIP Color Group`
plus `ZIP Point Size` to highlight the selected cases; expect 222 marks
(37 ZIPs × 6 measures), so it will be much denser.

Do not add `case_study_detail_available = TRUE` here unless you intentionally
want to hard-code the sheet to the two case studies regardless of the set.

Measure Names filter — keep only these six percentile measures, in this row
order (manual sort on `Measure Names`):

- `price_growth_percentile`
- `affordability_ratio_percentile`
- `vulnerability_percentile`
- `transaction_contraction_percentile`
- `eviction_rate_percentile`
- `permit_pipeline_percentile`

Alias the Measure Names members so they read in the intended order:

1. `1. Price-growth speed`
2. `2. Price-to-income ratio`
3. `3. Resident vulnerability`
4. `4. Transaction contraction`
5. `5. Eviction-filing rate`
6. `6. Permitted-unit pipeline`

Rows 1 and 2 are deliberately adjacent. Row 1 is the *rate* of price change; row
2 is the 2024 *level* of price relative to income. Stacking them means the
reader sees "fastest growth" immediately above "the level that growth has
reached," which is the 19132 story (17.0% CAGR, 100th percentile, above a 2.44x
ratio, 1st percentile).

Row 2 is the one row whose direction inverts the visual: high price-to-income
means *less affordable*, so 19132's dot at 0% reads as "cheapest of the 37," not
"least pressure." Caption it in the sheet subtitle, e.g. `2. Price-to-income
ratio — higher = less affordable; 19132 is the lowest of 37 at 2.44x (0.92x in
2014)`. Do not flip the field to income-to-price: that only relocates the
misreading and would put 19132 at 100%, implying it is the *most* unaffordable
ZIP, which is false.

If aliases are unavailable, rename the fields in the Data pane with the numeric
prefixes or set Measure Names to a manual sort and drag the rows into order.

Formatting:

- Mark: Circle, size 8–10. This sheet is intentionally a dot plot: each row is
  a measure, each dot is a ZIP, and the x-axis is the percentile. The dots are
  the graph, not decoration.
- If you want a table-like alternative, use a highlight table instead: Measure
  Names on Rows, ZIP5 Clean on Columns, Measure Values on Text, and Measure
  Values on Color. Do not mix dots into a text table.
- x-axis: set the fixed range to 0–1 and format as percent, 0 decimals; this
  displays 0–100%.
- With `Measure Names` on Rows, Tableau may create a separate axis per measure
  row. Right-click the Measure Values axis and choose **Uniform Axis** (or set
  each row to the same fixed 0–1 range) so all six rows share the common scale.
- Add a reference line at **0.5** (50%), scope **Per Cell** if available,
  otherwise Entire Table. Label `Qualifying-ZIP median`, dashed, charcoal.
- Colors: 19132 orange, 19143 blue, other selected gray.
- Label: percent, 0 decimals. If labels clutter when more than two ZIPs are
  selected, turn labels off and keep the tooltip.
- The percentile fields are already 0–1. Do **not** multiply them by 100 in a
  calculated field. If you see values like `80,000%`, either the field was
  multiplied by 100/1,000 or the `Measure Values` format is being applied on
  top of an already-scaled value. Use the raw percentile field and format the
  axis as percent.

This is a dot plot, not a line chart. Do not connect the six measures with a
line: that would imply the measures are a time sequence or a single index.

Tooltip: measure name, ZIP, percentile, and the note `Higher means more
pressure or exposure for the definition on this row; the 50% line is the
qualifying-ZIP median, not a pass/fail cutoff.`

---

### Worksheet 4 — Annual signal trend

**Purpose:** let the user switch among seven annual measures while keeping the
Philadelphia benchmark visible.

Shelves:

| Shelf | Field |
|---|---|
| Columns | `Year Date` (continuous exact date) |
| Rows | `SUM([Selected Annual Measure])` |
| Color | `ZIP Color Group` |
| Detail | `geography_label`, `ZIP5 Clean` |
| Size | `AVG([Line Weight])` (optional) |
| Tooltip | ZIP, year, measure value, unit, ACS period, source note |

Filters:

- `Annual ZIP Filter = TRUE`

Do **not** also put `Selected ZIPs` on the filter shelf; the calculated
`Annual ZIP Filter` already handles the City exception.

Parameter control:

- Right-click `Select Annual Measure` > **Show Parameter**.
- Place the control above the chart or in the sheet header.

Formatting:

- Mark: Line; show markers.
- Columns: continuous date, format `yyyy`.
- Color: 19132 orange, 19143 blue, City charcoal `#252525`, other selected
  gray, other qualifying gray.
- City line: thicker than ZIP lines. If Size does not vary by `Line Weight`,
  leave all lines at 2 and rely on color.
- Dynamic title: `Annual signal: <Parameters.Select Annual Measure>`.
- Axis title: `Value (units vary by selected measure)`.
- Do not apply a dollar sign to the axis. The parameter switches among dollars,
  rates, and days; exact units are in the tooltip.
- Tooltip: include `Selected Annual Measure Unit` and
  `source_definition_note`.

Measure availability to expect:

| Measure | Years with data |
|---|---|
| Redfin median sale price | 2014–2025 |
| ACS median household income | 2014–2024 |
| RTT sales per 1,000 occupied units | 2014–2025 |
| Eviction filings per 1,000 renters | 2020–2025 |
| Permitted units per 1,000 occupied units | 2014–2025 |
| Inventory per 1,000 occupied units | 2015–2025 |
| Redfin median days on market | 2015–2025 |

Blank years are source gaps, not zeros. Add a caption: `Blank years mean the
source does not cover that measure; they are not zero.`

**ACS income points are not one-year estimates.** Every `median_household_income`
value is a five-year ACS average: the 2023 point is 2019-2023 and the 2024 point
is 2020-2024, so the two share four of their five sample years. Do not read a
2023-to-2024 move as a one-year change in resident income.

Worked example, and the most likely source of a "the chart disagrees with the
KPI" question: 19143 reads 47,964 in 2023 (2019-2023) and 43,244 in 2024
(2020-2024). That 9.8% drop is a re-estimation between overlapping windows, not
a one-year decline. Both tables agree, and the KPI table must show 43,244 for
19143 and 32,823 for 19132 in 2024. Verify with a hover: the tooltip should print
`acs_estimate_period` as `2020-2024` for the 2024 point and `2019-2023` for the
2023 point.

For this reason, put `acs_estimate_period` in the tooltip of worksheet 4, and
keep the growth-gap narrative on the 2014-to-2024 endpoints rather than on
adjacent years.

#### Why the raw volume measures were removed

The City row is a **37-ZIP benchmark**, not a single ZIP and not a whole-city
household total. Its construction differs by measure:

| Raw field | City construction | Selector status |
|---|---|---|
| `redfin_median_sale_price` | Median across 37 ZIPs | Kept |
| `median_household_income` | Median across 37 ZIPs | Kept |
| `rtt_eligible_sales` | Pooled sum across 37 ZIPs | **Removed** — replaced by RTT sales per 1,000 |
| `eviction_filings_per_1000_renters` | Pooled City rate | Kept |
| `permitted_units` | Pooled sum across 37 ZIPs | **Removed** — replaced by permitted units per 1,000 |
| `redfin_inventory` | Pooled sum across 37 ZIPs | **Removed** — replaced by inventory per 1,000 |
| `redfin_median_days_on_market` | Median across 37 ZIPs | Kept |

In 2025, the City benchmark has 18,713 RTT eligible sales, while 19132 has 776
and 19143 has 1,058. The City value is roughly 18–24 times a single ZIP because
it is a pooled 37-ZIP total. That is why the raw view looked distorted: the
axis was scaled to a total while the ZIP lines were components. The normalized
per-1,000 measures in section 5.4.1 put the City and ZIP lines on a common
denominator, so the selector now contains only comparable measures.

2025 values for QA:

| Measure | City 37-ZIP benchmark | 19132 | 19143 |
|---|---:|---:|---:|
| RTT sales per 1,000 occupied units | 30.7 | 53.6 | 36.9 |
| Permitted units per 1,000 occupied units | 4.0 | 3.5 | 3.1 |
| Inventory per 1,000 occupied units | 7.6 | 15.2 | 8.7 |

This changes the presentation story in a useful way: 19132 has a much higher
transaction rate per housing unit than the City benchmark, and 19143's permit
rate is slightly below 19132 even though its raw permit count is higher,
because 19143 has about twice the housing stock.

The raw counts can remain in `fact_annual_signals` and in the tooltip for audit,
but they are no longer selectable from the annual menu.

Presentation wording:

> "The City benchmark is a pooled 37-ZIP total for raw volume measures, so it
> is naturally an order of magnitude larger than a single ZIP. The annual menu
> uses rates per 1,000 occupied housing units instead, which puts the City and
> the case-study ZIPs on the same denominator. Raw counts remain available in
> the tooltip."

QA: switch through all seven parameter values. Every option should produce a
comparable City-versus-ZIP chart; none should show the old pooled-total
distortion.

---

### Worksheet 5 — Observed and forecast activity

**Purpose:** show observed monthly eligible sales and the primary 2026–2035
conditional forecast with 80% and 95% intervals.

Recommended build: a six-line interval plot. Tableau does not have a one-click
"shade between two dynamic lines" feature; the six-line version is the reliable
native build. Appendix A gives an optional polygon recipe if your rubric
requires filled bands.

The 80% and 95% values are **prediction intervals**, not observed sales. They
come from `fact_monthly_forecast[lower_80]`, `[upper_80]`, `[lower_95]`, and
`[upper_95]`. They widen with the forecast horizon and describe model
uncertainty, not causal scenarios or policy guarantees.

Long-horizon caveat: 19132's lower 95% bound crosses zero by the mid-2030s.
Monthly sales cannot be negative, so that lower bound is a statistical bound,
not a literal negative count. Either clamp the lower bound at zero for display
(`IF [lower_95] < 0 THEN 0 ELSE [lower_95] END`) and disclose the clamp, or keep
the raw bound and annotate that the 2035 interval is a long-range planning
range. The 3–5 year portion is the operationally credible part.

#### 5A. Six-line interval plot

Shelves:

| Shelf | Field |
|---|---|
| Columns | `month` (continuous exact date) |
| Rows | `Measure Values` |
| Color | `Measure Names` |
| Detail | `Measure Names`, `ZIP5 Clean` |
| Small Multiples | `ZIP5 Clean` (recommended) |

Measure Names filter — keep only:

- `Observed Sales`
- `Forecast Sales`
- `lower_80`
- `upper_80`
- `lower_95`
- `upper_95`

If the four interval fields do not appear in the Measure Names list, they were
probably inferred as **String dimensions** because the observed rows contain
`"NA"`. In `fact_monthly_forecast`, set `lower_80`, `upper_80`, `lower_95`,
and `upper_95` to **Number (Decimal)**, verify `"NA"` becomes Null, then
right-click each field in the Data pane and choose **Convert to Measure**.
Changing the data type alone does not move a field from Dimensions to Measures;
the Convert to Measure step is required. They should then appear in Measure
Names.

You can also drag each field directly onto the **Measure Values** card (not
onto the worksheet canvas) or use the Measure Values card menu > **Add**. That
adds the field to the Measure Values list. Dragging onto Rows or Columns creates
a separate axis instead.

If you cannot change the source type, create four cleaned measures:

```tableau
IF [lower_80] = "NA" THEN NULL ELSE FLOAT([lower_80]) END
IF [upper_80] = "NA" THEN NULL ELSE FLOAT([upper_80]) END
IF [lower_95] = "NA" THEN NULL ELSE FLOAT([lower_95]) END
IF [upper_95] = "NA" THEN NULL ELSE FLOAT([upper_95]) END
```

Use the cleaned measures in Measure Values.

Filters:

- `displayed_in_default_view = TRUE`
- `forecast_available = TRUE`
- `Selected ZIPs` (set) = In

Color mapping:

| Measure | Color |
|---|---|
| `Observed Sales` | Charcoal `#252525` |
| `Forecast Sales` | Orange `#D95F0E` |
| `lower_80` | Dark blue `#08519C` |
| `upper_80` | Dark blue `#08519C` |
| `lower_95` | Medium blue `#3182BD` |
| `upper_95` | Medium blue `#3182BD` |

Formatting:

- Mark: Line.
- Use small multiples by `ZIP5 Clean` so the two case-study ZIPs do not
  overlap. Each panel gets its own axis. If your Tableau version does not have
  Small Multiples, use a single-value `ZIP5 Clean` quick filter on this sheet
  and show one case ZIP at a time.

To put the two ZIPs in two panels on one sheet:

1. Keep `month` on Columns and `Measure Values` on Rows.
2. Drag `ZIP5 Clean` onto the **Small Multiples** shelf at the top of the
   worksheet, next to the Columns and Rows shelves. If you do not see that
   shelf, your Tableau version does not support Small Multiples.
3. Tableau creates one panel per ZIP, with a shared y-axis and one shared
   Measure Names legend.
4. Add the `2026-01-01` reference line with scope **Per Pane** so each panel
   gets its own line.
5. Small multiples share axis ranges by default. If you want each ZIP to have
   its own range, right-click the y-axis > **Edit Axis** and enable
   **Independent axis ranges for each row or column**. Keep the shared axis if
   the audience needs to compare levels; independent axes can exaggerate
   differences.

If your Tableau version lacks Small Multiples, duplicate the worksheet:
filter one copy to 19132 and the other to 19143, then place the two sheets side
by side in a horizontal dashboard container. That is the most reliable
two-panel fallback.
- Alias the Measure Names legend to `Observed`, `Forecast`, `80% lower`,
  `80% upper`, `95% lower`, and `95% upper`.
- Add a vertical reference line at `2026-01-01`, label `Forecast begins`.
  - Make `month` continuous exact date (green pill) on Columns.
  - Right-click the date axis > **Add Reference Line**.
  - Scope: **Per Pane** for small multiples, otherwise **Entire Table**.
  - Line: **Value**; enter `2026-01-01` or `#2026-01-01#`.
  - Label: **Custom** > `Forecast begins`; style dashed, charcoal.
- Axis title: `Eligible monthly sales`.
- y-axis: 0 decimals.
- Tooltip: ZIP, month, series type, monthly sales, lower/upper 80, lower/upper
  95, forecast specification.
- Title: `Observed and forecast eligible sales — case-study-only conditional baseline`.
- Caption: `Forecast is an Auto-ARIMA conditional baseline with pandemic and
  recording-backlog interventions. It is not a causal market forecast.`

Expected structure:

- Observed history: January 2015–December 2025 visible; 2010–2014 is present
  but hidden by `displayed_in_default_view`.
- Forecast: January 2026–December 2035, 120 months per case ZIP.
- 80% interval: `lower_80` to `upper_80`.
- 95% interval: `lower_95` to `upper_95`.

#### 5B. Non-case selection message

The forecast fact covers only 19132 and 19143. If the user selects another ZIP,
the forecast sheet is empty. Do not leave that as an unexplained blank chart.

Baseline solution: put a permanent text note in the forecast zone:

> `Forecast is built only for 19132 and 19143. A blank chart means the
> selected ZIP does not have a forecast; it does not mean zero sales.`

Optional dynamic message (Tableau 2022.3+):

1. Add `forecast_available` to the Detail shelf of the scatter.
2. Create a Boolean parameter `Forecast Exists`, default `True`.
3. Add a dashboard **Change Parameter** action from the scatter to
   `Forecast Exists`, using the source field `forecast_available`.
4. Create a small text sheet: `Forecast not built for this ZIP. Select 19132
   or 19143.`
5. Select the forecast zone > **Layout > Dynamic Zone Visibility**, condition
   `[Forecast Exists]`.
6. Select the message zone, condition `NOT [Forecast Exists]`.
7. Test by clicking 19132, 19143, and a non-case ZIP on the scatter.

If your Tableau version does not support dynamic zone visibility, keep the
permanent note. It is honest and does not mislead.

---

### Worksheet 6 — Evidence-to-response matrix and detail

**Purpose:** connect the observed evidence to a conditional City response
without turning the dashboard into a wall of text.

#### 6A. Response matrix

Shelves:

| Shelf | Field |
|---|---|
| Rows | `action_category` |
| Columns | `ZIP5 Clean` |
| Text | `priority` |
| Color | `priority` |
| Detail | `recommendation_status`, `priority_score` |

Filters:

- `Selected ZIPs` (set) = In
- `selectable_zip = TRUE`

Formatting:

- Mark: Square.
- Priority colors:
  - High: `#B2182B`
  - Medium: `#EF8A62`
  - Not assessed: `#BDBDBD`
- Sort action rows by `MIN([dashboard_order])` so case-study actions 1–4
  appear first and `Monitoring and deeper review` (99) appears last.
- Sort ZIP columns by `MIN([geography_sort])` so 19132 and 19143 are first.
- Action row order: Renter stabilization, Affordable-housing preservation,
  Homeowner stabilization, Development and market monitoring, Affordable-rental
  preservation, Permit-pipeline accountability, Targeted renter support,
  Market-access monitoring, Monitoring and deeper review.
- Tooltip: evidence trigger, proposed response, lead time, monitoring metric,
  claim boundary.

Default view: 8 action rows × 2 ZIP columns, with 4 populated action rows for
each case ZIP = 8 case-study cells. The ninth action, `Monitoring and deeper
review`, appears only when a non-case ZIP is selected; that ZIP's column shows
one `Not assessed` cell.

The blank cells are expected. The two case ZIPs have different action sets, so
19132 is blank in 19143's four action rows and vice versa. A blank means “no
case-specific recommendation was validated for this ZIP/action,” not “assessed
and rejected.” Do not label those blanks `Not assessed`; that label is reserved
for the monitoring-only row that non-case ZIPs actually have.

For a cleaner visual, create:

```tableau
// Priority Display
IFNULL([priority], "—")
```

and use it on Text. For Color, create:

```tableau
// Priority Color
IFNULL([priority], "No recommendation")
```

and assign `No recommendation` a light gray. Add a caption: `— = no
case-specific recommendation for this ZIP/action; not the same as “Not
assessed.”`

If you want no blanks at all, build two separate four-row matrices, one per
case ZIP, or use a bar chart of `priority_score` by action and ZIP. A single
matrix will always show the union of action categories and therefore some
blanks.

Q&A framing for a blank cell:

> “No recommendation” is a scope statement, not a judgment that the action is
> ineffective or that nothing should be done. It means the current ZIP-level
> evidence did not trigger a validated case-specific recommendation for that
> ZIP/action pair. The action may still be reasonable, but it would require a
> deeper review — building-level eviction data, parcel-level tax delinquency,
> permit completion and affordability data, or program eligibility analysis —
> before the City could claim it is evidence-triggered.

Use `Not assessed` only for the monitoring-only row that non-case ZIPs have.
Use `—` for the case-study ZIP/action combinations that were not triggered.

This orientation is optimized for the two case studies. If the user selects all
37 ZIPs, the matrix becomes very wide; use the response detail table or a
filtered single-ZIP view instead of trying to read 37 columns.

#### 6B. Response detail table

Shelves:

| Shelf | Field |
|---|---|
| Rows | `ZIP5 Clean`, `dashboard_order`, `action_category` |
| Text | `Response Card` |
| Detail | `priority`, `recommendation_status` |

Convert `dashboard_order` to a **Dimension** before placing it on Rows;
otherwise Tableau aggregates it and collapses the table to one row.

In Tableau terms, a **dimension** is a row-level label or grouping field; a
**measure** is a number Tableau aggregates. `dashboard_order` is an ordering
code (1–4, with 99 for monitoring), not a quantity to sum. Right-click the field
in the Data pane > **Convert to Dimension**, or right-click its pill after
placing it on Rows > **Convert to Dimension**. The pill should turn blue and the
table should show one row per action. You can hide the `dashboard_order` header
if you only want to use it for ordering.

Filters:

- `Selected ZIPs` (set) = In
- Optional action filter from the matrix (see section 8)

Formatting:

- Mark: Text.
- Font: 9 pt.
- Row height: 120–160 px.
- Fit: **Fit Width**.
- Turn on text wrapping if your Tableau version supports it.
- Color the `priority` field with a light background only if the text remains
  readable; otherwise leave the text table white.

If the `Response Card` is too dense, build the detail table with separate
columns instead: ZIP, Priority, Action, Evidence Trigger, Proposed Response,
Lead Time, Monitoring Metric, Claim Boundary. Use a small font and a wide
dashboard zone.

### Placing 6A and 6B on the dashboard

6A and 6B are **two separate worksheets**, not two pages of one sheet. Build
both, then place them in the same dashboard response zone:

- **Side-by-side:** 6A matrix on the left (about 40% width), 6B detail on the
  right (about 60%).
- **Stacked:** 6A matrix on top (about 40% height), 6B detail below (about 60%).

Then add the dashboard filter action from 6A to 6B:

- Source: `6A Response Matrix`
- Target: `6B Response Detail`
- Fields: `ZIP5 Clean`, `action_category`
- Run on: Select
- Clearing the selection: Show all values

If the response zone is too small for both, put 6A and 6B on a separate
dashboard tab named **Response detail**, with a navigation button from the main
dashboard. Do not try to squeeze a full text table into a 240 px zone; the
audience will not be able to read it.

---

## 7. Assemble the dashboard

Create a dashboard named **Philadelphia Housing Pressure: Context, Trajectory,
and Response**.

### 7.1 Size and background

- Dashboard > Size > **Custom**.
- Width: 1600 px.
- Height: 900 px.
- Background: white.
- Use layout containers; avoid floating every sheet.

### 7.2 Recommended layout

```text
+--------------------------------------------------------------------------------+
| TITLE: Philadelphia Housing Pressure: Context, Trajectory, and Response          |
| Subtitle: 37 qualifying ZIP/ZCTAs · case studies 19132 and 19143 · screening     |
| Selected ZIPs: [ set control ]                                                   |
+------------------------------------------+-------------------------------------+
| 1. All-ZIP context scatter               | 2. Case-study KPI comparison         |
| 37 points + median lines                 | rows = ZIP, columns = measures       |
+------------------------------------------+-------------------------------------+
| 3. Evidence percentile profile           | 4. Annual signal trend               |
| 6 percentile rows, 2 dots each           | parameter-controlled measure         |
+------------------------------------------+-------------------------------------+
| 5. Observed + forecast activity          | 6. Evidence-to-response              |
| case-study-only, 80/95 intervals         | matrix + detail                      |
+------------------------------------------+-------------------------------------+
| LIMITATIONS FOOTER                                                               |
+--------------------------------------------------------------------------------+
```

Approximate zone sizes for a 1600×900 canvas:

| Zone | Width | Height |
|---|---:|---:|
| Header | 1600 | 75 |
| Scatter | 960 | 250 |
| KPI table | 620 | 250 |
| Evidence profile | 620 | 240 |
| Annual trend | 960 | 240 |
| Forecast | 980 | 240 |
| Response matrix/detail | 600 | 240 |
| Footer | 1600 | 70 |

How to resize the zones:

1. Set **Dashboard > Size > Custom** to 1600×900 first. If the dashboard is
   `Automatic`, the zones reflow with the window and are hard to control.
2. Use **tiled containers** (horizontal/vertical), not floating zones.
3. Hover over the border between two zones until the cursor becomes a
   double-headed arrow, then drag the divider.
4. Select a zone or container, open the **Layout** pane, and set **Width**,
   **Height**, **X**, and **Y** explicitly. This is the precise method.
5. For equal sections, select the parent container and use **Distribute
   Evenly**.
6. For each worksheet zone, set **Fit** to `Entire View` (charts) or
   `Fit Width` (text tables). A zone cannot be smaller than the sheet's
   minimum size if the sheet is set to `Standard`.
7. If a divider will not move, you are probably selecting the wrong container;
   select the parent container in the Layout pane's item hierarchy.

### 7.3 Header content

Title: `Philadelphia Housing Pressure: Context, Trajectory, and Response`

Subtitle: `37 qualifying ZIP/ZCTAs · detailed case studies 19132 and 19143 ·
descriptive screening, not proof of displacement`

Add the `Selected ZIPs` set control at right. Add a one-line instruction:
`Use the ZIP set to change the cohort; the scatter keeps all 37 points visible.`

### 7.4 Footer content

Use a text object, not a worksheet. Keep it permanent:

- ACS five-year estimates carry sampling error and margins of error.
- ZIP/ZCTA is an approximation of the Census ZIP Code Tabulation Area.
- Redfin and RTT use different property and sale definitions.
- Eviction filings are court cases, not unique households or completed
  evictions.
- Permits are applications, not completed units or affordable units.
- The forecast is a conditional historical baseline with 80%/95% intervals,
  not a causal market or displacement forecast.
- The validated forecast and case-specific recommendations exist only for
  19132 and 19143. Other ZIPs show forecast unavailable and monitoring-only
  response status; they are not all-ZIP predictions or recommendations.

Add: `Sources: RTT/OPA deed records, Redfin, ACS 5-year estimates, L&I permit
records, and eviction filings. See the Week 6 data dictionary and ingestion
README.`

### 7.5 Scope statement

Put a short scope statement in the header or directly under the title:

> **All 37 qualifying ZIPs:** context, annual signals, evidence percentiles,
> and monitoring status. **Validated forecast and case-specific responses:**
> 19132 and 19143 only. Other ZIPs are monitoring-only; they are not missing
> data, and they are not case-validated.

This prevents the audience from reading the dashboard as an all-ZIP
prediction or recommendation system. The two case studies are a deliberate
evidence tier, not a filter accident.

---

## 8. Add interactivity

### 8.1 Set control

- Show the `Selected ZIPs` set control.
- Set it to multiple values.
- Default selection: 19132 and 19143.
- Save the workbook in that state.

The set control is the single cohort selector. Do not replace it with an
ordinary ZIP quick filter; an ordinary filter would remove the other 35 points
from the context scatter.

### 8.2 Scatter highlight action

1. Dashboard > **Actions > Add Action > Highlight**.
2. Name: `Highlight ZIP from context`.
3. Source: Worksheet 1, the scatter.
4. Target: all sheets except the scatter.
5. Selected fields: `ZIP5 Clean`.
6. Run on: Hover or Select.
7. Leave the scatter unfiltered.
8. Every target sheet must have `ZIP5 Clean` on Detail, Color, Rows, or
   Columns for the highlight to match. The annual sheet needs `ZIP5 Clean`
   added to Detail; the other sheets already have it.

This lets a user inspect a point without collapsing the 37-ZIP distribution.

### 8.3 Response matrix filter action

1. Dashboard > **Actions > Add Action > Filter**.
2. Name: `Show selected response detail`.
3. Source: Worksheet 6A, the response matrix.
4. Target: Worksheet 6B, the response detail table.
5. Selected fields: `ZIP5 Clean`, `action_category`.
6. Run on: Select.
7. Clearing the selection: **Show all values**.

Do not use the generic **Use as Filter** option; it passes every field and can
produce unexpected filter combinations.

### 8.4 Reset behavior

Tableau sets are workbook-level, and a normal "Reset Filter" button does not
reset a set. Two dashboard tabs that share the same set also share the same set
selection, so duplicating a tab does not create two independent default states.

Use one of these approaches:

- **Saved custom view (preferred on Tableau Server/Cloud):** save one view with
  19132 and 19143 selected and another with all 37 selected. Add navigation
  buttons or links to those views.
- **Desktop-only default state:** save the workbook with 19132 and 19143
  selected, and put a small instruction next to the set control:
  `Default: 19132 + 19143. Use All, then reselect the two case ZIPs to reset.`
- **Advanced set-action reset:** create a small "Reset" sheet with two marks,
  19132 and 19143, and a set action that assigns `ZIP5 Clean` to
  `Selected ZIPs`. The user selects both marks to reset. This is more work than
  it is worth for most class dashboards.

Do not fake a reset with a filter that hides the other 35 points; that breaks
the context scatter and the "all qualifying ZIPs" comparison.

---

## 9. Color, typography, and formatting

Use the project palette everywhere:

| Element | Color |
|---|---|
| 19132 | Orange `#D95F0E` |
| 19143 | Dark blue `#08519C` |
| Philadelphia benchmark | Charcoal `#252525` |
| Other qualifying ZIPs | Gray `#7F7F7F` |
| Light comparison points | Light gray `#BDBDBD` |
| 80% interval | Dark blue `#08519C` |
| 95% interval | Medium blue `#3182BD` |
| High priority | `#B2182B` |
| Medium priority | `#EF8A62` |
| No assessment | `#BDBDBD` |

Typography:

- Title: 18–20 pt bold.
- Subtitle: 10–11 pt gray.
- Worksheet titles: 11–12 pt bold.
- Axis labels: 9–10 pt.
- Tooltips: 9–10 pt.
- Footer: 8 pt gray.
- Use the same font family across Tableau, R, and PowerPoint if possible.

Number formats:

- Currency: `$#,##0`.
- Percent: `0.0%` for rates and growth; `0%` for percentiles.
- Price-to-income: `0.00"x"`.
- Counts: `#,##0`.
- Filing rate: `0.0`.
- Days: `0`.

---

## 10. QA checklist before saving

### Data model

- [ ] Only the five ingestion CSVs are connected.
- [ ] `dim_geography` is the root table.
- [ ] Each fact relates directly to `dim_geography` on `geography_key`.
- [ ] No fact-to-fact relationship exists.
- [ ] No physical join exists.
- [ ] `dim_geography` has 38 distinct `geography_key` values.
- [ ] `fact_zip_profile` has 38 rows at one row per key.
- [ ] `fact_annual_signals` has 456 rows and a unique key + year.
- [ ] `fact_monthly_forecast` has 624 rows and a unique key + month + series.
- [ ] `fact_policy_response` has 43 rows and a unique `recommendation_key`.
- [ ] No fact has an orphan `geography_key`.

### Selection behavior

- [ ] Workbook opens with 19132 and 19143 selected.
- [ ] Scatter always shows 37 ZIP points, even when the set changes.
- [ ] Scatter median reference lines stay at the all-37 medians.
- [ ] Annual sheet keeps the City benchmark visible.
- [ ] KPI and evidence sheets show only selected ZIPs, never the City row.
- [ ] Forecast sheet shows only case-study ZIPs; non-case selections show the
      availability note.
- [ ] Policy matrix shows monitoring-only for non-case ZIPs.

### Values

- [ ] 19132: 17.0% CAGR, 73.9% vulnerability, -33.2% transaction change,
      2.44x price-to-income, 55.2 filing rate, 191 permitted units.
- [ ] 19143: 11.2% CAGR, 63.6% vulnerability, -13.9% transaction change,
      3.94x price-to-income, 34.7 filing rate, 201 permitted units.
- [ ] City pooled 2025 eviction filing rate: 40.2.
- [ ] 19132 is the fastest price-growth ZIP in the qualifying set.
- [ ] 19143 has the higher price-to-income ratio but the lower filing rate.
- [ ] No number on the dashboard contradicts the exported CSVs.

### Presentation

- [ ] Colors match the fixed palette.
- [ ] Every axis has a title and units.
- [ ] Every sheet states its grain or filter where needed.
- [ ] The forecast is labeled `case-study-only conditional baseline`.
- [ ] The limitations footer is visible without scrolling.
- [ ] Tooltips include definitions, MOE caution, and claim boundaries.
- [ ] The dashboard does not describe the analysis as proof of gentrification
      or displacement.

---

## 11. Common Tableau gotchas in this package

1. **`zip5` becomes a number.** Fix the data type to String and set geographic
   role to None. Otherwise ZIP `19132` may display as `19,132` or gain a map
   role.
2. **`"NA"` becomes a text member.** Create `ZIP5 Clean` and verify numeric
   nulls. If a numeric field remains text, use a `FLOAT()` cleanup calculation.
3. **Tableau auto-relates two facts.** Delete the fact-to-fact line and relate
   each fact to `dim_geography`.
4. **A worksheet mixes two facts.** Keep one fact per sheet. If you need
   profile and annual measures together, build two sheets and place them side
   by side.
5. **The set filters the scatter.** Do not put `Selected ZIPs` on the scatter's
   Filter shelf. Use it on Color/Size only.
6. **The City benchmark disappears from annual sheets.** Use
   `Annual ZIP Filter`, not the set alone.
7. **The City row appears in KPI/evidence sheets.** Add
   `selectable_zip = TRUE`.
8. **Forecast chart is blank for a non-case ZIP.** Add the availability note;
   the fact has no rows for that ZIP.
9. **`Measure Names` shows unrelated measures.** Filter `Measure Names` to the
   exact measures for that sheet. Do not leave annual or monthly measures in a
   profile sheet.
10. **Dashboard opens with the wrong set state.** Tableau does not read the
    CSV's `default_dashboard_selection` flag. Select 19132 and 19143 manually
    and save.

---

## 12. Post-review addendum — second dashboard and the map selector

Added after the Week 6 review. Two pieces of feedback drove this section:

1. Worksheets 5 and 6 should live on their own dashboard. Multiple dashboards
   in one workbook are allowed, and all of them publish together under one
   Tableau Public link.
2. The ZIP should be picked from a map, not from a list.

Do these in the order below. Both changes are safe to abandon halfway: the
`Selected ZIPs` set remains the real selector in every design, so if a step
misbehaves, delete the new zone and nothing else breaks.

### 12.1 What the workbook already contains

Check the tab bar at the bottom before building anything:

| Object | Type | Sheets it holds |
|---|---|---|
| `Philadelphia Housing Pressure: Context, Trajectory, and Response.` | Dashboard | 01, 02, 03, 04, 05, 06 |
| `Philadelphia Housing Pressure: Context, Trajectory, and Response (2)` | Dashboard | 05, 06 |
| `07 Response Detail` | Worksheet | nothing — currently orphaned |

So the second dashboard exists but is unfinished: it has no title, no footer,
no filter action from 06 to 07, and its natural third panel (`07 Response
Detail`) is not on it. Dashboard A still carries 05 and 06, so the same two
charts appear twice.

Also note the canvas: both dashboards are **2000 × 1200 fixed**, not the
1600 × 900 in section 7. Use the coordinates below against 2000 × 1200.

### 12.2 Finish dashboard B (forecast + response)

Rename it first, or the published tab labels will read like file copies.

1. Right-click the `(2)` tab at the bottom → **Rename Sheet** →
   `Forecast and Response`.
2. Open it and lay out three zones:

   | Zone | Width | Height | Content |
   |---|---:|---:|---|
   | Header | 2000 | 110 | Title + subtitle text object |
   | Forecast | 2000 | 470 | `05 Observed and forecast activity` |
   | Response matrix | 700 | 560 | `06 Evidence-to-response` |
   | Response detail | 1280 | 560 | `07 Response Detail` |
   | Footer | 2000 | 60 | Scope note |

3. Header text object:
   `Forecast and Response — 19132 and 19143`
   Subtitle: `Conditional historical baseline with 80%/95% intervals · validated
   for the two case-study ZIPs only · recommendations are conditional City
   actions, not program impact`
4. Footer text object:
   `Forecast intervals describe model uncertainty, not causal scenarios. Lower
   95% bounds below zero are statistical bounds, not negative sales. Response
   rows are conditional recommendations, not evaluated program effects.`
5. Add the response drill-down on **this** dashboard. Actions are
   dashboard-scoped, so the copy on dashboard A does not travel:
   Dashboard → **Actions → Add Action → Filter**, name
   `Show selected response detail`, source `06 Evidence-to-response`,
   target `07 Response Detail`, fields `ZIP5 Clean` and `action_category`,
   run on **Select**, clearing the selection **Show all values**.
6. Add the scatter highlight action here too if you want hover feedback from
   the forecast sheet's marks; otherwise skip it. The forecast and response
   sheets do not share a row grain, so the highlight adds little.
7. Add navigation buttons: Dashboard → **Objects → Button**, one to
   `Philadelphia Housing Pressure: Context, Trajectory, and Response.` labelled
   `← Context`, one on dashboard A labelled `Forecast & Response →`. Without
   buttons, viewers only see the small tabs at the bottom of the public viz and
   most will never find the second page.
8. Set each sheet zone's **Fit** to `Entire View`. `07 Response Detail` is a
   text table; if its rows spill, set it to `Fit Width` and accept vertical
   scroll rather than shrinking the fonts below 9 pt.

#### 12.2.1 Verifying the response drill-down

`07 Response Detail` carries **no filters of its own**, so before you click
anything it prints every row: one row per `zip5` × `action_category`
combination, 43 rows in total. That is your baseline. Make the change visible
before you conclude the action is broken:

1. Set the `07 Response Detail` zone to `Fit → Fit Width`, not `Entire View`.
   With `Entire View` all 43 rows compress into the zone, and a jump from 43
   rows to 1 is easy to miss inside 1280 px of white space.
2. Note the row count, then click one cell in `06 Evidence-to-response`.
3. The detail table should collapse to exactly **one** row — that ZIP, that
   action category — and clearing the selection should restore all 43.

Three config errors account for every "clicking does nothing" on this action:

- **The action was written to a different dashboard.** Tableau attaches a new
  action to whichever dashboard tab is active, not to the one you are looking
  at in a second window. Verify with Dashboard → **Actions**: the dialog lists
  the actions for the current tab only. Switch tabs and look again — if
  `Show selected response detail` is missing from `Forecast and Response` and
  present on the context page, it landed on the wrong tab. Rebuild it with
  `Forecast and Response` open.
- **You are clicking `06` on page 1.** Until the 05 and 06 zones are deleted
  from the context dashboard (12.2 item 9), page 1 still shows the same matrix
  with no action attached, and clicking it there does nothing. Delete those two
  zones first, or test only on page 2.
- **Target Sheets was left as "All Using This Data Source" or is unticked for
  `07 Response Detail`.** Set it to the single sheet.

Also check the action's enabled checkbox in that same dialog, and that
`Run action on` is `Select` rather than `Menu`.

Then clean up dashboard A:

9. On dashboard A, select the 05 zone and the 06 zone and delete both. Leaving
   them duplicates the second page and breaks the "one page, one question"
   structure the reviewer asked for.
10. Re-flow the remaining four panels to the 2000 × 1200 canvas:

    | Zone | Width | Height |
    |---|---:|---:|
    | Header + map band | 2000 | 270 |
    | Scatter | 1280 | 450 |
    | KPI table | 720 | 450 |
    | Evidence profile | 720 | 420 |
    | Annual trend | 1280 | 420 |
    | Footer | 2000 | 60 |

    The header band is 270 tall because the map selector from 12.3 goes there.

11. Update the tabs' left-to-right order so the context dashboard is leftmost:
    drag the tabs at the bottom. Tableau Public opens the leftmost tab by
    default.

**Behavior to expect and to state out loud:** the `Select Annual Measure`
parameter and the `Selected ZIPs` set are workbook-level, not dashboard-level.
Changing the measure on dashboard A changes it on dashboard B, and a ZIP picked
on the map carries to every sheet on both pages. That is the desired behavior —
it is one model with two views — but say so, because a viewer who changes the
measure on page 2 and finds page 1 changed will otherwise think it is a bug.

### 12.3 Replace the ZIP list with a geometry map

The map is a **fifth worksheet that acts as a control**, not a chart. It writes
into `Selected ZIPs` through a set action. No shapefile is needed: Tableau ships
ZIP/ZCTA polygons, and `zip5` is already a five-digit string.

**Build the map sheet**

1. Right-click `ZIP5 Clean` in the Data pane → **Geographic Role → ZIP Code**.
   Do this on `ZIP5 Clean`, not on raw `zip5`; `ZIP5 Clean` nulls out the `"NA"`
   member so the City row cannot create a phantom polygon.
2. New worksheet, name it `00 ZIP Map Selector`.
3. Double-click `ZIP5 Clean`. Tableau draws a symbol map and adds the field to
   Detail with the ZIP geographic role.
4. Change the Marks card type to **Map** (filled polygons).
5. Drag `ZIP Color Group` to **Color**. It already resolves to
   `#D95F0E` for 19132, `#08519C` for 19143, gray for other qualifying ZIPs, so
   the map matches the rest of the workbook with no new calculation.
6. Filters: `selectable_zip = TRUE` and `ZIP5 Clean` is not null. The City row
   has no ZIP and must not appear.
7. Tooltip: `ZIP5 Clean`, `case_group`, and the line
   `Click to add or remove this ZIP from the cohort`. Remove the default
   measure tooltip entries — a filled map drawn from a single dimension has
   nothing meaningful to show there.
8. Map → **Background Maps → Tableau → Light**. The default streets basemap
   puts highway shields and neighborhood names on top of the polygons and makes
   620 px of Northeast Philadelphia unreadable.
9. Map → **Map Layers**: turn off every layer except the ZIP polygon boundaries.
   Uncheck labels, roads, and points of interest.
10. Zoom and pan so the 37 qualifying ZCTAs fill the frame. Tableau persists
    the zoom with the sheet, so this is a one-time step; re-check it after any
    resize of the zone.
11. Turn off the sheet title on the dashboard zone (zone menu → **Title →
    Hide**) and instead put a text object directly above the map:
    `Select ZIPs — click to add or remove`.

**Wire the map to the set**

12. Right-click the dashboard → **Actions → Add Action → Change Set Values**.
13. Name: `Pick ZIPs from map`.
14. Source Sheets: only `00 ZIP Map Selector`.
15. Target Set: `Selected ZIPs`.
16. Run action on: **Select**.
17. Clearing the selection will: **Keep set values**.

    This is the setting that makes it a cohort picker instead of a
    single-select. With `Keep set values`, each click adds a ZIP and the set
    accumulates, so a viewer can click 19132, then 19143, and see both. The
    alternative, `Remove all values from the set`, resets the cohort to whichever
    single ZIP was last clicked and defeats the two-ZIP comparison.

18. Keep the `Selected ZIPs` set control on the dashboard, but shrink it to a
    narrow strip under the map and retitle it `Current cohort`. Clearing a set
    action cannot be done by clicking, so the set control stays as the readout
    and the escape hatch: uncheck a member there to drop that ZIP.

**Where it goes**

19. Place the map in the right-hand 620 px of the 270 px header band, with the
    title, subtitle, and scope statement in the left-hand 1380 px.
20. Set the zone to `Fit → Entire View`.

**Known limits to disclose, not hide**

- Tableau's built-in ZIP geometry is a ZCTA approximation, not a postal
  boundary. Say "ZCTA" in the caption if a viewer asks about a boundary that
  looks wrong.
- The map shows the 37 qualifying ZCTAs. The white space inside the city is
  ZCTAs excluded by the qualification screen, not missing data. Put that in the
  caption: `37 qualifying ZCTAs; unshaded areas were excluded by the
  qualification screen, not missing values.`
- ZCTAs are drawn at full extent, so a large low-density ZCTA occupies more ink
  than a small dense one. The map is a selector, not an areal rate map; do not
  let anyone read it as "more orange area means more pressure."

#### 12.3.4 Set action created with "Remove" instead of "Add"

The first build of `Pick ZIPs from map` was saved with:

```xml
<add-or-remove-marks value='remove' />
```

That is the dialog's **"Running the action will: Remove values from the set"**
option. The visible symptom is the opposite of "nothing happens": every click
*deletes* the clicked ZIP from `Selected ZIPs`, so clicking anywhere on a map
whose default cohort is 19132 + 19143 strips those two out of the KPI table,
the profile, and the annual chart. It reads as "clicking does nothing" because
the map keeps rendering all 37 polygons either way.

Correct value is `add`. Together with
`selection-clear-set-option = do-nothing` ("Keep set values"), clicks then
accumulate. Removal is done by unchecking a member in the cohort control; a set
action cannot toggle membership from a plain click.

#### 12.3.5 `ZCTA Area` — naming the regions

Feedback: nobody knows which part of the city a ZCTA is. A `ZCTA Area`
calculated field now lives in the data source and is on the map's tooltip,
returning strings such as `Kingsessing / Cedar Park - Southwest`.

Two things it deliberately does **not** do:

- It does not concatenate the name into `ZIP5 Clean`. That field carries the
  `[ZipCode].[Name]` geographic role; appending text stops Tableau from
  geocoding it and the filled map goes blank.
- It does not add a column to `dim_geography.csv`. That would require rebuilding
  the `.hyper` extract and republishing. A calculated field computes on the
  existing extract, so no refresh is needed.

**Formulas must reference `[Calculation_0204296021520385]`, not `[ZIP5 Clean]`.** `ZIP5 Clean` is only the caption of that calculated field; its internal column name is the `Calculation_...` key. A formula written with the caption opens, validates, and looks correct in the calculation editor, then renders **red** on the sheet because the engine cannot resolve it - and a red field stops the map from drawing. Every stored formula in this workbook uses the internal name; match it.

The names are conventional Philadelphia neighbourhood/ZIP associations, not
official boundaries — describe them as approximate area labels.

#### 12.3.3 Root cause of "Missing field on 00 ZIP Map Selector"

Checked directly in the saved workbook. The set and the sheet disagree about
which field identifies a ZIP:

| Object | Field it uses |
|---|---|
| `Selected ZIPs` set | **`zip5`** (raw string) |
| `00 ZIP Map Selector` | `ZIP5 Clean` (calculated), **no raw `zip5` anywhere on the sheet** |
| `01 Zip Context` | raw `zip5` on both Tooltip (`ATTR(zip5)`) and Detail |

A **Change Set Values** action works by taking the field the set is built on,
from the source sheet, and writing those members into the set. If the source
sheet never places that field in the view, Tableau has nothing to read and
reports `Missing field on 00 ZIP Map Selector` in the Edit Set Action dialog.
That is why the highlight action on the scatter works — the scatter carries
`zip5` — and the map action does not.

**Fix:** on `00 ZIP Map Selector`, drag **`Zip5`** (the raw field under
`dim_geography.csv`, *not* `ZIP5 Clean`) onto the **Detail** card. One extra
pill, no change to the marks, the colours, or the 37 polygons. Reopen the set
action and the warning is gone.

Do not "fix" this by recreating the set on `ZIP5 Clean`: the set is referenced
by name in `ZIP Color Group`, `ZIP Point Size`, `Scatter Label`,
`Annual ZIP Filter`, and the filters on sheets 02, 03, 05, 06 and 07. Adding one
pill to one sheet is the whole change.

**Also worth cleaning:** the data source carries an unused calculated field
`NA issue` (`IF [median_household_income] = "NA" THEN NULL ELSE
FLOAT([median_household_income]) END`) which shows a red `!` in the Data pane
because it references a table-qualified field that no longer resolves. Nothing
uses it — no worksheet references it. Delete it to clear the badge.

#### 12.3.2 Which sheets the map can actually move

The map does not filter anything directly. It writes membership into the
`Selected ZIPs` set, and each worksheet reacts only because it already carries
that set. Verified against the saved workbook:

| Worksheet | Filter on the sheet | Reacts to a map click? |
|---|---|---|
| `01 Zip Context` | `selectable_zip = TRUE` only | **No, by design** — always 37 points |
| `02 KPI Evidence` | `Selected ZIPs` set | Yes |
| `03 Selected ZIP Evidence Profile` | `Selected ZIPs` set | Yes |
| `04 Annual Signals` | `Annual ZIP Filter` (references the set) | Yes |
| `05 Observed and forecast activity` | set + `displayed_in_default_view` + `forecast_available` | **Only for the two case ZIPs**; any other ZIP falls through to the availability note |
| `06 Evidence-to-response` | `Selected ZIPs` set | Yes, gains that ZIP's monitoring row |
| `07 Response Detail` | `Selected ZIPs` set | Yes, gains that ZIP's detail rows |

Two consequences worth stating before anyone calls it broken:

- If you are staring at `01` or `05` while clicking, nothing will happen and
  nothing should. The scatter is the all-37 context view, and the forecast is
  validated for 19132 and 19143 only.
- Because `05` filters on `forecast_available`, a third ZIP selected on the map
  replaces the forecast with the availability message rather than drawing an
  empty chart. That is the intended fallback, not a failure.

The action must be **Change Set Values**, not Filter. A filter action cannot
write to a set; it can only add its own filter on top, and because `02`, `03`,
and `04` already filter by the set, the result is an intersection that is usually
empty.

#### 12.3.1 If the map action appears to do nothing

Set actions have no effect on open or on hover-by-default; they fire only when a
mark is *selected*, and only on the dashboard, never on the worksheet tab.

Check these in order. Each one is cheap, and #1 explains the majority of
"nothing happened" reports.

1. **You clicked a ZIP that is already in the set.** The default cohort is
   19132 + 19143, and `Keep set values` only ever *adds*. Clicking 19132 or
   19143 is a no-op, because both are already members, and the chart you are
   watching is already showing them. Test with a **gray** ZCTA, for example
   19142. If the KPI, profile, and annual sheets then show three ZIPs, the
   action works and there was never a problem.
2. **Make membership visible.** A set action that fires can still look like
   nothing happened if nothing on screen is keyed to the set. `ZIP Color Group`
   has hard-coded branches for 19132 and 19143 *before* it tests `[Selected
   ZIPs]`, so those two polygons never change colour. On the map, drag this to
   **Label**:
   `IF [Selected ZIPs] THEN [ZIP5 Clean] END`
   A selected ZCTA now prints its own ZIP number. Click a gray polygon and the
   number appears — unambiguous proof the action reached the set.
3. **Confirm the set itself changed.** Keep the `Selected ZIPs` control on the
   dashboard while you test. If the checkbox in the control does not flip, the
   action is not reaching the set. If it flips but the sheets do not move, the
   problem is downstream in the sheets, not in the action.
4. **You are on the other dashboard.** Dashboard actions are scoped to one
   dashboard. The Actions dialog always belongs to whichever dashboard is
   currently open. An action built on `Forecast and Response` does nothing on
   the context page, and vice versa. Open the right dashboard, then check.
5. **Run action on is set to Menu.** `Menu` only fires from the little
   tooltip/mark menu, never from a plain click. Set it to `Select` while
   debugging; switch back only if you deliberately want right-click behaviour.
   As a temporary diagnostic, set it to `Hover` — if the sheets respond to
   mouse movement, the configuration is correct and only the click is landing
   in the wrong place.
6. **Source Sheets does not include the map.** Open
   Dashboard → Actions → select the action and read the Source list. If the
   `00 ZIP Map Selector` box is unticked, or the list contains a different
   sheet, the action is watching the wrong thing. A very common cause: the
   sheet was renamed after the action was created.
7. **The zone on the dashboard is showing a different sheet.** Check the zone's
   title, not the tab you have open. If the map zone still shows `01 Zip
   Context` (both are maps of the same ZIPs at a glance), you are clicking
   points from the scatter, whose action is *highlight*, not *set*.
8. **You are clicking the zone, not a mark.** In dashboard edit mode a click on
   the zone border or on empty ocean selects the zone, not the polygon. Turn on
   **Presentation mode** (or just click well inside a polygon) and try again.
9. **A hard filter is blocking the add.** If a sheet has `ZIP5 Clean` on the
   Filters shelf as an ordinary filter, the set action cannot add a ZIP that
   the filter excludes. The only ZIP-level filter these sheets should carry is
   the `Selected ZIPs` set itself, plus `selectable_zip = TRUE`.
10. **The set belongs to another data source.** The Target Set dropdown only
    lists sets from the source the sheet is built on. If `00 ZIP Map Selector`
    was built from a second copy of the CSVs, `Selected ZIPs` will not appear,
    or the action will silently do nothing. Rebuild the map on the same
    `dim_geography`-rooted source as the other sheets.

A two-question bisection that settles it every time:

- Untick 19143 in the `Selected ZIPs` control by hand. If the KPI, profile, and
  annual sheets do not change, the problem was never the action — it is in the
  sheets.
- If they do change by hand but not on click, the problem is the action
  configuration, and items 4–7 above are the whole list.

### 12.4 Publish both pages

1. Data → **Extract Data** on the data source. Tableau Public rejects a live
   connection to local CSVs, which is the error you already hit
   (`does not permit external database connections`).
2. Server → **Tableau Public → Save to Tableau Public**.
3. Tab order becomes the published tab order; the leftmost tab is what loads
   first. Confirm `Philadelphia Housing Pressure: Context, Trajectory, and
   Response.` is leftmost.
4. Open the published link in a private window and check, in this order:
   - page 1 loads on the context dashboard,
   - clicking a ZCTA adds it to the cohort rather than replacing it,
   - `Current cohort` matches the map colours,
   - forecast and response buttons navigate,
   - a non-case ZIP shows the forecast-availability note instead of an empty
     chart,
   - the 06 → 07 filter action works on page 2.

### 12.5 Do not do these

- Do not swap the set for a ZIP quick filter. It removes the other 35 points
  from the context scatter and destroys the all-37 comparison.
- Do not delete the `Selected ZIPs` set control. The map action cannot clear a
  set, so without the control there is no way to remove a ZIP.
- Do not put the City benchmark on the map. It has no ZIP and will either
  vanish or geocode to a nonsense location.
- Do not attempt a filled choropleth of a **measure** on this sheet. One sheet,
  one job: this one selects, it does not report.

### 12.6 If the reviewer wants a real geography view of the measures

That is a different request and a different sheet: a filled map coloured by
`price_to_income_2024` or `vulnerability_percentile`, with `ZIP5 Clean` on
Detail and the measure on Color. Build it as `08 ZIP Measure Map` and give it
its own tab, keeping the quadrant scatter intact. Replacing the scatter would
lose the two axes and the City benchmark, which is the piece the reviewer has
not asked you to drop.

---

## Appendix A — Optional filled forecast bands

The six-line interval plot is the reliable native build. If a rubric explicitly
requires filled 80%/95% bands, use a polygon. This is advanced and should be
built as a separate "Forecast band" data source so it does not disturb the
production model.

1. Connect `fact_monthly_forecast.csv` again in a new data source.
2. In the physical layer, union the table with itself. Tableau adds
   `[Table Name]`. The two values are usually `fact_monthly_forecast` and
   `fact_monthly_forecast1`; use the actual values shown in the data pane.
3. Create `[Band Edge]`:
   ```tableau
   IF [Table Name] = "fact_monthly_forecast" THEN "Upper" ELSE "Lower" END
   ```
4. Create `[Band Value]` for the 95% band:
   ```tableau
   IF [Band Edge] = "Upper" THEN [upper_95] ELSE [lower_95] END
   ```
5. Create `[Band Path]`:
   ```tableau
   IF [Band Edge] = "Upper"
   THEN DATEDIFF("month", #2010-01-01#, [month])
   ELSE 10000 - DATEDIFF("month", #2010-01-01#, [month])
   END
   ```
6. Filter `[series_type] = "Forecast"`, `[displayed_in_default_view] = TRUE`,
   and the case ZIP.
7. Build the polygon sheet:
   - Columns: `[month]` continuous.
   - Rows: `[Band Value]`.
   - Path: `[Band Path]`.
   - Detail: `[Band Edge]`, `[ZIP5 Clean]`.
   - Mark: Polygon.
   - Color: light blue `#3182BD`, opacity 30–40%.
8. Duplicate the sheet for the 80% band using `lower_80` and `upper_80`, with a
   darker blue `#08519C`.
9. Overlay the two polygon sheets behind the six-line sheet in the same
   dashboard zone. Use transparent sheet backgrounds and verify that the axes
   align exactly.
10. Test both case ZIPs and confirm that the polygon closes at the first and
    last forecast month.

If the overlay is unstable, keep the six-line interval plot. A clear line
chart with labeled 80%/95% bounds is more honest than a broken polygon.

---

## Appendix B — Where the build is documented in the repo

| Topic | File |
|---|---|
| Package specification, relationship model, filter behavior, colors | `tableau_data/tableau_ingestion/README.md` |
| Field definitions, forecast methods, worksheet plan, recommendation boundaries | `docs/WEEK_06_DATA_DICTIONARY_AND_DASHBOARD_GUIDE.md` |
| Research design and dashboard wireframe | `docs/WEEK_04_05_06_ANALYSIS_STEPS.md`, section 6 |
| R export of the five CSVs | `R/week06_dashboard_exports.R` |
| Reproducible runner and audit checks | `R/week06_run_all.R` |
| Final relationship audit | `tableau_data/week06_final_package_audit.csv` |
| Pre-Week 6 archived five-chart package (not production) | `tableau_data/archive_pre_week06_ingestion/` |

The archived `BSAN710Pro.twb` is the previous five-chart workbook, not the
final Week 6 dashboard. Do not connect it to the final ingestion folder.
