# Week 03 Proposed Analysis Steps and Client Meeting Plan

**Project:** Philadelphia Property Transactions and Mortgage Activity  
**Prepared for:** Week 03 progress discussion and client meeting  
**Source expectation:** `Week 03 Expected Progress.pptx`  
**Current analytical source:** [`R/BSAN_Proj.R`](../R/BSAN_Proj.R),
[`R/core_visualizations.R`](../R/core_visualizations.R), and the version 6 team
datasets  
**Analysis period:** January 2000 through July 2026

## 1. What Week 03 expects

The Week 03 guidance asks the team to pause after cleaning and establish the
analytical direction before treating later models as final. The expected work
has four parts:

1. Continue exploratory analysis through descriptive statistics, missing-data
   and outlier review, transformations, correlations, crosstabs, and
   variable-level visualizations.
2. Finalize two or three focus areas within the main research question.
3. Create a detailed plan for each focus area, including tools, methods,
   collaboration needs, and analytical outputs.
4. Begin the visualizations that will become part of the final dashboards.

The project has already built forecasting, regression, clustering,
optimization, and Tableau exports. For Week 03, these should be treated as
prototypes and evidence about what is feasible. The team should use the EDA and
client discussion to confirm which components belong in the final deliverable.

Two potential final-project directions are now documented in
[`FINAL_RESEARCH_PATHWAYS.md`](FINAL_RESEARCH_PATHWAYS.md): an
activity-forecasting and audit-allocation pathway, and a higher-data-burden
housing-pressure and displacement-risk mapping pathway. These are alternatives
for group discussion, not two additional workstreams that have already been
approved.

## 2. Recommended main research question

> How have Philadelphia property-market activity and typical single-property
> prices changed since 2000, which five ZIP codes have followed a similar
> price-growth path, and what does the overlapping ZIP-level evidence indicate
> about price relative to household income?

This wording keeps the work within one Philadelphia housing-market research
area while allowing the five agreed charts to move from citywide conditions to
ZIP growth and affordability.

### Current construction status

- `tableau_data/tableau_ingestion/viz1_citywide_activity.csv` contains the complete monthly
  timeline for deeds and new mortgages through July 2026.
- `tableau_data/tableau_ingestion/viz2_citywide_property_price.csv` contains annual citywide
  medians for eligible single-property deeds; 2026 is explicitly YTD.
- `tableau_data/tableau_ingestion/viz3_zip_price_projection.csv` contains history and scenario
  projections for five ZIP codes.
- `tableau_data/viz3_selected_zip_codes.csv` records exactly why those five ZIP
  codes were selected. The default definition of “similar increase” is the
  smallest absolute difference from citywide 2015-2025 CAGR.
- `tableau_data/viz3_zip_projection_accuracy.csv` reports a 2021-2025 holdout
  check for the log-linear annual trend used in the scenario.

## 3. Recommended focus areas

### Focus area 1: Citywide market cycles and disruptions

**Question**

How did deed and new-mortgage volumes change from 2000 through July 2026, and which
periods differed materially from established trends?

**Measures already available**

- Monthly deed and new-mortgage counts.
- Nominal-transfer and unknown-consideration counts.
- Monthly market-price summaries.
- Year-over-year changes.
- Seasonal decomposition.
- Backtests for the 2008 financial crisis, 2020-2025 disruption period, and a
  recent-regime stress test.
- Forward forecasts with 80% and 95% intervals.

**Current code and data**

- Sections 4-7 and 9-10 of `R/BSAN_Proj.R`.
- `tableau_data/fact_monthly_citywide.csv`.
- `tableau_data/model_forecast_accuracy.csv`.

**Week 03 methods**

- Summarize annual and monthly counts.
- Compare major periods: 2000-2007, 2008-2012, 2013-2019, 2020-2022, and
  2023-2025; show 2026 separately as January-July year-to-date.
- Use line charts and year-over-year charts for volume.
- Use stacked bars to show deed composition: market-priced, nominal, and
  unknown consideration.
- Use log-scaled distributions or boxplots for positive sale consideration.
- Treat the existing forecasts as a later-stage extension until the client
  confirms that forecasting activity or workload is useful.

**Provisional evidence to discuss, not final conclusions**

- The cleaned document table contains 1,269,061 records classified as deeds.
- Deed volume peaked at 65,028 in 2005, with another large increase to 62,232
  in 2022. It fell to about 38,500 in both 2023 and 2024, then increased to
  40,852 in 2025. January-July 2026 contains 23,224 recorded deeds and should
  not be compared as a full year.
- New-mortgage volume peaked at 92,754 in 2006 and was materially lower in
  2023-2025.
- About 25.2% of deed records are nominal transfers and 14.1% have unknown
  consideration. Those shares make sample-definition decisions important for
  every price chart.

**Dashboard concept**

A citywide timeline with a metric selector for deeds, new mortgages, nominal
transfers, price, and recorded local tax. Add recession or disruption bands and
a separate actual-versus-forecast view only if the client values forecasting.

### Focus area 2: ZIP price trajectories and long-term scenarios

**Question**

Which Philadelphia ZIP codes have followed similar property-price paths, and
which five should be carried into a transparent long-term projection scenario?

**Measures already available**

- Annual median eligible single-property deed consideration by ZIP.
- Eligible-sale counts and interquartile price ranges by ZIP.
- Complete-year history from 2000-2025 and separately labeled 2026 YTD data.
- A normalized Redfin input specification for a residential-price benchmark.

**Current code and data**

- `R/core_visualizations.R`.
- `tableau_data/tableau_ingestion/viz2_citywide_property_price.csv`.
- `tableau_data/tableau_ingestion/viz3_zip_price_projection.csv`.
- `tableau_data/viz3_selected_zip_codes.csv`.
- `tableau_data/viz3_zip_projection_accuracy.csv`.

**Week 03 methods**

- Use the working definition that “similar increase” means closest to the
  citywide 2015-2025 compound annual growth rate.
- Require a minimum annual sale count and show excluded ZIP-years.
- Compare historical growth using complete years; keep 2026 as YTD context.
- Backtest candidate annual trend models before choosing one.
- Treat a 10-15 year result as a scenario projection with wide uncertainty,
  not a precise forecast.
- Prefer Redfin for a residential-market interpretation and retain RTT as a
  recorded-property-market benchmark.

**Current projection cautions**

- The implemented log-linear scenario includes a 2021-2025 holdout diagnostic,
  but its error should be reviewed before it is presented as a final client
  result.
- Ten- to fifteen-year horizons are highly sensitive to the model and starting
  period, so model selection must use backtesting and prediction intervals.
- The RTT source does not contain a clean residential-use field. Its ZIP price
  series includes eligible property deeds, not necessarily typical homes.
- ZIP `19192` appears in RTT records but has no matching ACS ZCTA and therefore
  cannot receive an income ratio.

**Dashboard concept**

A five-ZIP comparison with historical price paths, the citywide benchmark, and
clearly separated projection scenarios. Include transaction counts so sparse
ZIP-years are visible.

### Focus area 3: ZIP price relative to household income

This focus area supplies the fourth correlation view and fifth affordability
trend view. It uses only the years for which both Redfin ZIP prices and ACS
income are available and does not force the longer RTT timeline onto the
shorter affordability panel.

**Question**

How does the relationship between property prices and household income vary
across Philadelphia ZIP/ZCTA areas and over the years with comparable data?

**Measures already available**

- ACS 5-year median household income and margin of error by ZCTA.
- RTT median eligible single-property price by ZIP-year.
- Price-to-income ratio for matched ZIP/ZCTA-years.
- Pearson and Spearman correlation matrices.
- Optional Redfin residential prices after the teammate handoff is available.

**Current code and data**

- `R/zip_affordability_etl.R`.
- `external_data/acs_zcta_income.csv`.
- `tableau_data/fact_zip_price_income.csv`.
- `tableau_data/model_zip_price_income_correlations.csv`.

**Week 03 methods**

- Start with price-versus-income scatterplots and price-to-income trends.
- Retain ACS margins of error and flag imprecise income estimates.
- Show Pearson and Spearman results because prices and ratios are skewed.
- Use the latest 2024 ZIP cross-section for the client-facing matrix. Retain
  annual cross-sections and the pooled 2012-2024 result as diagnostics because
  trending levels can inflate pooled correlations.
- Use Redfin as the preferred price numerator for housing affordability once
  the normalized teammate file is available.

**Current affordability cautions**

- Postal ZIP codes and Census ZCTAs are related but not identical.
- ACS 5-year estimates pool five years and adjacent annual releases overlap.
- Correlating a ratio with its own numerator or denominator creates a partly
  mechanical relationship and should not be interpreted causally.
- The current validated affordability build covers 2012-2024 after matching
  Redfin ZIP observations to the available ACS income series.
- The primary correlation chart uses 39 eligible ZIPs in 2024 and shows only
  the lower triangle; the long-form model export retains annual and pooled
  matrices for reproducibility.
- RTT price measures are not restricted to residential property. Final housing
  affordability conclusions should wait for Redfin or a property-use filter.

**Dashboard concept**

An affordability view with a ZIP selector, price and income trends, a
price-to-income line or map, and a supporting correlation heatmap. Display the
income margin of error in tooltips or a reliability flag.

## 4. Week 03 requirement audit

| Expected item | Already available | What should be added or confirmed next |
|---|---|---|
| Descriptive statistics | Monthly citywide activity plus citywide and ZIP property-price summaries | Add one concise table covering activity, eligible property sales, ZIP coverage, and 2026 YTD treatment |
| Missing-data review | Unknown consideration, assessment coverage, missing tax, ZIP coverage, and ACS margins of error | Summarize missing price, unmatched ZIP/ZCTA, low-sale-count ZIP-years, and income reliability |
| Outlier handling | Nominal flag, unknown-price flag, $11 million upper-tail cutoff, reconciliation flags | Show counts and sensitivity with and without flagged values; do not delete them from volume analysis |
| Data transformations | Date keys, ZIP standardization, log transforms, year-over-year change, and price-to-income ratios | Add inflation-adjusted price or label every long-run price chart as nominal dollars |
| Correlation analysis | ZIP price-income matrix and affordability trend are built for the 2012-2024 overlap | Treat correlation as supporting EDA and avoid causal language |
| Crosstabs | Some grouped summaries exist in code | Add explicit crosstabs listed below with counts and row percentages |
| Variable-level visualizations | Citywide activity, citywide annual price, and a five-ZIP historical/projection panel are implemented | Refine chart annotations and transfer the validated CSVs into Tableau |
| Two or three focus areas | Citywide activity/price and ZIP price trajectories form one coherent research area | Confirm whether the final scenario horizon should be 10 or 15 years |
| Detailed approach | Methods exist across the script | Present the scope, method, output, caveat, and decision use for each focus area |
| Collaboration plan | ACS income ETL and a Redfin handoff specification now exist | Assign the Redfin normalization and approve its residential property category |
| Dashboard preparation | Tableau-ready files and manifest exist | Build a storyboard and select a small set of decision-relevant visuals before formatting dashboards |

## 5. Crosstabs to add next week

The current analysis does not yet provide a clear crosstab package. At minimum,
create these tables with counts and row percentages:

1. `activity_type` by analysis period.
2. `transaction_type` by year or five-year period.
3. `deed_variant` by `nominal_transfer` and `unknown_consideration`.
4. Single-parcel versus multi-parcel document by deed variant and price flag.
5. ZIP by recent price band and minimum-sale-count status.
6. ZIP/ZCTA match status by year and price source.
7. Financial aggregation method by activity type.

These crosstabs will expose composition changes that a citywide line chart can
hide. They also provide direct QA for the dashboard filters.

## 6. Variable-level EDA plan

### Identifiers and counts

- Confirm uniqueness at the declared grain.
- Plot the distribution of parcels per document.
- Report the number and share of multi-parcel filings.

### Dates

- Plot monthly and annual record counts.
- Report recording delays and investigate negative or extreme delays.
- Mark sparse or disruption periods without treating them as bad data.

### Categories

- Bar chart for `activity_type`.
- Bar chart for detailed deed variants.
- Compare new mortgages with mortgage-lifecycle filings rather than combining
  them in the analytical measure.

### Financial fields

- Report median, quartiles, selected percentiles, missingness, and zero counts.
- Use log scales for positive consideration and tax distributions.
- Compare reported and adjusted values using reconciliation differences.
- Separate nominal, unknown, and high-value cases.

### Geography

- Report ZIP coverage and ZIP/ZCTA matching.
- Compare RTT and Redfin ZIP coverage when the teammate file arrives.
- Use maps only after confirming that ZIP/ZCTA is the approved geography.

### Assessment and market value

- Report coverage before presenting medians.
- Compare assessed value, fair-market value, and consideration only for samples
  where the fields refer to comparable units.

## 7. Required fixes or pivots

### Keep the current direction

The following choices are sound and should remain:

- Separate parcel and document grains.
- Count transactions at document grain.
- Keep missing values distinct from zero.
- Separate new mortgages from mortgage lifecycle activity.
- Retain nominal and high-value records in volume counts.
- Use a complete monthly panel.
- Keep Tableau facts at declared grains rather than building one duplicated
  wide table.

### Fix before presenting price findings as final

1. **Replace or qualify the term `arms-length`.** The current rule identifies a
   deed with consideration above $100 that is not in the upper-tail flag. It
   does not prove an independent market sale. Sheriff deeds, condemnation,
   land-bank transfers, other deed variants, and related-party transfers may
   remain. Use `market-priced deed` until a defensible arms-length definition
   is approved.
2. **Separate single-property and multi-property filings.** A document total
   covering several parcels is not comparable to a single-property sale price.
   Present separate distributions or restrict a typical-home price view to
   single-parcel filings.
3. **Adjust for inflation or label nominal dollars.** A dollar in 2000 is not
   comparable to a dollar in 2025. Add CPI-adjusted 2025 dollars for long-run
   purchasing-value comparisons, or clearly label the existing series as
   nominal.
4. **Confirm the intended property population.** The RTT file does not provide
   a clean residential/commercial category in the current export. If the client
   wants housing-market conclusions, the project may need an OPA property-use
   join or a narrower defensible proxy.

### Validate before presenting ZIP projection findings as final

The code now selects by similarity to the citywide path, reports a 2021-2025
holdout check, excludes ZIP-years below the minimum sale threshold, keeps 2026
YTD outside model fitting, and shows 95% prediction intervals. The remaining
team decision is whether to present a 10-year or 15-year scenario.

### Keep earlier advanced work as optional prototypes

Ward clustering, economic regressions, peer-city comparisons, and Solver work
remain available in the project but are not part of the newly narrowed core
question. Do not spend Week 03 presentation time on them unless the client
explicitly asks to retain one as a supporting analysis.

## 8. Dashboard storyboard for next week

### Page 1: Citywide activity

- Monthly deed and new-mortgage trends.
- Year-over-year change.
- Annual eligible single-property median price, with 2026 labeled YTD.
- Deed composition by market-priced, nominal, and unknown consideration.
- Filters for period and activity type.
- One short interpretation area tied to the selected period.

### Page 2: Five-ZIP price trajectories

- Historical ZIP price paths and citywide comparison.
- Eligible-sale counts and low-volume warnings.
- Selection rule for the five ZIP codes.
- Long-term scenarios with uncertainty intervals after backtesting.

### Optional later page: Price relative to income

- ZIP/ZCTA price-to-income ratio.
- Price-versus-income scatterplot.
- Pearson and Spearman correlation heatmap.
- ACS margin-of-error or reliability indicator.
- Price-source selector after Redfin is available.

## 9. Questions for the client meeting

The answers to these questions should determine the final scope:

1. The working definition of “similar increase” is closest to the citywide
   2015-2025 growth rate. Does the client agree with that definition?
2. Is a 10-year scenario preferred to the current 15-year scenario?
3. Does the client want all property filings or a residential-market view? If
   residential, can the City provide a property-use classification or approved
   join to OPA data?
4. What does the source `discrepancy` field mean operationally, and is excluding
   all flagged rows the approved rule?
5. Is Redfin the approved primary source for residential ZIP prices, with RTT
   retained as a benchmark?
6. What counts as a market-priced sale for the client's purpose?
7. Are sheriff deeds, land-bank deeds, condemnation deeds, and multi-parcel
   filings in scope for price analysis?
8. Does the client need inflation-adjusted price trends?
9. Is ACS 5-year median household income the accepted affordability
   denominator, and is ZCTA an acceptable approximation for ZIP?
10. Are there other teams or City units that own property-use classifications
    or approved geographic crosswalks that we should contact?

## 10. Meeting-ready explanation of the research steps

Use this sequence when presenting the plan:

1. **Start with the unit of analysis.** The cleaned source preserves property
   records, while transaction analysis uses one row per legal document.
2. **Show the EDA plan.** Review volume, composition, missingness, outliers,
   prices, and geography before interpreting models.
3. **Introduce the three focus areas.** Citywide activity and price, five-ZIP
   price scenarios, and ZIP price relative to household income.
4. **Explain the methods in plain language.** Trends and crosstabs describe the
   data; correlations measure associations; projections estimate plausible
   future ranges under explicit assumptions.
5. **Show how each focus area becomes a dashboard page.** Every visual should
   answer a client question rather than display a field merely because it is
   available.
6. **End with decisions needed from the client.** Confirm geography, population,
   ZIP-selection rule, property population, price source, income definition,
   and forecast horizon.

## 11. Deliverables for next week

The minimum Week 03 package should include:

- A one-page statement of the main question and three focus areas.
- A descriptive-statistics table at document, month, and ZIP-year grain.
- A missingness and outlier summary by period and activity type.
- The seven crosstabs listed above.
- Four to six polished EDA visuals selected for dashboard reuse.
- A ZIP price-income correlation table and scatterplot with interpretation
  limits.
- A dashboard storyboard with no more than three core pages.
- A decision log containing answers from the client meeting.
- A short list of analyses that remain exploratory or assumption-dependent.

## 12. Definition of done

Week 03 is complete when the team can answer all of the following:

- What are the two or three questions the final dashboard will answer?
- Which cleaned table and grain supports each question?
- Which records are included in every count and price measure?
- How much missingness affects each conclusion?
- Which transformations make comparisons valid?
- Which relationships are descriptive, associative, predictive, or
  prescriptive?
- Which visuals will appear in the dashboard?
- Which assumptions still require client approval?

The team does not need to discard the advanced work already completed. The
correct move is to use Week 03 as a validation gate, refine the scope, and then
carry only the defensible analyses into the final dashboards.
