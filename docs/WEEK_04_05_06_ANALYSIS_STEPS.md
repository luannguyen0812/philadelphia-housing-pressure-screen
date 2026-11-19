# Weeks 4-6 Analysis and Implementation Steps

| Project setting | Decision |
|---|---|
| Final research theme | Housing pressure and potential displacement risk across five Philadelphia ZIP/ZCTAs, with 19132 and 19143 as detailed case studies |
| Implementation period | Weeks 4, 5, and 6 |
| Primary audience | City housing, planning, preservation, and community outreach stakeholders |

**Scheduling convention:** Bracketed labels show when each component should be
implemented. A range such as `[Weeks 4-5]` means construction begins in Week 4
and validation or refinement continues in Week 5.

### Three-week delivery map

| Week | Primary purpose | Main output |
|---|---|---|
| **Week 4** | Lock the five-ZIP screen, validate the two detailed case studies, acquire ACS fields, and construct the joined analytical panel | Validated five-ZIP screen, two-ZIP case-study panel, coverage report, and preliminary metrics |
| **Week 5** | Put the two case studies in citywide context, validate the market measures, and test whether the selection is robust | All-ZIP benchmark panel, Philadelphia baselines, property-type/unit sensitivity checks, source reconciliation, and validated forecasting |
| **Week 6** | Build the dashboard and connect validated evidence and scenarios to differentiated responses | Final all-ZIP Tableau dashboard, two-ZIP case-study views, evidence-linked recommendations, speaker notes, and reproducible handoff |

### Week 5 implementation status (October 22, 2026)

Week 5 is now an implemented evidence-validation layer, not only a proposal.
The first complete build adds:

- a 37-qualifying-ZIP benchmark and a separately labeled pooled/median
  Philadelphia comparison;
- an all-ZIP test of price growth versus eligible transaction change;
- an OPA join covering approximately 98% of the eligible 19132 and 19143 sale
  records used in the property-type sensitivity analysis;
- an explicit finding that OPA's `unit` field is an address designator, not a
  complete dwelling-unit count, so project-wide price per dwelling unit is not
  currently defensible;
- official L&I permit counts and units reported on new-construction permits;
- Eviction Lab ZIP-level filing trends compared with pre-pandemic baselines;
- Redfin inventory and days-on-market context;
- Redfin-versus-RTT price and activity reconciliation;
- non-overlapping 2010-2014 and 2020-2024 ACS income endpoints compared with
  2014 and 2024 Redfin prices; and
- seasonal-naive, ETS, and ARIMA transaction forecasts validated in 2019 and
  2022-2024 holdouts, plus a common 2024-2025 pandemic-treatment sensitivity
  test and conditional prediction intervals through 2035.

The historical ACS expansion for education, tenure, poverty, age, rent, and
burden is still gated: as of May 2026 the Census Data API requires an API key
for all data queries. The repository uses existing cached ACS income endpoints
and records the unbuilt fields in
`tableau_data/week05_neighborhood_change_availability.csv`; no missing measure
is silently treated as no change.

## 1. Final research direction [Week 4]

The project will move from broad citywide exploratory analysis to a five-ZIP
screen and a focused comparison of 19132 and 19143. The five candidates show
how market growth and resident vulnerability vary across the selection
quadrants. The two upper-right ZIPs receive the detailed analysis of housing
pressure, affordability, resident vulnerability, and possible displacement
exposure.

The project should describe **housing pressure** and **potential displacement
risk**. Gentrification is a broader neighborhood-change process involving
market, socioeconomic, and demographic change. The current evidence does not
establish that a ZIP has gentrified or that an individual household was
displaced.

Week 5 will retain 19132 and 19143 as the detailed case studies while testing
whether their selection is robust. The test will compare the two ZIPs with all
qualifying Philadelphia ZIP/ZCTAs and the City as a whole, examine alternative
property definitions, and add demographic-change evidence. The purpose is to
contextualize the selected ZIPs, not restart the case-study selection without a
documented reason.

### Final research question [Week 4]

> Do 19132 and 19143 continue to show unusual housing pressure and resident
> vulnerability when compared with all qualifying Philadelphia ZIP/ZCTAs and
> the City overall, and which responses best match the validated risks?

### Analytical logic [Week 4]

```text
Resident vulnerability and baseline housing conditions
    -> Housing-market change relative to Philadelphia
    -> Affordability and transaction pressure
    -> Demographic or housing-instability evidence
    -> Potential displacement risk
    -> Targeted City response
```

The final result should not be a collection of unrelated graphs. Every measure
must help explain either the pressure occurring in a ZIP code, the residents
who may be exposed, or the response that the City could consider.

## 2. Role of affordability, activity, and assessment measures [Weeks 4-5]

### 2.1 Price-to-income ratio: primary affordability indicator [Weeks 4-5]

```text
Price-to-income ratio = median residential sale price
                        / median household income
```

This ratio evaluates whether local home prices are becoming increasingly
disconnected from the incomes of households living in the ZIP code. A ratio of
4.0 means that the median sale price is approximately four times the median
annual household income.

It helps answer:

- Are prices increasing faster than local incomes?
- Which detailed ZIP code has experienced greater affordability pressure?
- Is that pressure persistent or driven by one unusual year?
- How does each ZIP compare with Philadelphia overall?

This is a descriptive screening measure, not a complete homebuyer
affordability calculation. It does not account for mortgage interest rates,
down payments, property taxes, insurance, credit qualification, or the actual
income of the households purchasing the homes.

### 2.2 Sale-to-assessment ratio: appendix diagnostic [Weeks 4-5]

```text
Sale-to-assessment ratio = property sale price / assessed property value
```

This ratio evaluates how closely assessed values track observed sale prices.
It is not a direct measure of homebuyer affordability.

- A ratio near 1.0 means sale price and assessment are approximately aligned.
- A ratio above 1.0 means the property sold for more than its assessed value.
- A ratio below 1.0 means the property sold for less than its assessed value.

The ratio can support the displacement-risk theme indirectly. If market prices
rise substantially above assessments, a later reassessment may increase
property-tax exposure for existing owners. That exposure may be more important
for lower-income, elderly, fixed-income, and longtime homeowners.

The final presentation should describe this measure as **assessment
alignment**, not as proof of mortgage availability, political intent, tax-bill
change, or buyer affordability. The main presentation should use transaction
activity instead while assessment-year alignment remains unverified.

### 2.3 How the measures complement one another [Week 5]

| Measure | Main question | Population most relevant |
|---|---|---|
| Price-to-income | Are market prices aligned with local incomes? | Prospective buyers and the wider community |
| Transaction activity | Is recorded market activity increasing or decreasing? | Neighborhood market; not a direct measure of household movement |
| Rent burden | Can tenants continue to afford housing costs? | Renters |
| Appendix sale-to-assessment | How do recorded sale prices compare with the RTT assessed-value field? | Existing property owners; interpretation limited by missing assessment year |

The measures should remain separate. They should not be combined into one
unexplained index.

## 3. Screening five ZIP codes and selecting two case studies [Week 4]

The presentation screen contains five ZIP/ZCTAs: 19132, 19143, 19122, 19138,
and 19119. Citywide medians across all qualifying Philadelphia candidates set
the market-growth and vulnerability quadrant boundaries. The two detailed
areas must remain in the high-growth, high-vulnerability quadrant rather than
being selected because their graphs appear interesting.

The screen covers all four quadrants:

- 19132 and 19143: higher growth and higher vulnerability; detailed case
  studies;
- 19138: higher growth and lower vulnerability;
- 19122: lower growth and higher vulnerability; and
- 19119: lower growth and lower vulnerability.

This design allows the team to explain why similar market changes may produce
different consequences for residents.

### Recommended selection matrix [Week 4]

| | Lower resident vulnerability | Higher resident vulnerability |
|---|---|---|
| Lower market pressure | Monitor and maintain baseline | Prioritize resident support and stability |
| Higher market pressure | Manage growth and monitor affordability | Highest anti-displacement attention |

### Minimum selection criteria [Week 4]

1. Adequate annual sale observations in both ZIP codes.
2. Matched Redfin price and ACS income coverage through 2024.
3. Acceptable ACS margins of error for the main indicators.
4. A meaningful difference in either market pressure or vulnerability.
5. No selection based solely on the most extreme observed value.

The team should record the rule and selected ZIP codes before interpreting the
final results.

In Week 5, report where all qualifying Philadelphia ZIP/ZCTAs fall on the same
measures, not only the five presentation ZIPs. The five-ZIP screen remains a
readable slide; the full distribution belongs in the dashboard and validation
tables. If the selected ZIPs change materially under defensible property-type,
unit, or source definitions, document the sensitivity rather than hiding it.

The full Week 5 distribution shows that 19140 is the closest qualifying ZIP to
19132 on the growth/vulnerability quadrant: it has approximately 15.2% price
growth CAGR and a 73.4% vulnerability percentile, compared with 17.0% and
73.9% for 19132. Therefore, 19132 and 19143 must be described as a
**purposefully contrasting pair**, not the two highest-scoring ZIPs. 19140 is
not excluded for inadequate coverage; it is retained as a close high-pressure
benchmark because it largely duplicates the 19132 quadrant profile. In
contrast, 19143 adds a higher current price, higher price-to-income ratio,
higher renter share/cost burden, and a different transaction trajectory.

The selection-slide speaker notes must explicitly disclose this comparison.
If the objective changes to selecting the two most extreme combined
growth/vulnerability cases, the current evidence would favor 19132 and 19140
and the group must rerun the downstream case-study analysis.

> **Selection-slide speaker note:** “19140 is the closest alternative to 19132
> and has similarly high price growth and measured vulnerability. We retained
> it as a benchmark rather than a second case study because it largely repeats
> the 19132 quadrant profile. We selected 19143 to provide a contrasting
> higher-price, higher-price-to-income, renter-heavy case. Therefore, 19132 and
> 19143 are purposeful contrasting cases—not the two highest-scoring ZIPs.”

## 4. Analytical dimensions to build [Weeks 4-5]

### 4.1 Market pressure [Weeks 4-5]

Use Redfin and Philadelphia real-estate-transfer (RTT) data to calculate the
same measures for 19132, 19143, every qualifying Philadelphia ZIP/ZCTA, and a
clearly defined City benchmark:

- nominal and inflation-adjusted median residential sale price;
- five-year and ten-year price growth;
- current price level relative to the Philadelphia median;
- price growth relative to Philadelphia overall;
- eligible sale counts and changes in transaction activity;
- transaction counts and transactions per 1,000 occupied housing units;
- price-growth speed, measured by CAGR, separately from acceleration, measured
  as the change in growth rate between pre-pandemic and recent periods;
- the appendix sale-to-assessment ratio and its interquartile range; and
- the stability of each trend after removing low-volume years.

The city comparison is necessary. A 30% increase in one ZIP is not necessarily
an unusual local signal if Philadelphia overall also increased by 30%.

#### Property type and price-per-unit decision gate [Week 5]

The current Redfin ZIP series is aggregated and the current RTT extracts contain
parcel counts, not residential-unit counts. `property_count` and
`n_parcel_rows` must not be treated as the number of homes within a property.
Complete the following checks in order:

1. Compare Redfin All Residential trends with available Redfin property-type
   series, including single-family, condominium, and multifamily categories.
2. Join the official OPA property file by account/parcel number and audit both
   match coverage and the meaning of its `unit` field.
3. The implemented OPA join matches approximately 98% of eligible records, but
   `unit` is an address designator and is populated on only a very small share
   of case-study parcels. It must not be interpreted as dwelling-unit count.
4. Therefore, separate the principal results by OPA property class and label
   the outcome as price per transacted property. L&I `numberofunits` is retained
   only as a permitted-project pipeline field, not the existing-unit stock.
5. Report whether 19132 and 19143 remain unusual under each defensible
   specification.

Also reconcile annual Redfin and RTT price trends. Compare direction, growth,
coverage, property definitions, and low-volume years rather than expecting the
two sources to produce identical medians.

### 4.2 Affordability pressure [Weeks 4-5]

Retain the current price-to-income ratio and add:

- median gross rent;
- renter cost burden: share spending at least 30% of income on rent;
- severe renter cost burden: share spending at least 50%;
- owner housing costs as a percentage of income;
- income growth compared with sale-price and rent growth; and
- an optional mortgage-payment-to-income scenario, clearly labeled as a
  scenario rather than observed buyer affordability.

### 4.3 Resident vulnerability [Weeks 4-5]

Introduce resident vulnerability before the market-pressure results. Compare
the two detailed case-study ZIPs with the Philadelphia ZIP/ZCTA distribution
and, where geographically comparable, the City estimate on:

- renter and homeowner share;
- poverty rate;
- median household income;
- educational attainment;
- senior population;
- renter and owner housing-cost burden;
- recent-mover or residential-mobility measures;
- households receiving public assistance, if retained; and
- ACS margins of error and data-quality flags.

For neighborhood-composition change, prefer non-overlapping ACS five-year
endpoints such as 2010-2014 and 2020-2024. This avoids treating heavily
overlapping releases as independent annual observations. Keep the endpoint
periods and margins of error visible in the output.

This dimension prevents the analysis from treating appreciation as equivalent
to displacement risk. Similar price growth can have different implications in
a high-income, owner-occupied ZIP and a lower-income, renter-heavy ZIP.

ACS is a survey. Retain estimates and margins of error together, flag unstable
ZIP-level estimates, and state that populations facing housing instability may
be difficult to measure fully. Do not describe small percentage differences as
substantive when their uncertainty overlaps.

### 4.4 Observable housing-instability signals [Week 5 - priority if available]

Prioritize eviction filings as the first outcome-oriented source because both
case studies show substantial renter exposure. If usable eviction coverage is
not available, document that constraint and select only one alternative:

- property-tax delinquency or foreclosure;
- residential turnover;
- demolition, construction, or conversion permits;
- investor or corporate purchases; or
- changes in affordable rental inventory.

Week 5 now includes both Eviction Lab filings and L&I permit evidence because
they answer different questions: filings are a renter-instability signal,
whereas permits describe authorized development activity. Neither is treated
as direct proof that a household was displaced.

### 4.5 Validated trajectory and forecasting analysis [Weeks 5-6]

Replace unvalidated long-range trend extrapolation with a time-ordered model
comparison. Select a target with adequate frequency and coverage, preferably
monthly or quarterly transaction activity or price for Philadelphia and the
two detailed ZIPs. Compare:

- seasonal naive or random-walk baseline;
- ETS;
- ARIMA; and
- dynamic regression only when defensible predictors are available.

Use rolling-origin or blocked holdout validation and report MAE, RMSE, and MASE.
Pandemic sensitivity is implemented three ways: retain all observations with
explicit pandemic and recording-backlog intervention indicators; treat the
identified disruption months as missing; and fit only the May 2022 onward
regime. All alternatives are judged on the same January 2024-December 2025
holdout. No treatment wins for both ZIPs, so the all-history intervention model
is the transparent reference and the alternative paths are retained as a
sensitivity range. Display prediction intervals and describe a 2035 path as a
long-horizon conditional forecast with substantial uncertainty. XGBoost may be
added as a challenger only if the dataset has enough observations and
predeclared lagged features; LightGBM is not required.

## 5. Recommended core visualizations [Weeks 5-6]

Use one semantic color system throughout the slides and dashboard:

- 19132: orange;
- 19143: blue;
- Philadelphia: black;
- other comparison ZIPs: gray; and
- time periods: light/dark shades or different shapes, not the ZIP colors.

### Visualization 1: Vulnerability profile with baseline [Week 5]

Introduce vulnerability first. Use a compact dot or dumbbell profile for the
four screening components: renter share, renter cost burden, poverty, and
senior share. Show 19132, 19143, and the Philadelphia comparison value. Include
MOE warnings in the tooltip or notes. Keep the additional severe-renter and
owner-cost-burden measures in the dashboard or appendix.

### Visualization 2: Selection and citywide context [Week 5]

Retain the readable five-ZIP quadrant slide, with bold citywide-median reference
lines. Add a dashboard version containing all qualifying Philadelphia ZIP/ZCTAs
and tooltips for price level, growth, vulnerability, transaction coverage, and
MOE flags. State that the x-axis measures growth speed, not current price level
or acceleration.

### Visualization 3: Price, income, and Philadelphia trajectory [Week 5]

Compare both detailed ZIPs with Philadelphia using either indexed trends or a
common-scale growth-gap dumbbell. Show current price level alongside growth so
the audience can see that a ZIP may remain below the city median while changing
rapidly. Label whether values are nominal or inflation-adjusted and identify
the common valid period.

### Visualization 4: Transaction activity with comparison baseline [Week 5]

Retain the arm's-length eligible-sale definition and sales per 1,000 occupied
units. The slide may show the five readable comparison ZIPs, but the dashboard
must show all qualifying ZIPs and the Philadelphia benchmark. Use neutral
period styling so blue and orange remain reserved for the detailed ZIPs. Treat
the metric as property-market activity, not household turnover or direct proof
of displacement.

### Visualization 7: Pandemic-adjusted transaction forecast [Week 5]

Show actual values and the all-history intervention-adjusted forecast with 80%
and 95% prediction intervals. Shade the pandemic and recording-backlog windows,
make the expanding uncertainty prominent, and state that future intervention
fields are set to zero rather than implying that the disruptions never occurred.

### Visualization 8: Pandemic forecast sensitivity [Week 5]

Place the intervention-adjusted, disruption-excluded, and post-backlog forecast
paths on one common scale for each ZIP. Separation between the lines is model
uncertainty arising from the treatment of unusual years. It is not three
possible policy outcomes and should not be collapsed into a single precise
number.

### Appendix visualization: Sale-to-assessment trend [Week 5]

Retain the chart only as an assessment-alignment diagnostic until a year-specific
OPA assessment join resolves timing. It does not establish mortgage availability,
buyer affordability, political intent, or displacement.

### Final visualization: Evidence-to-response matrix [Week 6]

Summarize how vulnerability, market pressure, demographic or instability
evidence, and forecast/scenario conditions lead to a differentiated response.

## 6. Final Tableau dashboard [Week 6]

```text
+----------------------------------------------------------------------------+
| ALL-PHILADELPHIA CONTEXT WITH TWO DETAILED CASE STUDIES                     |
| ZIP [____]  Property type [____]  Period [____]  Source [Redfin | RTT]       |
+--------------------------------------+-------------------------------------+
| Vulnerability and selection context  | Case-study KPI comparison           |
| All qualifying ZIPs + City baseline  | Price level | growth | income | MOE |
+--------------------------------------+-------------------------------------+
| Price/income and City trajectory     | Transaction activity                |
| 19132 | 19143 | Philadelphia         | All ZIPs + sales per 1,000 baseline |
+--------------------------------------+-------------------------------------+
| Outcome/forecast evidence            | Evidence-linked City responses      |
| Evictions/permits + validated model  | Condition -> trigger -> response    |
+--------------------------------------+-------------------------------------+
| Screening and forecasting evidence; not proof of individual displacement  |
+----------------------------------------------------------------------------+
```

The dashboard should answer four questions without requiring the audience to
interpret separate spreadsheets:

1. What changed in each ZIP?
2. Is that change unusual relative to other ZIPs and Philadelphia overall?
3. Which residents appear most exposed?
4. Which response is supported by the observed evidence or scenario?

### Final Tableau semantic layer [Week 6]

The production ingestion folder contains only five files:

- `dim_geography.csv`, one row per geography key;
- `fact_zip_profile.csv`, one row per geography key;
- `fact_annual_signals.csv`, one row per geography key and year;
- `fact_monthly_forecast.csv`, one row per geography key, month, and series
  type; and
- `fact_policy_response.csv`, one row per recommendation key.

In Tableau, relate every fact directly to `dim_geography` through
`geography_key`. Do not physically join the facts: their grains differ and a
physical join would multiply records and inflate counts. The Week 6 runner
checks dimension uniqueness, fact primary keys, and orphan foreign keys. The
previous five-chart ingestion package is archived outside the production
folder.

### Tableau ZIP-filter behavior [Week 6]

- The workbook opens with **19132 and 19143 selected by default** in a visible
  multi-select Tableau set control named **Selected ZIPs**.
- Clients can select any one ZIP, any combination, or all qualifying
  Philadelphia ZIP/ZCTAs; the selector is not hard-coded to the case studies.
- Detail sheets for price, income, transactions, vulnerability, permits,
  eviction filings, inventory, and market time respond to the ZIP selector
  wherever the source has citywide ZIP coverage. Annual views use
  `City benchmark OR Selected ZIPs` so the comparison line remains visible.
- The citywide selection/quadrant sheet remains populated with all qualifying
  ZIPs and colors membership in **Selected ZIPs**. The selector must not remove
  the comparison distribution or median reference lines.
- Forecast and property-level OPA sensitivity sheets are labeled
  **case-study-only** until equivalent all-ZIP modeling/property joins are
  built; selecting another ZIP must show a clear availability message rather
  than a misleading blank chart.
- Include a `Reset to 19132 + 19143` navigation/filter action and an `All
  qualifying ZIPs` option so users can easily recover the intended starting
  view.

## 7. Connecting findings to recommendations [Week 6]

Recommendations should differ by ZIP and follow directly from the evidence.

| Observed condition or scenario | Evidence trigger to report | Potential City response |
|---|---|---|
| High renter burden with rising rent or eviction filings | Burden and outcome exceed the Philadelphia comparison | Eviction-prevention outreach and rental preservation |
| Rapid price or per-unit appreciation with vulnerable renters | Growth remains unusual after property-type and source checks | Preserve naturally occurring affordable housing and consider acquisition support |
| Increasing pressure on lower-income or senior homeowners | Owner burden, delinquency, assessment, or tax evidence supports the concern | Promote LOOP, installment plans, tangled-title support, and counseling |
| Permit or investor activity accelerates in a vulnerable area | Activity exceeds the ZIP's baseline and City trajectory | Target preservation, code enforcement, and community acquisition tools |
| Forecast indicates continued pressure | Validated model exceeds its benchmark and intervals remain policy-relevant | Begin time-consuming preservation and outreach remedies before the projected peak |
| Strong growth but lower measured vulnerability | Market change is unusual but exposure indicators remain lower | Monitor rather than label as a displacement priority |
| Weak, missing, or uncertain evidence | Coverage, MOE, source disagreement, or forecast error is material | Improve data collection and continue monitoring |

These are policy-alignment recommendations, not claims that one program will
causally prevent displacement. Final recommendations should also recognize
program eligibility, capacity, budget, and operational constraints.

## 8. Week-by-week implementation plan [Weeks 4-6]

### Week 4: Define and construct [Week 4]

**Objective:** Finalize the five-ZIP screen and produce an analysis-ready
two-ZIP case-study panel.

Tasks:

1. Confirm the five candidate ZIPs, the citywide quadrant thresholds, and the
   two detailed case studies.
2. Keep ZIP/ZCTA as the common analytical geography for this deliverable.
3. Add ACS measures for tenure, rent burden, poverty, senior population, median
   rent, owner housing costs, and residential mobility.
4. Retain ACS estimates and margins of error together.
5. Convert monetary trends to constant dollars for change comparisons while
   retaining clearly labeled nominal values where needed.
6. Construct ZIP-year price-to-income measures using the existing validated
   Redfin/ACS overlap.
7. Construct the five-ZIP transaction-activity comparison using three-year
   averages and a fixed occupied-housing-unit denominator.
8. Retain the sale-to-assessment calculation as an appendix diagnostic and
   document that assessment-year alignment remains unverified.
9. Produce a coverage table showing years, observations, exclusions, and MOE
   warnings for both detailed ZIP codes.

**Week 4 deliverables:**

- documented five-ZIP screen and two-ZIP case-study selection;
- joined two-ZIP analytical dataset;
- data dictionary and calculation notes;
- coverage and missingness report; and
- preliminary trend charts.

**Decision gate:** Do both ZIPs have enough comparable observations and reliable
ACS estimates to support the proposed comparison? If not, replace a ZIP using
the same predeclared selection rule.

### Week 5: Compare and validate [Week 5]

**Objective:** Put 19132 and 19143 in full Philadelphia context and determine
whether their apparent pressure remains meaningful under alternative sources,
property definitions, comparison periods, and uncertainty rules.

Tasks:

1. **Build the all-ZIP benchmark panel.** Calculate the selection, price,
   income, vulnerability, and transaction measures for every qualifying
   Philadelphia ZIP/ZCTA. Produce both the ZIP-level distribution and a
   separately labeled City benchmark.
2. **Keep the slide comparison readable.** Retain the five comparison ZIPs for
   presentation, but use the complete qualifying set in statistical checks and
   the dashboard.
3. **Introduce vulnerability first.** Add the Philadelphia comparison and MOE
   status to the four-component vulnerability profile. Do not imply that ACS
   point estimates are exact or that the survey captures every vulnerable
   household.
4. **Resolve the property-unit question.** Inventory Redfin property types and
   seek an OPA residential-unit-count field. Never substitute parcel count for
   housing-unit count. Use the decision gate in Section 4.1 to choose
   price-per-unit, one-unit-only, property-type-separated, or clearly labeled
   price-per-property analysis.
5. **Reconcile Redfin with RTT.** Compare annual/quarterly trends, growth ranks,
   sample coverage, and definitions. Explain disagreements and test whether the
   case-study selection changes by source.
6. **Separate price level, speed, and acceleration.** Report current price
   relative to Philadelphia, CAGR as growth speed, and recent-minus-earlier
   growth as acceleration. Do not use these terms interchangeably.
7. **Benchmark transaction change.** Compare arm's-length eligible sales per
   1,000 occupied units across all qualifying ZIPs and Philadelphia. Test the
   price-growth/transaction association with a scatterplot, correlation,
   sample size, and low-volume sensitivity check; do not claim a cause.
8. **Measure neighborhood composition change.** Compare non-overlapping ACS
   endpoints, preferably 2010-2014 and 2020-2024, for income, education,
   tenure, poverty, age, rent, and burden. Retain MOEs and use this evidence to
   distinguish housing pressure from a stronger gentrification claim.
9. **Add one outcome-oriented source.** Prioritize eviction filings. If the
   geographic or temporal coverage is unusable, use permits as the documented
   substitute. Treat sheriff sales or foreclosure as a narrow homeowner-risk
   extension, not a general displacement measure.
10. **Evaluate Redfin market context.** Add inventory and days on market when
    definitions and ZIP coverage are adequate. Use these measures as possible
    explanations for price and transaction patterns, not automatic causes.
11. **Build and validate the forecast.** Compare naive, ETS, and ARIMA models
    with time-ordered validation. Test pandemic sensitivity, report error and
    intervals, and select a model only if it improves on the baseline.
12. **Apply sensitivity checks.** Test alternative base years, minimum sale
    counts, inflation treatment, property definitions, and exclusion of unusual
    years. Retain sale-to-assessment only as an appendix sensitivity result.
13. **Draft evidence profiles.** Write one evidence statement for each detailed
    ZIP covering vulnerability, price level and trajectory, transactions,
    demographic/outcome evidence, forecast uncertainty, and prohibited claims.
14. **Export dashboard-ready tables.** Use clearly named scripts, stable keys,
    source fields, City/ZIP geography labels, and data-quality flags.

**Week 5 deliverables:**

- all-qualifying-ZIP benchmark and separately labeled Philadelphia summary;
- revised vulnerability-first comparison views with consistent colors;
- property-type/unit-count feasibility memo and implemented decision;
- Redfin-versus-RTT reconciliation table and rank-stability check;
- price-level, speed, and acceleration comparison;
- all-ZIP transaction benchmark and noncausal association test;
- non-overlapping ACS neighborhood-composition comparison;
- eviction-filing analysis or permits substitute;
- validated forecast comparison with a primary pandemic-adjusted view, a
  three-path pandemic sensitivity view, and prediction intervals;
- consolidated sensitivity-check table;
- preliminary Tableau data sources; and
- one evidence profile for each detailed ZIP.

**Implemented Week 5 scripts:**

- `R/week05_run_all.R`: reproducible runner for the complete Week 5 batch;
- `R/week05_citywide_context.R`: 37-ZIP benchmark, Philadelphia summary, and
  noncausal price-growth/transaction-change test;
- `R/week05_property_permit_validation.R`: OPA match/unit audit, property-type
  sensitivity, and L&I permit/unit pipeline;
- `R/week05_redfin_rtt_reconciliation.R`: annual source agreement, growth-rank
  sensitivity, and indexed trajectory comparison;
- `R/week05_neighborhood_change.R`: non-overlapping ACS income endpoints,
  price-versus-income change, and availability register for pending variables;
- `R/week05_eviction_market_signals.R`: Eviction Lab filings, Redfin inventory,
  and Redfin days on market; and
- `R/week05_time_series_forecasting.R`: two-window seasonal-naive/ETS/ARIMA
  validation, common-holdout pandemic-treatment sensitivity, and conditional
  transaction baselines through 2035.

See `docs/WEEK_05_DATA_DICTIONARY_AND_NOTES.md` for source URLs, field
definitions, refresh rules, current findings, and interpretation limits.

**Decision gate:** Do 19132 and 19143 remain defensible detailed case studies
after the City/all-ZIP comparison, unit/property-type test, source
reconciliation, MOE review, and time-ordered forecast validation? If a result
is unstable, narrow or qualify the claim rather than selecting the most
favorable specification.

### Week 6: Recommend and communicate [Week 6]

**Objective:** Convert the validated citywide context and two-ZIP evidence into
a decision-oriented dashboard, forecast/scenario interpretation, and responses
that can begin before pressure becomes more severe.

Tasks:

1. Build the interactive all-Philadelphia context view from the completed Week
   5 exports. Default the visible multi-select ZIP filter to 19132 and 19143,
   while allowing any qualifying ZIP, any combination, or all ZIPs. Add filters
   for property type, source, and period, plus detailed views for the two case
   studies.
2. Preserve the five-ZIP screen as a readable presentation layer while making
   every qualifying ZIP available in the dashboard.
3. Apply the fixed semantic color system across R, Tableau, and PowerPoint.
4. Display Philadelphia baselines, sample sizes, MOE/data-quality flags, and
   source definitions in tooltips and notes.
5. Add the validated forecast only if the chosen model beats the seasonal-naive
   baseline on the predeclared holdout criterion. Separate observed
   data, forecast values, prediction intervals, and policy scenarios visually
   and verbally.
6. Explain why acting early may matter: preservation, acquisition, outreach,
   and legal remedies require lead time even when current prices remain below
   the City median.
7. Link each recommendation to an observed condition or forecast/scenario
   trigger. Make renter, homeowner, preservation, and monitoring responses
   distinct.
8. Make the recommendations different where 19132 and 19143 differ, and avoid
   claiming that one policy will causally prevent displacement.
9. Add a concise limitations panel covering ACS sampling, ZIP/ZCTA mismatch,
   property-versus-unit definitions, Redfin/RTT disagreement, pandemic effects,
   outcome-source coverage, and forecast uncertainty.
10. Fact-check every dashboard and slide number against the exported tables.
11. Synchronize definitions, periods, colors, findings, and limitations across
    R outputs, Markdown, HTML, Tableau, the decision log, and PowerPoint.
12. Rehearse a narrative that moves from vulnerability to citywide context,
    validated pressure, possible future conditions, and evidence-linked action.
13. Add a required selection speaker note: 19140 closely matches 19132 and was
    retained as a benchmark; 19143 was chosen to create a contrasting
    higher-price, renter-heavy affordability case rather than because it had
    the second-highest quadrant score.
14. Include a forecast methods box and technical appendix stating the target,
    January 2010-December 2025 training period, 192 monthly observations per
    ZIP, 120-month horizon, candidate models, holdout windows, selected
    Auto-ARIMA orders, intervention variables, residual check, and the absence
    of external market predictors.

**Week 6 deliverables:**

- final Tableau dashboard with every qualifying ZIP, a City baseline, and two
  detailed case-study views;
- final five-ZIP presentation screen;
- two-ZIP evidence, forecast/scenario, and recommendation matrix;
- presentation-ready charts using the consistent color system;
- speaker notes explaining definitions, comparisons, uncertainty, claim
  boundaries, and the explicit 19140-versus-19143 selection rationale;
- reproducible exports and source documentation;
- updated Markdown, HTML, data dictionary, run order, and decision log; and
- final limitations and next-steps statement.

**Implemented Week 6 scripts:**

- `R/week06_run_all.R`: complete Week 6 runner and final package validation;
- `R/week06_dashboard_exports.R`: geography dimension, ZIP profile, annual
  signals, observed/forecast fact, relationship audit, and percentile profile;
- `R/week06_forecast_technical_appendix.R`: selected Auto-ARIMA orders,
  coefficients, residual diagnostics, sample/construction metadata, and
  unseen-period RMSE visualization;
- `R/week06_exogenous_forecast_challenger.R`: same-sample test of lagged
  mortgage rates, Redfin inventory, and days on market against the
  intervention-only model; and
- `R/week06_policy_scenario_matrix.R`: differentiated evidence triggers,
  conditional responses, lead times, monitoring metrics, claim boundaries,
  and the policy-priority visualization.

See `docs/WEEK_06_DATA_DICTIONARY_AND_DASHBOARD_GUIDE.md` and
`tableau_data/tableau_ingestion/README.md` for the final relationship model,
field definitions, filter behavior, and dashboard build specification.

**Decision gate:** Can a City audience identify who appears vulnerable, whether
the selected ZIPs differ from Philadelphia and other ZIPs, which results are
robust, what the forecast does and does not establish, and which response is
triggered by each evidence pattern?

## 9. Required technical cautions [Weeks 4-6]

1. **[Week 4] ZIP and ZCTA are not identical.** Describe the ACS join as a ZIP/ZCTA
   approximation and document unmatched areas.
2. **[Weeks 4-5] ACS five-year releases overlap.** Avoid interpreting every adjacent annual
   change as a completely new sample.
3. **[Week 4] ACS one-year data are not published for ZCTAs.** Use ACS five-year
   releases for ZIP-level comparisons. If ACS one-year data are used for a
   Philadelphia citywide benchmark, label the different geography and source
   separately.
4. **[Weeks 4-5] Margins of error matter.** Retain MOE fields and flag unreliable
   comparisons rather than silently dropping them.
5. **[Week 4] Use constant dollars for long-run growth.** Nominal growth can overstate
   changes in purchasing power.
6. **[Week 4] Redfin observations are rolling periods.** Preserve the documented annual
   aggregation rule and do not describe the source as ordinary monthly sales.
7. **[Weeks 4-6] Sale-to-assessment is an appendix diagnostic.** It does not
   establish mortgage availability, political intent, a tax-bill change, or
   buyer affordability.
8. **[Week 4] Assessment timing must align with sales.** A mismatched assessment year can
   create an artificial ratio gap.
9. **[Week 5] Medians can hide distributional differences.** Report the interquartile
   range and eligible observation count.
10. **[Weeks 5-6] Correlation is not causation.** The analysis identifies conditions that
   warrant monitoring; it does not prove that price changes caused migration or
   displacement.
11. **[Week 5] Properties, parcels, and housing units are different.** A
    multifamily property sale is not a single housing-unit sale. Parcel counts
    do not supply residential-unit counts.
12. **[Week 5] Redfin and RTT measure different samples.** Compare their
    definitions and trajectories; do not expect identical medians or silently
    choose the source with the stronger result.
13. **[Week 5] Price level, growth speed, and acceleration are different.** A
    below-median ZIP can grow rapidly; CAGR does not measure acceleration.
14. **[Weeks 5-6] ACS is sample-based.** Retain MOEs, flag unstable estimates,
    and acknowledge potential underrepresentation of hard-to-survey residents.
15. **[Weeks 5-6] Forecasts require time-ordered validation.** Compare with a
    naive baseline, test pandemic sensitivity, and display prediction
    intervals. A long horizon does not become accurate merely because a model
    produced it.
16. **[Week 6] Two ZIPs are case studies.** Findings should not automatically be
    generalized to every Philadelphia neighborhood.

## 10. Minimum viable scope and optional extensions [Week 4 scope lock]

### Required for the final project [Week 4 - commit]

- a five-ZIP screen with two defensibly selected detailed case studies;
- an all-qualifying-ZIP validation panel and separately labeled City benchmark;
- property-type/unit-count feasibility check and transparent price definition;
- Redfin-versus-RTT reconciliation;
- price level, growth speed, and income comparison;
- price-to-income ratio;
- rent burden and tenure;
- resident-vulnerability comparison with Philadelphia baseline and MOE flags;
- five-ZIP presentation and all-ZIP dashboard transaction activity;
- non-overlapping ACS demographic-change comparison;
- eviction filings or permits as one outcome/investment source;
- validated naive/ETS/ARIMA forecast comparison with pandemic sensitivity;
- sale-to-assessment as an appendix diagnostic only;
- evidence-linked recommendations; and
- transparent limitations and data-quality checks.

### Add only if the required Week 5 work is complete [Week 5 decision gate]

- investor ownership or repeat-sale flips;
- a second outcome source beyond the required eviction/permit choice;
- XGBoost as a forecasting challenger if the sample supports it;
- mortgage-payment affordability scenario;
- affordable-housing inventory; or
- a parcel- or tract-level map beyond the required ZIP dashboard.

## 11. Definition of a successful final deliverable [Week 6]

The project is complete when the audience can understand:

1. why the five ZIPs were screened and whether the two detailed selections
   remain defensible against all qualifying ZIPs and the City benchmark;
2. how vulnerability differs before market results are introduced;
3. how price level, growth speed, acceleration, income, and transaction
   activity differ;
4. whether Redfin, RTT, and alternative property definitions support the same
   conclusion;
5. what the property-versus-unit analysis can and cannot measure;
6. whether demographic and outcome evidence supports housing-pressure,
   gentrification, or displacement language;
7. what the validated forecast adds beyond a simple scenario and how pandemic
   years affect uncertainty;
8. which City response is linked to each observed condition or scenario; and
9. which limitations prevent stronger causal or predictive claims.

## 12. Supporting policy and data references [Weeks 4-6]

- [Philadelphia OPA property file](https://opendataphilly.org/datasets/philadelphia-properties-and-assessment-history/)
- [Philadelphia L&I building and zoning permits](https://opendataphilly.org/datasets/licenses-and-inspections-building-and-zoning-permits/)
- [Eviction Lab tracking-system downloads](https://evictionlab.org/eviction-tracking/get-the-data/)
- [Redfin Data Center](https://www.redfin.com/news/data-center/)

- [Philadelphia Housing Action Plan dashboard](https://www.phila.gov/departments/department-of-planning-and-development/about/our-results/housing-action-plan-dashboard/)
- [Philadelphia H.O.M.E. Initiative](https://www.phila.gov/programs/home-initiative/)
- [Philadelphia Annual Action Plan 2024-2025](https://www.phila.gov/media/20240822181540/Annual-Action-Plan-Year-2024-2025-Final.pdf)
- [U.S. Census ACS rent-burden table B25070](https://api.census.gov/data/2023/acs/acs5/groups/B25070.html)
- [U.S. Census ACS areas published](https://www.census.gov/programs-surveys/acs/geography-acs/areas-published.html)
- [Philadelphia property assessment methodology](https://www.phila.gov/documents/assessment-methodologies/)
- [Philadelphia Office of Property Assessment](https://www.phila.gov/departments/office-of-property-assessment/)
- [Urban Displacement Project three-part methodology](https://www.urbandisplacement.org/wp-content/uploads/2021/07/udpaustin_methodology.pdf)
- [HUD USER: Mapping Gentrification methodology](https://www.huduser.gov/portal/periodicals/cityscape/vol26num1/ch20.pdf)
- [Gentrification and Residential Mobility in Philadelphia](https://pmc.ncbi.nlm.nih.gov/articles/PMC5450830/)

