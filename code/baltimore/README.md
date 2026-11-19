# Baltimore peer-city comparison — stage 20

**Status:** included. `20_baltimore_comparison.R` runs the comparison on its own
(input `external_data/raw/baltimore_redfin_neighborhoods.csv`, outputs under
`tableau_data/` and `visualizations/`). It is deliberately **not** part of
`run_all.R`: it reads a different city, and nothing it produces enters the
Philadelphia semantic model.

**Applies to:** slide 10 of the final client presentation, and the Baltimore rows
of the Data Usage Report (Sections 3, 4, 5.2 and 6).

---

## 1. What the section is for

Philadelphia and Baltimore have comparable housing stock, poverty profiles and
pre-2000 building ages. The argument is **not** that Baltimore causes anything in
Philadelphia. It is that Baltimore is a plausible picture of where the same
pressure markers lead, and that the response tools a city reaches for — a
housing trust fund, community land trusts, a homestead assessment cap — already
exist there and can be read as a rehearsal.

Two rules carry over from the Philadelphia analysis and are not negotiable:

1. **Descriptive, not causal.** Neighborhood price change against a city
   benchmark is a comparison of stages.
2. **Pressure, not proof.** Nothing here establishes gentrification or
   household displacement in either city.

---

## 2. What it measures

| Item | Value |
|---|---|
| Neighborhoods | Remington, Union Square, Washington Village-Pigtown, Highlandtown, Patterson Park |
| Source | Redfin neighborhood market tracker, Baltimore MD metro area |
| Measure | Mean of the year's monthly `MEDIAN SALE PRICE NSA ($)` |
| Window | Calendar 2012 against calendar 2025, both complete years in the delivered file |
| Benchmark | Mean of every neighborhood median in the file (see §3) |
| Outputs | `external_data/baltimore_neighborhood_prices.csv`, `tableau_data/week07_baltimore_comparison.csv`, `visualizations/week07_baltimore_comparison.png` |

Delivered result:

| Neighborhood | 2012 | 2025 | Change |
|---|---:|---:|---:|
| Remington | $74,936 | $277,033 | +269.7% |
| Union Square | $65,900 | $213,571 | +224.1% |
| Washington Village-Pigtown | $63,952 | $206,329 | +222.6% |
| Highlandtown | $117,646 | $316,000 | +168.6% |
| Patterson Park | $121,654 | $299,560 | +146.2% |
| **Benchmark** | **$159,820** | **$284,961** | **+78.3%** |

---

## 3. What the benchmark is, and what it is not

The benchmark is the mean of **every neighborhood median in the metro file** —
305 neighborhoods, spanning Baltimore City, Baltimore County and Harford County.
It is not a citywide median: its 2012 level is $159,820 against roughly $92,000
for Baltimore City itself.

**Call it "the average Baltimore-area neighborhood". Do not call it "the city
average".**

Three limits follow and should travel with any ratio taken from this stage:

- **Geography.** Metro-wide, so it includes suburbs that are not comparable to
  the five city neighborhoods.
- **Composition.** 195 regions have 2012 data, 238 have 2025 data, 180 have both.
  The two years are not computed over the same basket.
- **Thin cells.** A year's price is the mean of that year's monthly medians, not
  an annual median. Union Square carries 4 months of 2012 data against 7 of 2025;
  Remington carries 11 against 12.

Consequence: the ratio of the five-neighborhood mean (+206%) to the benchmark
(+78.3%) is **2.6x**, and it is 2.5x if Union Square is dropped. It is not 2.5x
against a citywide median, which would put it nearer 1.6x–1.8x. If a single
multiplier is quoted, the benchmark it is measured against has to be named in the
same sentence.

---

## 4. What this stage does not cover

- **No commercial-investment series.** The presentation notes mention rising
  commercial investment in the five neighborhoods; no permit or commercial
  valuation data was delivered for Baltimore, so that claim has no dataset
  behind it in this package.
- **No Baltimore housing-stock inventory.** Nothing here counts assisted or
  income-restricted units, so it cannot say whether the five neighborhoods
  gained or lost affordable stock. The same limit is set out for Philadelphia in
  Appendix B.4 of the Data Usage Report.
- **No boundary file.** The neighborhoods are Redfin's definitions, not the
  City of Baltimore's official neighborhood boundaries.

---

## 5. How to run

```r
# from the project root, with external_data/raw/baltimore_redfin_neighborhoods.csv in place
source("code/baltimore/20_baltimore_comparison.R")
```

The script stops with the expected path if the input is missing. It does not
download anything.

---

## 6. Checklist before the section is quoted

- [ ] The benchmark is described as Baltimore-area, not city
- [ ] The window (2012, 2025) travels with the percentages
- [ ] Union Square's months of data are known if its figure is singled out
- [ ] No Baltimore key enters `dim_geography` or any `tableau_ingestion/` file
- [ ] No comparison is made between a Baltimore price and a Philadelphia price
