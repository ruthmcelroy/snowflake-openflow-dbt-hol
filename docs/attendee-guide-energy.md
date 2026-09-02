# Energy: your lab guide

Everything you need, in order, with the minutes it should take. If you fall
behind, every section tells you how to skip without breaking anything.

**Your business question:**

> What is our exposure to commodity prices, and what is our fleet costing us
> when it breaks?

**Your safety net, before anything else.** Your raw data is already in this
repo as a seed — nothing to sync, nothing that can be slow. If you break
something you can't undo, re-fork `github.com/hicham-bab/snowflake-openflow-dbt-hol`
and set up again. It takes under a minute and nothing else in the lab needs
to change.

**Two things about this data, up front, because they will save you time:**

1. **The price series ends 2022-11-04.** When you ask questions later, say "in
   2022". Ask about this year and you get a correct, empty answer that looks
   broken.
2. **Your two maintenance feeds are the same data.** More on this in section 3,
   and it is the most interesting thing in the track.

---

## Section 1: fork, pick, accounts (8 min)

1. Fork `github.com/hicham-bab/snowflake-openflow-dbt-hol` to your own account.
2. You have picked energy. You will work only in `projects/energy`.
3. Get your accounts sorted: [account-setup.md](account-setup.md).
4. Set up the dbt platform properly: **[../dbt/setup.md](../dbt/setup.md)**.
   That page is the one setup you cannot skip, and it covers the field below.

**Expected result:** a fork under your GitHub username, and a dbt platform
account connected to Snowflake and to your fork, with the project subdirectory
set to `projects/energy`.

### The one setting you must not skip

This repo holds three separate dbt projects. The dbt platform has no way to know
you picked energy until you tell it.

When you create your dbt platform project, find the field called **Project
subdirectory** and type exactly this into it:

```
projects/energy
```

**Where it is:** dbt platform, **Account settings** then **Projects**, open your
project, **Edit**, under the repository settings. If you already created the
project without it, go back and add it now; you can change it any time.

**Why it matters:** leave it blank and dbt looks in the repo root, finds no
`dbt_project.yml`, and every command fails with
`Could not find dbt_project.yml` (including `dbt seed`, which will report no
seeds found). This is the most common setup mistake in the lab and it costs
people ten minutes.

> ![dbt platform project settings with the Project subdirectory field set to projects/energy](../assets/dbt-01-project-subdirectory.png)
>
> *The Project subdirectory field in dbt platform project settings, filled in
> with `projects/energy`.*

---

## Section 2: point dbt at your data, load it, first green build (18 min)

**Prerequisite:** your dbt platform project is created, connected to Snowflake
and to your fork, with the project subdirectory set to `projects/energy`.
If any of that is not true, do **[../dbt/setup.md](../dbt/setup.md)** first. It
takes 15 minutes and nothing below works without it.

### 2.1 Install packages

```bash
dbt deps
```

### 2.2 Load your raw data

```bash
dbt seed
```

**Expected result:** four seeds load in a few seconds — no account or sync
required. Three are this track's raw tables, shipped in the repo as CSVs
under `projects/energy/seeds/`:

| Table | Rows |
|---|---|
| `commodity_prices` | 5,898 |
| `fts_records` | 750 |
| `loglynx` | 750 |

The fourth, `commodity_reference.csv`, is a lookup of the 23 commodities with
their human-readable names, asset-class groups and quoted units. It is a seed
rather than a `CASE` statement so a trader can add a commodity by editing a
CSV.

In production, the three raw tables above would land continuously via
**Openflow** rather than a one-time seed — see
[../openflow/openflow-overview.md](../openflow/openflow-overview.md) if
you're curious why the lab doesn't run that live.

### 2.3 Build staging

```bash
dbt build --select staging
```

**Expected result. CHECKPOINT 1: this must be green.**

```
Completed successfully
Done. PASS=45 WARN=0 ERROR=0 SKIP=0 TOTAL=45
```

Three staging models and their tests. Nothing in staging is booby trapped;
if this is red, it's almost certainly the project subdirectory — go back to
step 1, or re-fork if you're not sure what you changed.

### 2.4 Look at what you built, and notice two absences

```sql
select count(*) from stg_commodity_prices;
-- 5897, not 5898
```

One row disappeared. The source has a row for 2000-01-03 where every price is
null. Staging drops it, because it is not a trading day for our purposes and it
would show up as a gap in every chart.

```sql
select count(*) as total, count(gasoline) as gasoline_populated from stg_commodity_prices;
-- 5897, 4414
```

Gasoline is missing on about 1,483 days. Its series simply starts later than
the others. There is deliberately no `not_null` test on it: you cannot test for
something the source does not have.

---

## Section 3: dbt Studio and Fusion tour (8 min)

Follow the instructor. Open `models/marts/vw_energy_data_quality.sql`. It is a
chain of small CTEs, built that way so you can poke at it.

**3.1 Hover a column.** Put your cursor over `maintenance_cost` in the `fts`
CTE. Fusion tells you the type without running anything.

**3.2 Break something on purpose.** Change `{{ ref('stg_fts_records') }}` to
`{{ ref('stg_fts_record') }}`. The error appears before you run. Change it back.

**3.3 Preview one CTE.** Put your cursor inside `maintenance_overlap` and
preview just that.

**Expected result: 750.**

Stop and look at that number. `maintenance_overlap` counts events that appear
in **both** the field technician feed and the LogLynx feed. There are 750
events in each feed. So the overlap is not partial. It is total.

**3.4 Build it and read the scorecard.**

```bash
dbt build --select vw_energy_data_quality
```

```sql
select * from vw_energy_data_quality order by data_quality_score;
```

**Expected result:** two rows. Commodity prices score well. Maintenance logs
score badly, and the reason is that every single maintenance event is reported
twice.

### Why this matters more than it looks

`loglynx` is not a second set of maintenance events. It is a mirror of
`fts_records`. All 750 record IDs appear in both, and not one row differs on
any column. Two systems reporting the same physical work, because a platform
migration was started and never finished.

If you union the two feeds and stop there:

- Total maintenance cost goes from about $410,000 to about $820,000
- Total downtime hours doubles
- Every average stays exactly the same, so nothing looks odd
- Nothing errors, nothing warns, and every chart renders fine

That is the failure mode worth fearing. Not the query that breaks, the one that
does not.

Open `models/intermediate/int_energy_maintenance_logs_unioned.sql`. It unions
both feeds and then de-duplicates on `record_id`, with the field technician
system as system of record. The `source_system` column survives on every row,
so you can always prove which feed a surviving record came from, and
`feed_count` records how many systems saw it.

`tests/assert_maintenance_logs_are_deduplicated.sql` is the alarm on that door.

---

## Section 4: dbt Wizard (25 min), the main event

### 4.1 Break the build

```bash
dbt build
```

**Expected result: it fails.** Four things in this project are deliberately
broken. You are going to fix them by talking to the agent, not by reading the
answers.

Three failures in this first run:

| What fails | What the error looks like |
|---|---|
| `int_energy_commodity_prices_unpivoted` | invalid identifier `'CRUDE_OIL'` |
| `energy_maintenance_cost_by_type` | not a valid group by expression |
| a test on `energy_maintenance_logs` | `accepted_values` on `maintenance_status`, got 1 result |

### 4.2 Fix them with dbt Wizard

Open the dbt Wizard panel. For each failure, open the failing file first so the
agent has context, then prompt it.

**Bug 1.** Open `models/intermediate/int_energy_commodity_prices_unpivoted.sql`.

> The UNPIVOT in this model fails with `invalid identifier 'CRUDE_OIL'`. Check
> the column list against what `stg_commodity_prices` actually produces and fix
> the wrong one.

**Expected:** the agent finds that the unpivot list names `crude_oil`, that no
such column exists, and that the intended column is `wti_crude`.

**Bug 2.** Open `models/marts/energy_maintenance_cost_by_type.sql`.

> This model fails with a group by error. Work out whether the extra column
> belongs in the group by or should not be selected at all, given the model is
> documented as one row per maintenance type.

**Expected:** the agent notices `maintenance_status` is selected but not
grouped. The right fix is to **remove it**, not to add it to the `group by`:
the model's stated grain is one row per maintenance type, and grouping by
status as well would change the grain and break the contract and the unique
test downstream.

**This is worth pausing on.** There are two ways to make the error go away and
only one of them is correct. The agent may suggest either. You know the
intended grain because it is documented at the top of the file; the agent is
inferring. This is what reviewing the diff is for.

**Bug 3.** Open `models/marts/_energy__marts.yml`.

> The accepted_values test on maintenance_status fails with one result. Find
> which value is missing from the test and decide whether to add it to the test
> or treat it as bad data.

**Expected:** `Cancelled` is a real, legitimate status present in 165 rows and
listed in the source documentation. It was simply left out of the test. The fix
is to add it.

### 4.3 Review before you accept, every time

dbt Wizard proposes a diff. **Read it before accepting.** The agent writes the
code; you stay accountable for it. Bug 2 in particular has a wrong fix that
compiles perfectly.

### 4.4 Run again, meet the fourth

```bash
dbt build
```

**Expected result:** a new failure that could not appear before, because its
model would not compile.

```
This model has an enforced contract that failed.
```

`energy_commodity_price_history` produces `commodity_code`, and its contract
declares a column called `commodity`.

> The contract on energy_commodity_price_history fails. Compare the columns the
> model produces with the columns the contract declares, and fix the mismatch.

**The lesson:** a contract is a separate promise about the shape of a table.
Change the model and you have to change the promise too, deliberately, in a
diff someone can review. If it had not failed here, a downstream consumer would
have found out instead.

### 4.5 Green

```bash
dbt build
```

**Expected result:** everything passes, including
`assert_maintenance_logs_are_deduplicated` and
`assert_commodity_prices_cover_every_commodity`.

### 4.6 Build something from intent (10 min)

Repair is only half of what the agent is for.

> Create an intermediate model called `int_energy_price_volatility` that
> calculates, for each commodity and calendar year, the average price, the
> standard deviation of price, and the ratio of the two as a coefficient of
> variation. Read `int_energy_commodity_prices_unpivoted` for the pattern and
> follow the same layout and commenting style.

Review it. Then:

> Add data-quality tests and column descriptions for the new model, then run
> them.

And a metric:

> Add a MetricFlow metric to `models/marts/_energy__marts.yml` for total maintenance
> cost per piece of equipment, as a derived metric.

**Expected result:** a new model, tests, and a metric, all written by the agent
and reviewed by you.

**Behind? Skip 4.6.** Fixing the four bugs is what matters.

---

## Section 5: the semantic layer, defined twice (10 min)

Open these side by side:

- `models/marts/sv_energy_commodity_prices.sql` and
  `models/marts/sv_energy_equipment_reliability.sql`, Snowflake Semantic Views
- `models/marts/_energy__marts.yml`, dbt Semantic Layer specs (MetricFlow).
  Scroll to the `semantic_model:` and `metrics:` blocks under each mart. Under
  the latest spec these live beside the contract rather than in their own file;
  `models/semantic/README.md` explains why.

**First, why energy has two Semantic Views and the other tracks have one.**
Commodity trading and equipment maintenance share no key. Putting them in one
object would hand Cortex Analyst a join it cannot make and let it answer
questions that have no answer. One object per subject area is the honest shape,
and recognising when two things are genuinely unrelated is a modelling skill.

| | Snowflake Semantic View | dbt Semantic Layer |
|---|---|---|
| Where the definition lives | in Snowflake, as an object | in this repo, in git |
| Created by | `dbt build`, via the Snowflake-Labs package | nothing created in the warehouse |
| Read by | Cortex Analyst | any MetricFlow client, and Snowflake CoWork via the dbt MCP Server |
| Changed by | editing the dbt model, then rebuilding | editing the YAML, then a pull request |

**Now find the honest difference.** `sv_energy_commodity_prices.sql` defines:

```sql
prices.price_volatility AS STDDEV(prices.settlement_price)
```

Look for the equivalent in `models/marts/_energy__marts.yml`. **It is not there.**
MetricFlow has no standard-deviation aggregation. The comment at the top of the
YAML says so explicitly.

That is not a bug in either product. It is what "the same business, expressed
in two systems" actually looks like, and it is exactly the kind of thing worth
knowing before you promise a stakeholder that two layers are equivalent.

Build them:

```bash
dbt build --select sv_energy_commodity_prices sv_energy_equipment_reliability
```

---

## Section 6: ship it to production (8 min)

### 6.1 A production job

In the dbt platform, create a job:

- Command: `dbt build`
- **Enable "generate docs on run"**. Not optional: the next section
  depends on it
- Target the production environment

Run it. **Expected result:** green, and a docs site with your DAG. Your DAG has
a genuinely interesting shape: two independent branches that never meet.

### 6.2 Run it again and watch dbt State

Trigger the same job again without changing anything.

**Expected result:** the second run is substantially shorter. dbt State compares
against the previous run and skips models whose inputs have not changed.

Worth a moment: your commodity price mart is roughly 133,000 rows built from a
23-column unpivot and two window functions. Rebuilding it when nothing changed
is pure waste. On a project with 2,000 models on an hourly schedule, that waste
is the difference between a warehouse bill you can defend and one you cannot.

**Make sure this job targets your production environment.** dbt Catalog, in
the next section, only shows metadata from a deployment environment marked
production or staging, and only after a job there has succeeded. If you skipped
creating that environment, go back to
[../dbt/setup.md](../dbt/setup.md) step 5 now; it takes two minutes.

---

## Section 7: dbt Catalog, the metadata the agent will use (8 min)

Full walkthrough: [../dbt/catalog-tour.md](../dbt/catalog-tour.md). The short
version is here.

One fact makes this section worth your time:

> **dbt Catalog and the dbt MCP Server read the same metadata, through the same
> Discovery API.**

Catalog is that metadata rendered for a human. The MCP Server hands it to an
agent. So before you ask an AI anything, this is where you find out what it is
actually going to know.

Open **Catalog** from the top navigation.

### 7.1 Lineage

Click **Explore Lineage**. This is the DAG you built: two branches that never touch, because commodity prices and equipment
maintenance share no key. You can see the reason for two semantic views rather
than one.

Try the **lenses** control and colour the graph by model layer, then by
materialization. Your views and tables separate instantly.

### 7.2 A model page

Open `energy_maintenance_logs`.

**Status bar:** last run, materialization, row count. Check the row count reads
750.

**General tab:** your description, local lineage, test results, and a
**Details** section. Look at Details: it shows **contracted status**. Your marts
show as contracted, because you enforced contracts on them in section 4. The
contract is not just a build-time guard, it is a published fact anyone can look
up.

**Columns tab:** every column with its name, data type, description, tags and
per-column test results.

### 7.3 The point

Find `is_reported_by_both_feeds` in the Columns tab and read its description:

*"True when both source systems reported this event. In this data set that is
every row, which is the finding the track is built around."*

That sentence is the difference between an agent that knows the maintenance
numbers were de-duplicated and one that finds the raw feeds and doubles every
cost in the business.

That description is not documentation hygiene. It is the agent's context.

Now scroll for a column with a thin description or none. That is a gap the
agent will feel too.

**Expected result:** you can point at the exact metadata an AI will use, and
say whether it is good enough. If you want a good AI experience on your data,
the work is not in the prompt. It is in the descriptions, tests, contracts and
metric definitions, which is to say it is in the pull request.

> **Empty Catalog?** No successful job run in a production or staging
> environment. **Columns tab empty?** The job did not run `dbt docs generate`.
> Both are section 6 problems; fix and re-run.

> **On plans:** column-level lineage and model performance are Enterprise+ only,
> so a trial account may not show them. Everything above works on all plans.

---

## Section 8: ask, and act, in English — Snowflake CoWork (25 min)

You just saw, in Catalog, exactly what metadata exists. Now watch an agent use
it.

### 8.1 Snowflake Semantic View, via Cortex Analyst (hands-on)

Open the `HOL_ENERGY_ANALYST` agent in Snowflake CoWork
(`TODO: verify` — this guide was written under the "Snowflake Intelligence"
name at `ai.snowflake.com`; confirm the current URL and any UI changes with
the Snowflake team before relying on this). It has both Semantic Views
attached as separate tools and routes between them.

1. What was the average natural gas price **in 2022**?
2. Show me the Brent crude price trend through 2022.
3. Which commodity had the largest single-day loss, and when?
4. Which equipment has the highest maintenance cost?
5. What is our cost per hour of downtime by maintenance type?
6. What share of our maintenance work is unplanned?
7. Which technicians have the highest average downtime per job?

**Then deliberately ask a bad question:** *"What is the natural gas price this
year?"*

**Expected result:** a well-configured agent tells you the series ends in
November 2022 and offers the latest available period instead. A badly
configured one returns an empty table and looks broken. The difference is three
lines of agent instruction, and it is the cheapest reliability work you will
ever do.

**Then ask about the 2020 oil crash:** *"What was the lowest WTI crude price
ever recorded?"*

**Expected result:** -37.63, on 2020-04-20. Negative. That is real; oil futures
genuinely settled below zero that day. The model deliberately has no positivity
test on `wti_crude`, and `price_change_pct` divides by the absolute previous
price so the percentage survives the sign change. Good data quality is not the
same as making the data look tidy.

### 8.2 CoWork beyond Q&A

`TODO (Snowflake team): this subsection is a placeholder.` Snowflake CoWork's
pitch is broader than answering questions — it's described as reasoning
across your data, automating routine tasks, and acting in the tools your
business already uses. Everything in 8.1 only exercises the Q&A half. If
there's a governed action worth showing here (a maintenance alert, a ticket,
a written-back field, tied to `unplanned_work_rate` or one of the price
metrics above), this is where it goes.

### 8.3 dbt Semantic Layer, via the dbt MCP Server — now inside CoWork too

The dbt MCP Server exposes your MetricFlow metrics as tools an AI agent can
call, so the agent asks dbt for `unplanned_work_rate` rather than writing its
own SQL. Registering that server directly inside Snowflake's agent surface
**used to be blocked** by an OAuth mismatch — fixed on August 24, 2026, so
this is a real part of the lab now, not a workaround.

**If your facilitator has wired it in** (check — it depends on whether the
room shares one dbt platform account), connect once: in CoWork's connector
settings, find the dbt connector and select **Connect**, sign in to dbt
platform, and approve. Then ask the same question you asked Cortex Analyst
and compare. If it isn't wired in for this room, your instructor will demo it
instead — the setup binds to one dbt host, so it isn't something everyone
configures individually in two minutes.

Full instructions, with the exact SQL: [dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md).

**The takeaway:** when the agent answers through the semantic layer, it is
constrained to metrics somebody defined and reviewed. When it writes its own
SQL, it is not. In this track that is the difference between an agent that
knows maintenance events were de-duplicated and one that finds `stg_loglynx`
and doubles your costs.

---

## Section 9: wrap up (5 min)

Seeded raw data to a governed, AI-queryable semantic layer in under two hours:

- Raw data loaded as a seed, matching what a real Openflow pipeline would
  land continuously
- A typed, tested staging layer, and a seed a trader can maintain
- A wide-to-long unpivot turning 23 price columns into a proper fact
- A union that de-duplicates, and a test that keeps it honest
- Two contracted marts, a strategy rollup, and a scorecard that caught the
  duplicate feed
- Four bugs diagnosed and fixed by an agent you reviewed
- The same metrics defined two ways, including one that could not be
- Natural-language answers grounded in definitions somebody owns
- A production job with docs generation, and dbt State skipping unchanged work
- A tour of dbt Catalog, so you know exactly what metadata an agent can see
- A reviewable pull request

**The thing worth remembering:** two systems reported the same 750 maintenance
events, and unioning them would have doubled every cost in the business with no
error, no warning and no visible symptom. The only defence was somebody looking
at the data and writing down what they found. No amount of AI on top fixes a
model that is quietly wrong underneath.

---

### Open a pull request

Commit in dbt Studio and open a pull request against your fork. **Do not
merge.** The point is that everything you did today arrives as a reviewable
diff, including the contract change.

---

### Next

- Read `projects/energy/README.md` for the model-by-model tour
- Try the CPG or financial services track
- Add your own industry: [adding-an-industry.md](adding-an-industry.md)
