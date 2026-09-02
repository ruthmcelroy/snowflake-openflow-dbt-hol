# Consumer packaged goods: your lab guide

Everything you need, in order, with the minutes it should take. If you fall
behind, every section tells you how to skip without breaking anything.

**Your business question:**

> Where are we losing money on this range, and is it a demand problem or a
> supply problem?

**Your safety net, before anything else.** Your raw data is already in this
repo as a seed — nothing to sync, nothing that can be slow. If you break
something you can't undo, re-fork `github.com/hicham-bab/snowflake-openflow-dbt-hol`
and set up again. It takes under a minute and nothing else in the lab needs
to change.

---

## Section 1: fork, pick, accounts (8 min)

1. Fork `github.com/hicham-bab/snowflake-openflow-dbt-hol` to your own account.
2. You have picked consumer packaged goods. You will work only in
   `projects/cpg`.
3. Get your accounts sorted: [account-setup.md](account-setup.md).
4. Set up the dbt platform properly: **[../dbt/setup.md](../dbt/setup.md)**.
   That page is the one setup you cannot skip, and it covers the field below.

**Expected result:** a fork under your GitHub username, and a dbt platform
account connected to Snowflake and to your fork, with the project subdirectory
set to `projects/cpg`.

### The one setting you must not skip

This repo holds three separate dbt projects. The dbt platform has no way to know
you picked consumer packaged goods until you tell it.

When you create your dbt platform project, find the field called **Project
subdirectory** and type exactly this into it:

```
projects/cpg
```

**Where it is:** dbt platform, **Account settings** then **Projects**, open your
project, **Edit**, under the repository settings. If you already created the
project without it, go back and add it now; you can change it any time.

**Why it matters:** leave it blank and dbt looks in the repo root, finds no
`dbt_project.yml`, and every command fails with
`Could not find dbt_project.yml` (including `dbt seed`, which will report no
seeds found). This is the most common setup mistake in the lab and it costs
people ten minutes.

> ![dbt platform project settings with the Project subdirectory field set to projects/cpg](../assets/dbt-01-project-subdirectory.png)
>
> *The Project subdirectory field in dbt platform project settings, filled in
> with `projects/cpg`.*

---

## Section 2: point dbt at your data, load it, first green build (18 min)

**Prerequisite:** your dbt platform project is created, connected to Snowflake
and to your fork, with the project subdirectory set to `projects/cpg`.
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

**Expected result:** `cpg_records` loads in a couple of seconds — no account
or sync required. This track's raw data ships in the repo as a CSV under
`projects/cpg/seeds/`.

```sql
select count(*) from cpg_records;
-- 750
```

In production, this pipeline would land this table continuously with
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
Done. PASS=24 WARN=0 ERROR=0 SKIP=0 TOTAL=24
```

One model (`stg_cpg_records`) and its tests. Nothing in staging is booby
trapped; if this is red, it's almost certainly the project subdirectory — go
back to step 1, or re-fork if you're not sure what you changed.

### 2.4 Look at what you built

```sql
select * from stg_cpg_records limit 20;
```

Notice what staging did. `order_date` was a VARCHAR in the raw feed because the
source Postgres column is `text`; it is a real `DATE` now.
`price_optimization_flag` was the string `'TRUE'`; it is a boolean called
`is_price_optimized`. And `customer_ltv` was renamed to
`customer_lifetime_value`, which will matter in about fifteen minutes.

---

## Section 3: dbt Studio and Fusion tour (8 min)

Follow the instructor. Open `models/marts/vw_cpg_data_quality.sql`. It is
built as a chain of small CTEs specifically so you can poke at it.

**3.1 Hover a column.** Put your cursor over `stockout_rate` in the `base` CTE.
Fusion tells you the type without running anything, because it has parsed the
whole project and knows what staging produced.

**3.2 Break something on purpose.** Change `{{ ref('stg_cpg_records') }}` to
`{{ ref('stg_cpg_record') }}`. The error appears immediately, before you run
anything. Change it back.

**3.3 Preview one CTE.** Put your cursor inside the `consistency` CTE and
preview just that. You get its output without building the model.

**3.4 Now build it and read the result.**

```bash
dbt build --select vw_cpg_data_quality
```

```sql
select * from vw_cpg_data_quality order by data_quality_score;
```

**Expected result:** 10 rows, one per product category. Completeness and
validity score 100. Consistency scores around 74, and that is the interesting
part. Three things drag it down:

- **192 cancelled orders still carry a value** in `order_total`. Anyone summing
  `order_total` overstates revenue by about a quarter. That is why the mart has
  a separate `recognised_revenue` column.
- **8 products have a rating above 4.5 from fewer than 10 reviews.**
- **373 orders were placed after the price optimisation that supposedly
  informed them.**

None of these are bugs in the code. They are real properties of the data, and
the scorecard exists to make them visible rather than letting them turn up in
somebody's board pack.

---

## Section 4: dbt Wizard (25 min), the main event

### 4.1 Break the build

```bash
dbt build
```

**Expected result: it fails.** Four things in this project are deliberately
broken. You are going to fix them by talking to the agent, not by reading the
answers.

You should see three failures in this first run:

| What fails | What the error looks like |
|---|---|
| `int_cpg_order_performance` | invalid identifier `'CUSTOMER_LTV'` |
| `cpg_product_inventory_health` | invalid identifier `'INVENTORY_COVERAGE_RATE'` |
| a test on `vw_cpg_data_quality` | `Got 10 results, configured to fail if != 0` |

### 4.2 Fix them with dbt Wizard

Open the dbt Wizard panel in dbt Studio. For each failure, open the failing
file first so the agent has context, then prompt it.

**Bug 1.** Open `models/intermediate/int_cpg_order_performance.sql`.

> This model fails with `invalid identifier 'CUSTOMER_LTV'`. Look at the
> staging model it selects from and find and fix the issue.

**Expected:** the agent finds that `stg_cpg_records` renames the raw
`customer_ltv` to `customer_lifetime_value`, and proposes that change.

**Bug 2.** Open `models/marts/cpg_product_inventory_health.sql`.

> This model fails with `invalid identifier 'INVENTORY_COVERAGE_RATE'`. Check
> the column names `int_cpg_inventory_health` actually produces and fix it.

**Expected:** the agent finds `inventory_coverage_ratio` in the intermediate
model and corrects the near-miss name.

**Bug 3.** Open `models/marts/_cpg__marts.yml`.

> The accepted_range test on data_quality_score fails for all 10 categories.
> Look at the actual scores and tell me whether the data is wrong or the
> threshold is wrong, then fix whichever it is.

**Expected:** the agent works out that real scores sit around 91 to 92, that
nothing is wrong with the data, and that a minimum of 95 was never achievable.
The right fix is a threshold the business can actually hold to, around 85.

**This is the important one to think about.** A failing test does not always
mean the data is broken. Sometimes the test is the thing that is wrong, and
deciding which is a judgement call the agent should help you make, not make for
you.

### 4.3 Review before you accept, every time

dbt Wizard proposes a diff. **Read it before accepting.** This is the whole
point of the exercise: the agent writes the code, you stay accountable for it.

On bug 3 in particular, the agent may suggest several thresholds. It does not
know your data contract. You do.

### 4.4 Run again, meet the fourth

```bash
dbt build
```

**Expected result:** a new failure that could not appear before, because its
model would not compile.

```
This model has an enforced contract that failed.
```

`cpg_order_performance` produces `customer_lifetime_value` and its contract
expects `customer_ltv`.

> The contract on cpg_order_performance fails. Compare the columns the model
> produces with the columns the contract declares, and fix the mismatch.

**This is the lesson bug 1 was setting up.** You renamed the column in the
model. The contract is a separate promise about the shape of that table, and it
has to be updated too. That is not friction; it is the contract doing its job.
If it had not failed, a downstream consumer would have found out instead.

### 4.5 Green

```bash
dbt build
```

**Expected result:** everything passes.

```
Completed successfully
```

### 4.6 Build something from intent (10 min)

Repair is only half of what the agent is for. Now build something new.

> Create an intermediate model called `int_cpg_price_opportunity` that flags
> products where a price decrease was recommended, the product has high
> elasticity (above 0.7) and stockout risk is Low. Read
> `int_cpg_inventory_health` for the pattern and follow the same layout and
> commenting style.

Review what it produces. Then:

> Add data-quality tests and column descriptions for the new model in
> `_cpg__marts.yml`, then run them.

And a metric:

> Add a MetricFlow metric to `models/marts/_cpg__marts.yml` for the average price
> elasticity of products flagged as a price opportunity.

**Expected result:** a new model, tests, and a metric, all written by the agent
and reviewed by you. Note how much of the surrounding convention it picked up
from the existing files: that is why the project comments so heavily.

**Behind? Skip 4.6.** Fixing the four bugs is the section that matters.

---

## Section 5: the semantic layer, defined twice (10 min)

Open these two files side by side:

- `models/marts/sv_cpg_commercial_performance.sql`, a Snowflake Semantic View
- `models/marts/_cpg__marts.yml`, dbt Semantic Layer specs (MetricFlow).
  Scroll to the `semantic_model:` and `metrics:` blocks under each mart. Under
  the latest spec these live beside the contract rather than in their own file;
  `models/semantic/README.md` explains why.

They describe the same business. Find `total_recognised_revenue` in both.

| | Snowflake Semantic View | dbt Semantic Layer |
|---|---|---|
| Where the definition lives | in Snowflake, as an object | in this repo, in git |
| Created by | `dbt build`, via the Snowflake-Labs package | nothing is created in the warehouse |
| Read by | Cortex Analyst | any MetricFlow client, and Snowflake CoWork via the dbt MCP Server |
| Changed by | editing the dbt model, then rebuilding | editing the YAML, then a pull request |
| Also usable from | anything that can query Snowflake | any tool that speaks to the dbt Semantic Layer |

**The question is not which one wins.** It is where the definition of revenue
should live and who else needs to read it. If everything you own is in
Snowflake, the Semantic View is closer to the data. If revenue also has to mean
the same thing in a BI tool, a notebook and a Slack bot, the definition wants
to live upstream of all of them.

Notice the synonyms in the Semantic View:

```sql
orders.total_recognised_revenue AS SUM(orders.line_recognised_revenue)
    WITH SYNONYMS = ('revenue', 'net revenue', 'recognised revenue')
    COMMENT = 'Sum of order value excluding cancelled orders. Use this for revenue.'
```

Those are not documentation. That is how Cortex Analyst maps somebody typing
"how much revenue" onto the right column rather than onto `total_order_value`,
which would be wrong by about a quarter.

Build it:

```bash
dbt build --select sv_cpg_commercial_performance
```

---

## Section 6: ship it to production (8 min)

### 6.1 A production job

In the dbt platform, create a job:

- Command: `dbt build`
- **Enable "generate docs on run"**. Not optional: the next section
  depends on it
- Target the production environment

Run it. **Expected result:** green, and a docs site with your DAG.

### 6.2 Run it again and watch dbt State

Trigger the same job a second time without changing anything.

**Expected result:** the second run is substantially shorter, because dbt State
compares against the previous run and skips models whose inputs have not
changed.

That is the whole idea, and it is worth a moment. On a project this size it
saves seconds. On a project with 2,000 models and an hourly schedule, it is the
difference between a warehouse bill you can defend and one you cannot. You are
not paying to rebuild things that did not change.

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

Click **Explore Lineage**. This is the DAG you built: one source fanning out into two parallel branches that rejoin at the semantic
view.

Try the **lenses** control and colour the graph by model layer, then by
materialization. Your views and tables separate instantly.

### 7.2 A model page

Open `cpg_order_performance`.

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

Find `recognised_revenue` in the Columns tab and read its description:

*"Value of the order line in USD, zero for cancelled orders. Use this rather
than order_total when reporting revenue."*

That sentence is the difference between an agent that reports revenue correctly
and one that overstates it by about a quarter, because 192 cancelled orders
still carry a value.

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

Open the `HOL_CPG_ANALYST` agent in Snowflake CoWork
(`TODO: verify` — this guide was written under the "Snowflake Intelligence"
name at `ai.snowflake.com`; confirm the current URL and any UI changes with
the Snowflake team before relying on this).

Try these:

1. Which product categories have the highest stockout rate?
2. What is our total recognised revenue by product category?
3. What is the average order value for high-value customers compared with
   low-value customers?
4. How many products need planner review, and which categories are they in?
5. What is our cancellation rate, and does it differ by customer segment?
6. Which product categories have the best average product rating?
7. **Compare total order value with total recognised revenue by month.**

**Question 7 is the one to sit with.** The two numbers differ by about a
quarter, and the gap is the 192 cancelled orders. The agent gets that right
only because the Semantic View says so in a comment. Nothing about the raw data
would have told it.

**Expected result:** answers with the SQL the agent generated shown alongside.
Read the SQL. It is querying your semantic view, not guessing at table names.

### 8.2 CoWork beyond Q&A

`TODO (Snowflake team): this subsection is a placeholder.` Snowflake CoWork's
pitch is broader than answering questions — it's described as reasoning
across your data, automating routine tasks, and acting in the tools your
business already uses. Everything in 8.1 only exercises the Q&A half. If
there's a governed action worth showing here (a notification, a ticket, a
written-back field, tied to one of the metrics above), this is where it goes.

### 8.3 dbt Semantic Layer, via the dbt MCP Server — now inside CoWork too

The dbt MCP Server exposes your MetricFlow metrics as tools an AI agent can
call, so the agent asks dbt for `total_recognised_revenue` rather than writing
its own SQL against a table. Registering that server directly inside
Snowflake's agent surface **used to be blocked** by an OAuth mismatch — fixed
on August 24, 2026, so this is a real part of the lab now, not a workaround.

**If your facilitator has wired it in** (check — it depends on whether the
room shares one dbt platform account), connect once: in CoWork's connector
settings, find the dbt connector and select **Connect**, sign in to dbt
platform, and approve. Then ask the same question you asked Cortex Analyst
and compare. If it isn't wired in for this room, your instructor will demo it
instead — the setup binds to one dbt host, so it isn't something everyone
configures individually in two minutes.

Full instructions, with the exact SQL: [dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md).

**The thing to take away:** when the agent answers through the semantic layer,
it is constrained to metrics somebody defined and reviewed. When it writes its
own SQL, it is not. That difference is the entire argument for a governed
semantic layer, and it does not depend on which of the two you pick.

---

## Section 9: wrap up (5 min)

Seeded raw data to a governed, AI-queryable semantic layer in under two hours:

- Raw data loaded as a seed, matching what a real Openflow pipeline would
  land continuously
- A typed, tested staging layer
- Two contracted marts, plus a data-quality scorecard that found three real
  problems in the data
- Four bugs diagnosed and fixed by an agent you reviewed
- The same metrics defined two ways, and a clear view of when to use each
- Natural-language answers grounded in definitions somebody owns
- A production job with docs generation, and dbt State skipping unchanged work
- A tour of dbt Catalog, so you know exactly what metadata an agent can see
- A reviewable pull request

**The thing worth remembering:** `order_total` and `recognised_revenue` are not
the same number, and nothing in the raw data tells you which one means revenue.
Somebody has to decide, write it down, and put it somewhere the AI can read.
That is what the last two hours were actually about.

---

### Open a pull request

Commit your changes in dbt Studio and open a pull request against your fork.
**Do not merge it.**

The point is not shipping. It is that everything you did today (the model
changes, the contract update, the new metric) arrives as a reviewable diff.
Including the contract change, which is exactly the kind of thing you want a
second pair of eyes on.

---

### Next

- Read `projects/cpg/README.md` for the model-by-model tour
- Try the energy or financial services track
- Add your own industry: [adding-an-industry.md](adding-an-industry.md)
