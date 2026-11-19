# Week 4 five-ZIP screen and two-ZIP case-study calculation notes

## Scope and selection

The five-ZIP presentation screen contains **19132, 19143, 19122, 19138, and
19119**. Medians across all qualifying Philadelphia ZIP/ZCTA candidates define
the market-growth and vulnerability quadrants. **19132 and 19143** are retained
as the detailed case studies because both pass the coverage gate and occupy the
high-growth, high-vulnerability quadrant. The other three candidates provide
one comparison in each remaining quadrant: 19138 is higher growth/lower
vulnerability, 19122 is lower growth/higher vulnerability, and 19119 is lower
growth/lower vulnerability under the current citywide median thresholds.

The scorecard uses the following evidence:

- Philadelphia RTT: at least 30 eligible single-property sales in every year
  from 2012 through 2024;
- Redfin/ACS income: common coverage from 2012 through 2024 and adequate 2015
  and 2024 Redfin activity;
- market pressure: 2015-2024 nominal Redfin median-price CAGR;
- vulnerability: the mean citywide percentile of renter share, renter cost
  burden, poverty, and senior share in the 2020-2024 ACS release; and
- uncertainty: retained ACS 90% margins of error, with warnings at a 10
  percentage-point MOE for rate measures or 20% relative MOE for income.

`tableau_data/week04_zip_selection_scorecard.csv` contains the result for every
available Philadelphia 191xx ZIP/ZCTA, not only the chosen pair.

`tableau_data/week04_five_zip_transaction_activity.csv` contains annual eligible
RTT sale counts and transactions per 1,000 occupied housing units for the five
presentation candidates. The rate uses 2024 ACS occupied units as a fixed
denominator; it is a market-activity measure, not direct evidence of involuntary
displacement.

Multiplying by 1,000 is only a readable scaling convention. For example, a
rate of 50 means an average of about five eligible sales per 100 occupied
units. It does not mean that 1,000 properties were sampled or that 5% of
households moved: properties may transact more than once, and the measure does
not identify household movement.

The presentation chart uses a horizontal dumbbell design: each ZIP/ZCTA has
one row on a shared transaction-rate scale, with connected dots for the
2015-2017 and 2022-2024 three-year averages. This replaces the earlier faceted
version so absolute rates and changes can be compared without switching scales.

## Research-language boundary

The project theme is **housing pressure and potential displacement risk**.
Gentrification is a broader neighborhood-change process that normally requires
evidence of market change together with socioeconomic and demographic change.
The current ZIP-level descriptive measures can identify conditions consistent
with pressure, but they cannot establish that gentrification occurred or that
particular households were displaced.

## Main panel fields

### Why FRED appears in the build

The three core housing and community sources remain Philadelphia RTT, Redfin,
and the ACS. FRED contributes only the monthly CPIAUCSL consumer-price index,
which is averaged by year and used to express sale prices and household income
in constant 2024 dollars. This implements the Week 4 requirement to distinguish
real growth from nominal growth.

CPI does **not** affect the 2015-2024 ZIP-selection CAGR, ACS vulnerability
measures, nominal price-to-income ratio, or sale-to-assessment ratio. Removing
FRED would leave those results unchanged; only the inflation-adjusted dollar
fields and preliminary real price/income trend would be unavailable.

| Field group | Definition |
|---|---|
| `redfin_median_sale_price` | Annual median of Redfin rolling 90-day All Residential median-sale-price observations. It is not a median of ordinary monthly transactions. |
| `redfin_price_2024_dollars` | Redfin nominal price multiplied by 2024 annual-average CPIAUCSL divided by that year's annual-average CPIAUCSL. |
| `median_household_income` | ACS five-year B19013 estimate, labeled by the release's final year. |
| `income_2024_dollars` | ACS nominal income converted to 2024 dollars using the same CPI calculation. |
| `price_to_income_ratio` | Redfin median sale price divided by ACS median household income for the same release year. Descriptive screening measure only. |
| `renter_share`, `homeowner_share` | ACS B25003 renter- or owner-occupied units divided by occupied units. |
| `renter_cost_burden` | ACS B25070 cash-renter households spending at least 30% of income on gross rent, excluding cases where the ratio cannot be computed. |
| `severe_renter_cost_burden` | ACS B25070 cash-renter households spending at least 50% of income on gross rent, with the same denominator. |
| `owner_cost_burden` | ACS B25091 owner households spending at least 30% of income on selected monthly owner costs, combining owners with and without mortgages and excluding not-computed cases. |
| `poverty_rate` | ACS B17001 population below poverty divided by population for whom poverty status is determined. |
| `senior_share` | Sum of ACS B01001 male and female age-65-plus cells divided by total population. |
| `recent_mover_share` | One minus ACS B07003 share living in the same house one year earlier. This is mobility, not direct evidence of displacement. |
| `*_moe` | ACS 90% margin of error. Component MOEs are combined by square-root-of-summed-squares; subset ratios use the Census ratio approximation with a conservative fallback. |

## Coverage and interpretation

The keyless, reproducible ACS vulnerability build uses Census table-based bulk
files for 2021-2024. Earlier years remain blank for the added vulnerability
fields unless a teammate deliberately rebuilds with a `CENSUS_API_KEY`; the
Redfin/ACS income panel still covers 2012-2024. ACS five-year releases overlap,
so adjacent annual rows must not be interpreted as independent samples.

ACS one-year estimates are not published for ZCTAs. The five-year product is
therefore the appropriate ACS source for the ZIP/ZCTA comparisons in this
project. A one-year ACS estimate may be used only as separately labeled
Philadelphia citywide context; it cannot replace the ZCTA-level five-year
series.

ZIP and ZCTA are not identical geographies. Every ACS join is therefore
labeled as a ZIP/ZCTA approximation. The Philadelphia benchmark in the
preliminary chart is the median across qualifying Philadelphia ZIP rows, not a
transaction-weighted city estimate.

## Assessment calculation and decision gate

The RTT parcel table contains `assessed_value`, but it does not identify the
assessment year represented by that value. For the project record, Week 4 now
reproduces the method from the previously presented citywide chart: exact DEED,
single-property, non-nominal, known-price, non-outlier sales beginning in 2014;
calculate `total_consideration / assessed_value` for each eligible property and
then report the annual ZIP median and interquartile range. Results are saved in
`tableau_data/week04_sale_to_assessment.csv` and an internal PNG.

The output still sets `publish_sale_to_assessment = FALSE` because the chart has
already been presented and the RTT file cannot independently prove assessment-
year alignment. It remains an appendix diagnostic. Reuse as a main finding
should join a year-specific OPA source. The ratio describes assessment
alignment; it does not prove mortgage availability, political intent, a tax-
bill increase, or affordability.

## Week 4 presentation output

`Week_04_Housing_Pressure_and_Displacement_Risk.pptx` is the eight-slide Week 4
presentation in the project root. It includes the five-ZIP selection screen,
the two detailed case studies, the transaction-activity replacement for the
main sale-to-assessment slide, limitations, next steps, and technical speaker
notes. The sale-to-assessment chart is retained only in the appendix.
