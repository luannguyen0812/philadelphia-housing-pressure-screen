# Baltimore comparison — evidence pack for slide 10

**Built:** 19 November 2026 · **Deck:** `Presentation Decks/BSAN 710_Group 4_Final Client Presentation.pptx`, slide 10
**Purpose:** verify what the slide asserts, so the section can be finished without waiting on the
person who built it. Every row below is either *verified with a source* or *not reconstructable
from the repo*.

Read the "Action" column as the edit the slide needs, not as a comment.

---

## 1. Claim-by-claim

### 1.1 "Housing age, poverty rates, tenure of resident, and proximity align with Philadelphia"

**Verified.** Census QuickFacts, ACS 2020–2024 five-year:

| Indicator | Baltimore city | Philadelphia | Gap |
|---|---:|---:|---:|
| Owner-occupied housing unit rate | 47.5% | 51.8% | 4.3 pts |
| Poverty rate | 19.7% | 21.4% | 1.7 pts |
| Median household income | $62,177 | $61,953 | $224 |
| Median value, owner-occupied units | $229,600 | $243,100 | $13,500 |
| Median gross rent | $1,331 | $1,397 | $66 |
| Median year structure built | 1949 | — (state-level figure is 1956; city figure not in QuickFacts) | — |

**Action.** Put three of these numbers on the slide. "Align" is currently an assertion; with
income within $224, poverty within 1.7 points and rent within $66 it becomes an argument. Drop
"housing age" unless the Philadelphia median year built is pulled from ACS B25035 — the Baltimore
figure is solid (1949), the Philadelphia one is not in the source used here.

---

### 1.2 "5 comparable Baltimore neighborhoods — median sales price increased 2.5x more than the city average"

**The five, named 19 Nov:** Remington, Union Square, Washington Village-Pigtown, Highlandtown,
Patterson Park.

**The 2.5x does not reproduce.** Two independent sources were run, and neither supports it. Data
in `docs/baltimore_five_neighborhoods.csv`.

*Zillow ZHVI (Zillow neighbourhood boundaries, typical home value):*

| Region | 2012 | 2025-10 | 2012–2025 |
|---|---:|---:|---:|
| Baltimore city | 88,798 | 192,354 | +116.6% |
| Remington | 69,604 | 237,748 | +241.6% |
| Washington Village-Pigtown | 80,405 | 176,684 | +119.7% |
| Highlandtown | 125,427 | 272,360 | +117.1% |
| Patterson Park | 128,452 | 264,973 | +106.3% |
| Union Square | n/a (series starts Nov 2015) | 179,930 | +89.9% over 2015–2025, against +68.8% for the city |

*BNIA "Median Price of Homes Sold" by Community Statistical Area (the City's own indicator, 2012–2023):*

| Region | 2012 | 2023 | 2012–2023 |
|---|---:|---:|---:|
| Benchmark: median of 55 CSAs | 92,000 | 210,000 | +128.3% |
| Hampden/Remington CSA | 144,600 | 303,500 | +109.9% |
| Poppleton/Terraces/Hollins Market CSA (Union Square) | 69,000 | 185,000 | +168.1% |
| Pigtown/Carroll Park CSA | 92,000 | 185,000 | +101.1% |
| Highlandtown CSA | 220,000 | 365,000 | +65.9% |
| Patterson Park North & East CSA | 162,200 | 260,000 | +60.3% |

**Ratios against the city:** Zillow 2012–2023, four-neighbourhood mean +140.8% against +112.9%,
**1.25x**. Zillow 2015–2025, five-neighbourhood mean +60.9% against +68.8%, **0.88x**. BNIA
2012–2023, five-CSA mean +101.1% against +128.3%, **0.79x**.

**Why a group average cannot be 2.5x, and why that is arithmetic rather than opinion.** Percentage
growth is inversely related to the base. In 2012 these five were priced between $69.6k and $128.5k
against a city value of $88.8k, so the two cheapest, Remington and Pigtown, carry the largest
percentage gains and the two most expensive, Highlandtown and Patterson Park, carry the smallest.
Only Remington reaches roughly twice the city rate (+241.6% against +116.6%). Any average that
includes the two high-base neighbourhoods must fall well below 2.5x.

**What does hold.** Every one of the five roughly doubled or better between 2012 and 2025, and all
five sit at or above the city's typical value. The finding is a gradient, not a multiplier: the
cheapest neighbourhood more than tripled, the two most expensive roughly doubled.

**Caveat on both sources.** The Zillow series uses Zillow's neighbourhood boundaries; BNIA
aggregates the neighbourhoods into Community Statistical Areas (Remington sits inside
Hampden/Remington, Union Square inside Poppleton/The Terraces/Hollins Market, Patterson Park inside
Patterson Park North & East). Neither is the City's official neighbourhood boundary. If the 2.5x
came from a boundary-level series held by the slide's author, that series should be produced before
the number is used, because two sources that bracket the question both disagree with it.

**Where the number probably came from.** A retired formulation of the slide read *"+196% for the
neighborhoods against +78% for Baltimore"*, and 196 ÷ 78 = 2.51. Two things follow. First, that is a
ratio of two percentage increases, so it reads as "2.5 times as fast", not "2.5 times more" — the
phrase on the slide overstates it even on its own arithmetic. Second, the +78% city figure matches
FHFA's Baltimore city index for 2014 Q1 → 2024 Q3 (+78.8% on Zillow's city series, +62.5% on FHFA),
so the old sentence was probably a 2014–2024 window, not 2012–2025. The +196% does not match
anything measured here; the highest 2014–2024 figure among the five is Remington at +84.3%.

**City benchmark, from the project's own file** (`tableau_data/fact_quarterly_peer_hpi.csv`,
FHFA all-transactions city index) — still the defensible two-city comparison:

| Window | Baltimore | Philadelphia |
|---|---:|---:|
| 2012 Q1 → 2025 Q3 | +72.5% | +93.8% |
| 2014 Q1 → 2024 Q3 | +62.5% | +82.1% |

Note what this says: over both windows **Philadelphia rose faster than Baltimore**. A slide that
implies Baltimore is the high-growth case study is arguing against its own benchmark.

**Action.** Replace the multiplier with the measured gradient in the table above, or use the FHFA
two-city comparison. Do not present "2.5x" in any form.

---

### 1.3 "Community Land Trusts … provide framework for Philadelphia"

**Verified, and stronger than the slide says.** The City of Baltimore awarded **$750,000 to each of
three land trusts in March 2021**: McElderry Park / Broadway East, Belair Edison, and Curtis Bay.
The operating entities include Charm City Land Trusts (McElderry Park), Broadway East Community
Land Trust and South Baltimore Community Land Trust (Curtis Bay). Maryland's Department of Housing
and Community Development also maintains a registry that formally recognises land trusts.

**Action.** Name them. "Community land trusts" as a category is a slogan; three named trusts funded
at $750,000 each in a comparable city is evidence.

---

### 1.4 "Affordable Housing Trust Act"

**Wrong instrument name — this needs fixing.** Baltimore's Affordable Housing Trust Fund is a
**City Charter amendment (Article I, §14, November 2016)**, operationalised by **Ordinance 18-215
in 2018**. It is not a state act, and calling it one invites the question of which act.

The charter amendment is a lockbox and it carries a reporting duty: an annual public report on
units produced by tenure, income level and bedroom count, plus a four-year CPA audit. The record
since:

| Fact | Value |
|---|---|
| Received since FY2019 | ~$111 million |
| FY2022 revenue | $23.3 million |
| FY2022 disbursements | $903,000 |
| FY2022 closing cash | $40.5 million |
| Unspent balance | ~$46.5 million, three years running |
| Average annual spend | under $6 million, about 12% of the unspent balance |
| Annual reports FY2023–FY2025 | missing until a reporter asked in October 2026 |

**Action.** This is the most useful paragraph available for the slide, and it cuts in the same
direction as the report's own language: revenue raised is not housing produced. It is the Baltimore
version of the project's flow-versus-stock problem.

---

### 1.5 "Property Tax Protections (4% per year)"

**True, but changing.** The Baltimore City homestead property tax credit caps annual taxable
assessment growth at 4%. Maryland permits up to 10%, so 4% is a City choice and therefore a policy
lever. On **15 June 2026 the City Council approved raising the cap from 4% to 5%**.

**Action.** Say "4%, raised to 5% in 2026" or drop the number. A slide that says "4% per year" in
November 2026 is quoting a rule that has just been amended.

---

### 1.6 "Just Cause policies provide framework for Philadelphia"

**Not accurate as presented.** Baltimore City has **no just-cause eviction law**. What exists:

- A City Council **resolution dated 24 February 2025** urging the Maryland General Assembly to pass
  statewide just-cause legislation (HB 744 / SB 462, with a county opt-in). The bill **did not pass**;
  it died in Senate committee in April 2025.
- The City's own rental-property-disposition ordinance was **held unconstitutional by the Fourth
  Circuit in 2024**, and the City agreed in **October 2026 to pay $11 million** to settle claims from
  landlords affected by it.
- What Baltimore *has* enacted is a rental licensing and registration regime (Strengthening Renters'
  Safety Act, effective 1 January 2026) — inspection and registration, not eviction protection.

**Action.** Reword to "statewide just cause has been proposed but not enacted", or swap the third
pillar for the rental-registration regime, which is real and in force. Do not leave an audience with
the impression that Baltimore protects tenants through just cause. The $11 million settlement is
also the honest counter-example: a tenant-protection ordinance can fail in court.

---

## 2. What is still missing, and what it would take

| Missing | Who has it | Status |
|---|---|---|
| The five neighborhood names | Supplied 19 Nov | **Resolved** |
| Their price series and the window | Rebuilt from Zillow ZHVI and BNIA | **Done** — see 1.2 |
| The boundary series behind "2.5x" | The slide's author | **Outstanding.** Two sources disagree with the number; if a third exists it has to be produced. |
| What "2.5x" multiplied | The slide's author | **Moot** unless the source appears — the measured ratios are 0.79x to 1.25x |

The comparison no longer needs a new selection rule: the five are fixed, and the rebuild used
Zillow's neighbourhood boundaries with BNIA's CSA aggregation as a second, independent check.

---

## 3. Suggested slide-10 rewrite (uses only verified content)

> **Why Baltimore.** Owner-occupied 47.5% against 51.8% in Philadelphia. Poverty 19.7% against
> 21.4%. Median household income $62,177 against $61,953. Median gross rent $1,331 against $1,397.
> *(Census ACS 2020–2024)*
>
> **What happened there.** Baltimore city's typical home value rose 116.6% between 2012 and 2025.
> In the five neighborhoods the range was wider: Remington more than tripled (+241.6%) while
> Highlandtown and Patterson Park roughly doubled (+117.1% and +106.3%). The gradient follows the
> starting point — the cheapest neighborhood gained most. *(Zillow ZHVI, Jan 2012 – Oct 2025)*
>
> **What the City did.** A charter-locked Affordable Housing Trust Fund — $111M raised since 2019,
> about $46.5M still unspent, average annual spend under $6M. Three community land trusts funded at
> $750,000 each in 2021. A 4% homestead assessment cap, raised to 5% in June 2026.
>
> **What it teaches.** Money in a trust is not housing on the ground, and a tenant-protection
> ordinance can lose in court. The transferable lesson is the reporting discipline, not the statute.

---

## 4. Sourcing note

Figures above come from Census QuickFacts (ACS 2020–2024), the FHFA city index already in
`tableau_data/fact_quarterly_peer_hpi.csv`, Baltimore City Council reporting on the homestead
credit (June 2026), reporting on the Affordable Housing Trust Fund and its missing annual reports
(October 2026), the Abell Foundation's summary of the 2025 just-cause resolution, and Maryland DHCD's
land-trust registry. **None of these were verified against the primary documents** — charter text,
Ordinance 18-215, Bill 26-0151, and the FY2023–FY2025 trust reports. Confirm the trust-fund and
homestead figures against the City's own pages before the numbers go on a slide.

---

## 5. Audit of the supplied script and file (19 Nov)

**Input:** `redfin_blt_final.csv` — 29,814 rows, 305 neighbourhoods, `Neighborhood` region type,
metro `Baltimore, MD metro area`, Jan 2012 – Jun 2026. Copied into the repo as
`external_data/raw/baltimore_redfin_neighborhoods.csv`.

**Reproduced.** The script's arithmetic runs clean and produces its own numbers exactly:

| Neighbourhood | 2012 | 2025 | Change |
|---|---:|---:|---:|
| Remington | $74,936 | $277,033 | +269.7% |
| Union Square | $65,900 | $213,571 | +224.1% |
| Washington Village-Pigtown | $63,952 | $206,329 | +222.6% |
| Highlandtown | $117,646 | $316,000 | +168.6% |
| Patterson Park | $121,654 | $299,560 | +146.2% |
| *Mean of five* | | | **+206.2%** |
| "Baltimore average" | $159,820 | $284,961 | **+78.3%** |

206.2 ÷ 78.3 = 2.63, which is the "2.5x more than the city average" on the slide, and the +78%
matches the retired "+78% for Baltimore". The code is not broken; the two numbers are measuring
different things.

**Defect 1 — the denominator is not the city.** `baltimore_overall` groups by every region in the
file and averages them, so the benchmark is an unweighted mean across **305 metro-area
neighbourhoods**, including suburbs in Baltimore County and Harford County (Abingdon, Belcamp,
Bulle Rock, Catonsville Manor, Constant Friendship). Its 2012 level, $159,820, is far above the
City's own median of about $92,000 — so the comparison is five city neighbourhoods against a
metro-wide mean, not against Baltimore.

**Defect 2 — the basket changes between the two years.** 195 regions have 2012 data, 238 have 2025
data, and only 180 appear in both. 58 neighbourhoods enter between the two years and 15 drop out,
so the 2012 average and the 2025 average are not computed over the same set.

**Defect 3 — "median sale price" per year is a mean of twelve monthly medians.** The script
averages `MEDIAN SALE PRICE NSA` across the months rather than taking a period median. In thin
markets a monthly median is noisy: `Union Square` has **4 months of data in 2012 against 7 in
2025**, so its +224% rests on four versus seven monthly figures. Remington has 11 months in 2012.

**Defect 4 — a mean of five percentages over-weights the cheapest.** Pigtown and Union Square
start at roughly $64-66k and contribute the largest percentage gains with the least price weight.
The mean of the five changes is not the change of the five neighbourhoods taken together.

**The ratio is not stable across defensible choices.** Holding the five neighbourhoods fixed:

| Benchmark | Benchmark growth | Ratio to +206% |
|---|---:|---:|
| Metro, unweighted (the script) | +78.3% | **2.6x** |
| Metro, sales-weighted | +60.1% | 3.4x |
| Baltimore City, Zillow ZHVI | +116.6% | 1.8x |
| Baltimore City, FHFA index | +72.5% | 2.8x |
| Median of 55 City CSAs (BNIA) | +128.3% | 1.6x |
| Five neighbourhoods on Zillow ZHVI, 2012–2023 | +140.8% | 1.25x |

A number that moves between 1.25x and 3.4x depending on the benchmark is not a finding; it is a
choice. **Do not put a multiplier on the slide.**

**What survives every version.** Each of the five roughly doubled or better between 2012 and 2025,
the cheapest (Remington) roughly tripled, and all five sit at or above the City's typical value.
That is the claim to make.
