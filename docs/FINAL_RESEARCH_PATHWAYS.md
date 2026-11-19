# Potential Research Pathways for the Final Deliverable

**Status:** Options for group and client discussion; no final pathway has been
approved.  
**Current analysis period:** January 2000 through July 2026  
**Purpose:** Narrow the project to one decision-oriented research question while
preserving the work already completed.

## Decision the team needs to make

The final project should not attempt to complete two separate major studies.
The team should choose one primary pathway based on the decision the City wants
to support, the data that can be obtained, and the remaining project time.

Two viable pathways have emerged:

1. Forecast recorded property activity and optimize a limited audit or review
   allocation.
2. Map emerging housing-market pressure and potential displacement risk.

Both pathways can produce a useful geospatial deliverable. They differ mainly
in data burden, policy purpose, and the type of claim the analysis can support.

The current five-worksheet Tableau exercise should be retained as **Week 3
EDA**, not treated as the final dashboard architecture. It successfully tests
the prepared exports, but its sheets have different grains and do not respond
to one common geographic selection. The final dashboard should instead be
built around the research question, one decision, and one primary geography.

The team should build the dashboard for the selected pathway only. Combining
the two canvases below would mix an operational review-allocation decision with
a housing-policy monitoring decision and weaken both stories.

## Pathway A: Activity forecasting and audit-allocation optimization

### Potential research question

> How can Philadelphia use historical and forecasted property-transaction
> activity to allocate a limited number of audit or review opportunities across
> geographic areas while respecting workload, capacity, and coverage
> constraints?

The operational term **audit** must be confirmed with the client. It could mean
transfer-tax review, recording-quality review, housing inspection, or another
City workflow. The outcome, eligible population, and geographic assignment
will change depending on that definition.

### Analytical sequence

1. Measure deed and new-mortgage activity from 2000 through July 2026.
2. Identify seasonality, structural changes, disruptions, and recording delays.
3. Compare candidate forecasting methods using time-based holdouts.
4. Forecast short-term activity, preferably over 12 to 36 months rather than a
   highly uncertain 10- to 15-year operational horizon.
5. Estimate review opportunity or expected workload by ward, ZIP code, or
   another approved City geography.
6. Optimize the allocation of a fixed number of reviews subject to capacity,
   minimum-coverage, maximum-concentration, and fairness constraints.
7. Map the recommended allocation and show how it changes under alternative
   budgets or forecast scenarios.

### Final deliverables

- Citywide activity and disruption dashboard.
- Forecast-comparison table with holdout error measures and uncertainty bands.
- Geographic activity or opportunity map.
- Optimization model with a documented objective function and constraints.
- Recommended allocation under a base budget plus low- and high-capacity
  scenarios.
- Plain-language explanation of what the allocation does and does not imply.

### Recommended Tableau dashboard canvas

**Working title:** *Philadelphia Property Activity and Review Prioritization*  
**Primary user:** City program manager or operational analyst  
**Decision supported:** Where review opportunities are concentrated and how a
fixed review capacity could be distributed under the approved rules  
**Primary geography:** Philadelphia ward  
**Primary interaction:** Select one ward on the map; every ward-level view
updates to that selection

```text
+--------------------------------------------------------------------------+
| Philadelphia Property Activity and Review Prioritization                 |
| Year [2025 v]  Map metric [Deed activity v]  Capacity [Base v]  [Reset]  |
+------------------------------------------+-------------------------------+
|                                          | SELECTED WARD                 |
| Interactive Philadelphia ward map        | Ward 15                       |
|                                          | Deeds          1,240          |
| Color by selected metric                 | New mortgages    865          |
| Click a ward to update the dashboard     | Median price  $285K           |
|                                          | Nominal share   8.2%          |
|                                          | Proposed reviews   24          |
+------------------------------------------+-------------------------------+
| Selected ward activity over time         | Ward versus Philadelphia      |
| Deeds and mortgages; city comparison     | Rank, percentile, and delta   |
+------------------------------------------+-------------------------------+
| Forecast and capacity scenario           | Why this allocation?          |
| Citywide workload with uncertainty       | Opportunity, cap, floor,      |
| and stated link to the ward allocation   | concentration and assumptions |
+------------------------------------------+-------------------------------+
| Interpretation and limitations: review opportunity, not proven violation |
+--------------------------------------------------------------------------+
```

#### Canvas components

| Component | Question answered | Recommended implementation |
|---|---|---|
| Ward choropleth | Where is the selected metric concentrated? | Filled ward polygons; one sequential color scale; ward ID in Detail and tooltip |
| KPI cards | What is happening in the selected ward and year? | Deeds, new mortgages, eligible sales, correctly calculated median price, nominal-transfer share, and proposed reviews |
| Activity trend | Is the selected ward increasing, declining, or changing differently from the City? | Monthly or annual ward line plus a clearly distinguished citywide comparison or index |
| Ward comparison | How unusual is the selected ward? | Rank, percentile, or selected-ward-versus-city bars; do not show an unexplained cluster label alone |
| Forecast panel | What workload is expected and how uncertain is it? | Winning validated citywide model, prediction interval, holdout error, and forecast horizon |
| Allocation panel | What action follows from the evidence? | Recommended reviews, opportunity cap, minimum coverage, capacity scenario, and change from equal allocation |
| Explanation panel | Why did the model produce this result? | Plain-language rule summary and warning that the output is not evidence of fraud or guaranteed recovery |

#### Required dashboard interactions

1. Use the ward map as a **single-select filter action** for the KPI, trend,
   comparison, and allocation sheets.
2. Use a parameter for the map metric so the same map can switch among deed
   volume, mortgage volume, median eligible-sale price, recent growth,
   nominal-transfer share, and proposed allocation.
3. Use a single-year selector for the KPI cards. This avoids incorrectly
   averaging monthly or annual medians over an arbitrary date range.
4. Keep the full time series visible after a year is selected; highlight the
   selected year rather than removing the historical context.
5. Provide a visible reset control and state what happens when no ward is
   selected: the dashboard should return to Philadelphia totals, not a blank
   screen.
6. Use capacity scenarios such as low, base, and high only after R exports a
   separate validated solution for each scenario. A Tableau parameter must not
   imply that the optimization has been rerun when it has not.

Tableau supports filter actions from a selected mark to specified target
sheets, including mappings between fields in different relational sources.
Parameter actions can also let a map selection or control change a metric or
reference value. These should be used deliberately rather than turning every
sheet into a filter. See Tableau's documentation for [filter
actions](https://help.tableau.com/current/pro/desktop/en-us/actions_filter.htm)
and [parameter
actions](https://help.tableau.com/current/pro/desktop/en-us/actions_parameters.htm).

#### Recommended Tableau data model

```text
dim_ward_geometry (one row per ward)
    |-- fact_ward_year (ward x year)
    |-- fact_ward_month (ward x month)
    |-- fact_ward_allocation_scenario (ward x capacity scenario)
    `-- optional fact_ward_forecast (ward x forecast period x scenario)

dim_date relates to the year and month facts at their declared grains.
fact_citywide_forecast remains citywide unless a defensible ward-level forecast
or allocation bridge is explicitly created.
```

Use Tableau logical relationships on validated keys rather than one large
physical join. The City publishes [Political Wards boundary
data](https://opendataphilly.org/datasets/political-wards/), which can supply
the polygons missing from the current exports.

Current repository readiness:

- `tableau_data/fact_monthly_geo.csv` already supports ward-month deeds,
  mortgages, nominal activity, eligible activity, median price, and cluster.
- `tableau_data/dim_geo.csv` already supplies one row per ward with trajectory
  features and cluster assignments.
- `tableau_data/optimization_results.csv` already supplies one allocation row
  per eligible ward for the current base scenario.
- A new `fact_ward_year.csv` should calculate annual medians directly from
  eligible document-level sales. Do not average monthly medians to create an
  annual or selected-period median.
- A new allocation-scenario export is required before the capacity selector
  can show more than the current 1,000-review case.
- The current citywide forecast does not automatically become a ward forecast.
  The team must define and validate how forecasted workload affects ward-level
  allocations, or describe the two panels as related but separate evidence.

#### Intended audience takeaway

> The selected ward's recording activity and review-opportunity indicators can
> be compared with Philadelphia, and a limited review capacity can be allocated
> transparently under visible assumptions and constraints.

This is stronger than presenting an optimization number alone because the user
can see the geography, history, comparison, rule, and resulting action in one
decision flow.

### Why this pathway is not necessarily too simple

The value is not created by adding many unrelated models. It comes from a
coherent descriptive, predictive, and prescriptive chain:

```text
Historical activity -> validated forecast -> geographic workload estimate
-> constrained optimization -> operational recommendation
```

A credible implementation requires time-series validation, uncertainty,
integer optimization, sensitivity testing, geographic communication, and
transparent policy constraints. Those components can demonstrate substantial
analytical depth while still answering one understandable City question.

### Main caveat

The current transaction data do not contain confirmed audit outcomes or the
value recovered from an audit. Without those outcomes, the model cannot claim
to predict violations, fraud, or financial return per audit. In that situation,
the result must be described as **activity-based review opportunity or workload
allocation**, not audit-yield optimization.

The team should ask the client whether historical review outcomes, staffing
capacity, audit costs, recovered value, or priority rules are available. If
they are not available, the model can still allocate workload using transparent
proxies, but the limitation must be prominent.

## Pathway B: Housing-market pressure and displacement-risk mapping

### Potential research question

> Which Philadelphia neighborhoods show the greatest combination of
> housing-market pressure and resident vulnerability, and where should the City
> prioritize monitoring and anti-displacement resources over the next five
> years?

The analysis should use terms such as **emerging housing pressure** or
**potential displacement risk**. It should not state that a neighborhood will
become gentrified as though that outcome were certain.

### Analytical sequence

1. Use ZIP codes for an accessible overview of current price-to-income
   conditions.
2. Move the primary analysis to census tracts because ZIP codes can combine
   neighborhoods with materially different conditions.
3. Construct an existing-vulnerability dimension using measures such as
   household income, poverty, renter share, rent burden, and homeownership.
4. Construct a market-pressure dimension using changes in sale prices, rents,
   transactions, investor ownership, permits, and other available indicators.
5. Compare tract changes with the city or metropolitan-area trend so that
   general inflation or citywide growth is not misclassified as neighborhood
   transformation.
6. Validate the method retrospectively before producing a five-year risk tier.
7. Aggregate tract results to ZIP codes or planning districts for executive
   presentation and program coordination.

### Final deliverables

- Current ZIP-level affordability-pressure map.
- Tract-level vulnerability and market-pressure maps.
- Combined monitoring tiers with uncertainty and data-quality flags.
- Five-year emerging-risk scenario, with ten years shown only as a more
  uncertain sensitivity case if requested.
- Targeted recommendations for monitoring, housing preservation, resident
  outreach, or further investigation.

### Recommended Tableau dashboard canvas

**Working title:** *Philadelphia Housing Pressure and Vulnerability Explorer*  
**Primary user:** Housing-policy, planning, preservation, or community-engagement
staff  
**Decision supported:** Which areas warrant monitoring or further housing-policy
investigation, and which conditions are driving that priority  
**Primary geography:** Census tract; ZIP code or planning district only as an
executive roll-up  
**Primary interaction:** Select one tract on the map; all indicators, trends,
comparisons, and driver explanations update to that tract

```text
+--------------------------------------------------------------------------+
| Philadelphia Housing Pressure and Vulnerability Explorer                 |
| Period [2020-2024 v]  Lens [Combined risk v]  Tenure [All v]  [Reset]    |
+------------------------------------------+-------------------------------+
|                                          | SELECTED TRACT                |
| Interactive census-tract map             | Risk tier       Elevated      |
|                                          | Price/income        4.1x       |
| Color by combined tier, market pressure, | Price growth       32%         |
| vulnerability, or data quality           | Income growth      14%         |
|                                          | Rent burden        48%         |
|                                          | Renter share       61%         |
+------------------------------------------+-------------------------------+
| Market pressure versus vulnerability     | Indexed trends                |
| Four-quadrant scatter; selected tract    | Price, income, rent, City=100 |
+------------------------------------------+-------------------------------+
| Drivers of the selected tier             | Monitoring implication        |
| Indicator contribution / evidence bars   | Preserve, monitor, outreach,  |
| with margin-of-error and coverage flags  | investigate, or data gap      |
+------------------------------------------+-------------------------------+
| Interpretation: screening tool, not a prediction of displacement         |
+--------------------------------------------------------------------------+
```

#### Canvas components

| Component | Question answered | Recommended implementation |
|---|---|---|
| Tract choropleth | Where do measured market pressure and resident vulnerability overlap? | Toggle among combined tier, market pressure, vulnerability, and data-quality views |
| KPI cards | What conditions characterize the selected tract? | Price-to-income, price and income change, rent burden, renter share, poverty, tenure, and observation/MOE flags |
| Quadrant chart | Is the tract high on pressure, vulnerability, both, or neither? | Market-pressure dimension on one axis, vulnerability on the other; selected tract highlighted; city thresholds shown |
| Indexed trend | Are prices or rents separating from income? | Rebase series to 100 in a common approved base year; compare selected tract with Philadelphia |
| Driver panel | Why was the tract placed in this tier? | Show standardized indicator contributions or rule thresholds; never expose only an unexplained composite score |
| Monitoring implication | What response is appropriate? | Use non-punitive categories such as monitor, preservation review, resident outreach, program coordination, or insufficient evidence |
| Data-quality panel | How reliable is the signal? | ACS relative MOE, missing market observations, boundary/crosswalk status, and last refresh date |

#### Required dashboard interactions

1. Use the tract map as a single-select filter for KPI, quadrant, trend, driver,
   and data-quality sheets.
2. Use a metric parameter to switch the map among combined tier, pressure,
   vulnerability, affordability, and data quality without displaying five
   competing maps at once.
3. Allow selection from either the map or the quadrant chart; both should
   highlight the same tract.
4. Keep comparisons anchored to Philadelphia or an approved regional benchmark
   so citywide inflation is not presented as tract-specific change.
5. Make margins of error and incomplete coverage visible in tooltips and the
   data-quality panel rather than hiding unreliable estimates.
6. Provide ZIP or planning-district roll-ups for executive communication, but
   preserve tract-level analysis underneath. Do not assign one ZIP-level income
   value to every tract or ward inside that ZIP.

#### Recommended Tableau data model

```text
dim_tract_geometry (one row per stable tract geography)
    |-- fact_tract_acs_period (tract x ACS estimate period)
    |-- fact_tract_market_year (tract x year)
    |-- fact_tract_housing_signals (tract x year x indicator)
    |-- model_tract_pressure_tier (tract x scoring period x model version)
    `-- optional bridge_tract_program_area (tract x program geography)

dim_indicator documents direction, unit, source, transformation, weight,
margin-of-error rule, and interpretation for every component.
```

Current repository readiness:

- `tableau_data/fact_zip_price_income.csv` and the Week 3 price-to-income work
  provide a ZIP-level exploratory starting point, not the final tract model.
- The present Redfin/ACS match can support a contextual ZIP overview, but ZIPs,
  ZCTAs, wards, and census tracts must not be treated as interchangeable.
- Tract-level ACS, tract-compatible market signals, stable boundary files,
  crosswalks, inflation treatment, scoring rules, and retrospective validation
  are still required.
- A five-year risk tier should be presented as a monitoring scenario with
  uncertainty, not as a statement that a tract will gentrify.

#### Intended audience takeaway

> The selected tract shows a documented combination of market pressure,
> resident vulnerability, and data confidence that can guide monitoring and
> further investigation, but the dashboard does not predict individual
> displacement or establish causation.

Map-centered housing dashboards provide useful interaction precedents. The
[Colorado Housing and Finance Authority Gap
Map](https://public.tableau.com/app/profile/colorado.housing.and.finance.authority/viz/TheGapMap/TheGapMap)
uses an interactive geographic view for housing-affordability conditions, and
the U.S. Census Bureau's [housing-cost-ratio
map](https://public.tableau.com/app/profile/us.census.bureau/viz/MappingHousingCostRatiosintheUnitedStates/Nation_Rent)
demonstrates geographic exploration of cost burden. Zillow's dashboard catalog
separates its geographic [Market Explorer and affordability-focused
tools](https://www.zillow.com/research/dashboards/), supporting the decision to
keep general market activity and affordability as related but distinct user
questions.

### Additional data likely required

- Tract-level ACS income, poverty, rent, home value, education, tenure, and
  housing-cost-burden measures.
- Current census-tract boundary files and geographic crosswalks.
- Eviction, tax-delinquency, housing-quality, permits, code violations, and
  investor-ownership data where obtainable.
- Inflation adjustments and consistent geographic boundaries across time.

### Main caveat

This pathway has strong policy and visual appeal, but it requires substantially
more acquisition, cleaning, geographic reconciliation, variable definition,
and validation. ACS five-year estimates also overlap across annual releases
and carry sampling margins of error. A rushed implementation could create an
attractive map without enough evidence to support the recommendation.

The current Redfin, ACS ZCTA, and Philadelphia transfer analysis provides a
foundation, but it is not sufficient by itself to predict gentrification or
displacement.

## Side-by-side decision summary

| Decision factor | Pathway A: Activity and allocation | Pathway B: Housing pressure and displacement risk |
|---|---|---|
| Primary City use | Operational workload or review allocation | Housing monitoring and anti-displacement targeting |
| Fit with existing code | High | Moderate |
| Additional data burden | Low to moderate; high if audit-yield modeling is required | High |
| Remaining implementation risk | Moderate | High |
| Geographic output | Ward, ZIP, planning district, or approved operational unit | Census tract first; ZIP or planning-district roll-up |
| Predictive horizon | Prefer 12-36 months | Prefer five years; ten years as sensitivity only |
| Prescriptive component | Constrained integer allocation | Program-priority tiers rather than a precise allocation unless costs and capacities are available |
| Primary limitation | No confirmed audit outcome or return field in the current data | More datasets, spatial harmonization, and a sensitive outcome definition |
| Risk of appearing too simple | Manageable if forecast validation and optimization are rigorous | Lower visually, but complexity can exceed the available time |

## Dashboard design lessons from public examples

The examples below are design references, not sources for the project's
metrics, thresholds, or conclusions.

- The City of Philadelphia's [Housing Action Plan
  dashboard](https://www.phila.gov/departments/department-of-planning-and-development/about/our-results/housing-action-plan-dashboard/)
  connects measures to defined program goals and explains important category
  definitions. The final project should similarly define every KPI and connect
  it to a decision or recommendation.
- Philadelphia's [Atlas](https://atlas.phila.gov/) uses search-and-select
  geography as the entry point to property information. Pathway A can borrow
  that interaction logic at ward level without trying to reproduce a
  parcel-level property system.
- Zillow separates market exploration, monthly snapshots, affordability, rent,
  and other housing decisions into purpose-specific dashboards rather than one
  overloaded canvas. The project should likewise select one primary pathway
  for the final dashboard.
- Tableau recommends purposeful filters, tooltips, and actions as dashboard
  interactions. A map selection should update only the views required to
  understand the selected geography; interactivity is not useful merely
  because a worksheet can be made clickable. See Tableau's [visual best
  practices](https://help.tableau.com/current/blueprint/en-us/bp_visual_best_practices.htm).

Across both pathways, the dashboard should show a visible title, decision
question, refresh period, selected geography, sample/coverage note, source
note, reset control, and interpretation boundary. The final presentation can
then use a static screenshot for the main finding and a short live interaction
to demonstrate how the City would investigate one selected area.

## Provisional recommendation for group discussion

Present both pathways, but do not promise both as full final analyses.

- Treat **Pathway A** as the lower-risk primary option because it uses the
  strongest existing data and creates a complete descriptive-predictive-
  prescriptive story.
- Strengthen Pathway A with a geographic allocation map, scenario comparison,
  forecast backtesting, and explicit operational constraints so the result is
  more than a simple activity forecast.
- Present **Pathway B** as the higher-effort, policy-oriented alternative. Move
  it into the final scope only if the group accepts the data workload and the
  client confirms that displacement-risk targeting is the more valuable
  decision.
- If the group selects Pathway A, the existing affordability maps can remain
  contextual EDA or a recommended future extension rather than becoming a
  second competing research project.

## Questions for the team and client

1. What exact City decision should the final analysis change?
2. What does an audit or review mean operationally, and what records are
   eligible?
3. Are historical audit outcomes, recovered value, staff capacity, or review
   costs available?
4. Which geography matches the decision: ward, ZIP, planning district, census
   tract, or parcel?
5. Is the preferred horizon operational and short-term, or policy-oriented and
   five to ten years?
6. Does the team have enough time and ownership capacity to acquire and verify
   the additional displacement-risk datasets?
7. Which pathway can be validated convincingly before the final presentation?

The final choice should be recorded in `docs/DECISION_LOG.md` after the group
and client confirm the objective, geography, horizon, and available data.
