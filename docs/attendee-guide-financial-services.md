# Financial services: your lab guide

Everything you need, in order, with the minutes it should take. This is the
flagship track: same two hours, richer data, and the only one where governance
does real work.

**Your business question:**

> Where is our credit risk concentrated, is it getting worse, and can we let an
> AI agent answer that without handing it anyone's social security number?

**Your safety net, before anything else.** Your raw data is already in this
repo as a seed — nothing to sync, nothing that can be slow. If you break
something you can't undo, re-fork `github.com/hicham-bab/snowflake-openflow-dbt-hol`
and set up again. It takes under a minute and nothing else in the lab needs
to change.

**Three things about this data, up front:**

1. **Several columns look numeric and are text**, with empty strings where the
   value is unknown. A plain `cast()` on any of them takes the model down.
2. **The `loan` table carries twelve personal-data columns**, and six of them
   are redundant copies of two actual identifiers. That is the governance beat.
3. **The risk star is clean.** 250 customers, 20 institutions, 700
   relationships, 25,200 monthly assessments, zero orphans. The joins are safe.

---

## Section 1: fork, pick, accounts (8 min)

1. Fork `github.com/hicham-bab/snowflake-openflow-dbt-hol` to your own account.
2. You have picked financial services. You will work only in
   `projects/financial_services`.
3. Get your accounts sorted: [account-setup.md](account-setup.md).
4. Set up the dbt platform properly: **[../dbt/setup.md](../dbt/setup.md)**.
   That page is the one setup you cannot skip, and it covers the field below.

**Expected result:** a fork under your GitHub username, and a dbt platform
account connected to Snowflake and to your fork, with the project subdirectory
set to `projects/financial_services`.

### The one setting you must not skip

This repo holds three separate dbt projects. The dbt platform has no way to know
you picked financial services until you tell it.

When you create your dbt platform project, find the field called **Project
subdirectory** and type exactly this into it:

```
projects/financial_services
```

**Where it is:** dbt platform, **Account settings** then **Projects**, open your
project, **Edit**, under the repository settings. If you already created the
project without it, go back and add it now; you can change it any time.

**Why it matters:** leave it blank and dbt looks in the repo root, finds no
`dbt_project.yml`, and every command fails with
`Could not find dbt_project.yml` (including `dbt seed`, which will report no
seeds found). This is the most common setup mistake in the lab and it costs
people ten minutes.

> ![dbt platform project settings with the Project subdirectory field set to projects/financial_services](../assets/dbt-01-project-subdirectory.png)
>
> *The Project subdirectory field in dbt platform project settings, filled in
> with `projects/financial_services`.*

---

## Section 2: point dbt at your data, load it, first green build (18 min)

**Prerequisite:** your dbt platform project is created, connected to Snowflake
and to your fork, with the project subdirectory set to
`projects/financial_services`. If any of that is not true, do
**[../dbt/setup.md](../dbt/setup.md)** first. It takes 15 minutes and nothing
below works without it.

### 2.1 Install packages

```bash
dbt deps
```

### 2.2 Load your raw data

```bash
dbt seed
```

**Expected result:** eight tables load in a few seconds, no account or sync
required — this track's raw data ships in the repo as CSVs under
`projects/financial_services/seeds/`.

| Table | Rows |
|---|---|
| `risk_assess_customers` | 250 |
| `risk_assess_financial_institutions` | 20 |
| `risk_assess_risk_profiles` | 700 |
| `risk_assess_performance_metrics` | 700 |
| `risk_assess_monthly_assessments` | 25,200 |
| `loan` | 3,000 |
| `predict_term_deposit` | 3,000 |
| `fpr_records` | 750 |

Yours is the biggest track by row count, roughly 33,000 rows total, and it
still loads in seconds.

In production, this pipeline would land these same tables continuously with
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
Done. PASS=88 WARN=0 ERROR=0 SKIP=0 TOTAL=88
```

Eight staging models and their tests, including referential integrity tests
proving the star has no orphans. Nothing in staging is booby trapped.

**If it is red:** it's almost certainly the project subdirectory. Re-check
step 1, or re-fork if you're not sure what you changed.

### 2.4 Read the governance model before anything else

Open `models/staging/stg_loan.sql` and read the comment block at the top. It is
long on purpose. It is the most important thing in this track.

The source table has 118 columns. This model selects 20. Twelve of the excluded
ones are personal data, and the interesting part is that they are **redundant**:

| Columns in the source | What they actually are |
|---|---|
| `social_security_number`, `ssn`, `ssnumber` | the identical value on every row |
| `ssnumber1` | a fourth SSN-shaped column with a *different* value |
| `drivers_license`, `dl` | the identical value on every row |
| `member_id` | a second person identifier alongside `id` |
| `emp_title`, `title`, `c_desc` | free text written by members of the public |
| `zip_code` | first three digits; a re-identification vector with state and income |
| `c_url` | a URL containing the loan id |

Six identity columns, two actual identifiers. **Drop `ssn` and stop, and you
have shipped the same number twice more under two other names.** PII removal is
a de-duplication problem before it is a deletion problem, and that is not
obvious until you check.

Now look at `stg_risk_assess_customers.sql`. `customer_name` is not selected;
instead there is `customer_name_hash`, an md5. It joins, and it cannot be read
back. Note the honest caveat in the comment: md5 on a low-cardinality field is
a join key, not a security control. Real masking is a Snowflake masking policy
applied by the platform team.

### 2.5 See the type traps for yourself

```sql
select count(*) as total,
       count(collateral_quality_score) as collateral_known,
       count(liquidity_ratio) as liquidity_known
from stg_risk_assess_risk_profiles;
-- 700, roughly two thirds known on each
```

Roughly two thirds of rows are NULL on each. Those columns are `text` in the
source with empty strings for unknown, and `stg_risk_assess_risk_profiles` uses
`try_cast` rather than `cast`. `cast()` would throw
`Numeric value '' is not recognized` and take the model down.

**The rule:** use `cast()` when a failure to convert is a bug you want to hear
about. Use `try_cast()` when the source is genuinely allowed to be blank. You
are about to see what happens when you get that wrong.

---

## Section 3: dbt Studio and Fusion tour (8 min)

Follow the instructor. Open `models/marts/vw_fs_data_quality.sql`. Yours scores
four domains rather than two.

**3.1 Hover a column.** Put your cursor over `debt_to_income_ratio` in the
`customers` CTE. Fusion tells you the type without running anything.

**3.2 Break something on purpose.** Change `{{ ref('stg_loan') }}` to
`{{ ref('stg_loans') }}`. The error appears before you run. Change it back.

**3.3 Preview one CTE.** Put your cursor inside `risk_profile_checks` and
preview just that.

**3.4 Build it and read the result.**

```bash
dbt build --select vw_fs_data_quality
```

```sql
select * from vw_fs_data_quality order by data_quality_score;
```

**Expected result:** four rows. Risk relationships scores worst, and the driver
is the completeness gap on those three text-typed columns. That is a **control
finding**, not a data bug: two thirds of relationships have no collateral
assessment on file. A risk committee would want to know that. Coalescing it to
zero would have hidden it.

---

## Section 4: dbt Wizard (25 min), the main event

### 4.1 Break the build

```bash
dbt build
```

**Expected result: it fails.** Four things in this project are deliberately
broken. Unlike the other tracks, all four surface at once, because your DAG
branches cleanly.

| What fails | What the error looks like |
|---|---|
| `int_fs_monthly_risk_enriched` | `Numeric value '' is not recognized` |
| `fs_loan_portfolio` | enforced contract failed |
| a test on `fs_risk_relationship_summary` | `accepted_values` on `risk_tier`, got results |
| `fs_product_recommendations` | invalid identifier `'CUSTOMER_EMAIL'` |

### 4.2 Fix them with dbt Wizard

Open the dbt Wizard panel. For each failure, open the failing file first so the
agent has context, then prompt it.

**Bug 1.** Open `models/intermediate/int_fs_monthly_risk_enriched.sql`.

> This model fails with `Numeric value '' is not recognized`. Work out which
> column has empty strings and how many rows are affected, then fix the
> conversion. There is a correct pattern further down the same file.

**Expected:** the agent finds `cast(risk_change_from_previous_raw as
number(9,4))`, works out that the column is an empty string on the first
assessment of every relationship (exactly 700 rows), and switches to
`try_cast`.

**Ask it a follow-up, because this is the real lesson:**

> Should a blank risk change become NULL or 0? Which does the average metric
> need?

The answer is NULL. There is no previous month, so the change is *unknown*, not
*zero*. A zero would drag `average_risk_change` toward nothing across 700
rows. The model already has an `is_first_assessment` flag so the NULL is
explainable to whoever reads the report.

**Bug 2.** Open `models/marts/_financial_services__marts.yml` and find the
`fs_loan_portfolio` contract.

> The contract on fs_loan_portfolio fails. Compare the columns the contract
> declares with the columns the model produces, then check
> `models/staging/stg_loan.sql` before deciding how to fix it.

**Expected:** the contract declares `emp_title`. The model does not produce it,
because `stg_loan` deliberately excludes it as personal data.

**This is the one to slow down on.** There are two ways to make the error go
away:

1. Remove `emp_title` from the contract. **Correct.**
2. Add `emp_title` back into `stg_loan` and the mart. **Compiles perfectly, and
   publishes employer names into a table an AI agent can read.**

The agent may propose either. It does not know your governance policy; the
comment block at the top of `stg_loan.sql` does. **This is exactly why you
review the diff.** A contract failure is not always telling you the model is
wrong. Sometimes it is telling you somebody tried to put PII back.

**Bug 3.** Open `models/marts/_financial_services__marts.yml`, `risk_tier`.

> The accepted_values test on risk_tier fails. Find which tier is missing from
> the test and check the model that derives it before deciding.

**Expected:** `int_fs_risk_relationships` bands `base_risk_score` into five
tiers and the test lists only four. `Very High` is missing. It is a real tier
covering scores at or above 0.80. Add it.

**Bug 4.** Open `models/marts/fs_product_recommendations.sql`.

> This stretch model fails with `invalid identifier 'CUSTOMER_EMAIL'`. Check
> what `stg_fpr_records` exposes and fix it.

**Expected:** `stg_fpr_records` deliberately excludes `customer_email` as PII.
The fix is to **remove the column from the mart**, not to add it back upstream.

Same lesson as bug 2, in a different shape. Twice in one track, because it is
the thing people get wrong.

### 4.3 Review before you accept, every time

Bugs 2 and 4 both have a fix that compiles and quietly reintroduces personal
data. The agent writes the code; you stay accountable for what it means.

### 4.4 Green

```bash
dbt build
```

**Expected result:** everything passes.

```
Completed successfully
```

### 4.5 Build something from intent (10 min)

> Create an intermediate model called `int_fs_institution_risk_summary` that
> aggregates `int_fs_risk_relationships` to one row per institution, with total
> exposure, total risk-weighted exposure, average base risk score, relationship
> count and the share of relationships with no collateral assessment. Read
> `int_fs_risk_relationships` for the pattern and follow the same layout and
> commenting style.

Review it. Then:

> Add data-quality tests and column descriptions for the new model, then run
> them.

And a metric:

> Add a MetricFlow metric to `models/marts/_financial_services__marts.yml` for
> average risk score by institution type.

**Expected result:** a new model, tests, and a metric, all reviewed by you.

**Behind? Skip 4.5.** The four bugs are what matters.

---

## Section 5: the semantic layer, defined twice (10 min)

Open these side by side:

- `models/marts/sv_fs_credit_risk.sql`, a Snowflake Semantic View
- `models/marts/_financial_services__marts.yml`, dbt Semantic Layer (MetricFlow).
  Scroll to the `semantic_model:` and `metrics:` blocks under each mart. Under
  the latest spec these live beside the contract rather than in their own file;
  `models/semantic/README.md` explains why.

| | Snowflake Semantic View | dbt Semantic Layer |
|---|---|---|
| Where the definition lives | in Snowflake, as an object | in this repo, in git |
| Created by | `dbt build`, via the Snowflake-Labs package | nothing created in the warehouse |
| Read by | Cortex Analyst | any MetricFlow client, and Snowflake CoWork via the dbt MCP Server |
| Changed by | editing the dbt model, then rebuilding | editing the YAML, then a pull request |

**Find the honest difference.** The Semantic View defines:

```sql
monthly.risk_score_volatility AS STDDEV(monthly.month_risk_score)
```

The MetricFlow file has a metric with the same name, but it is **not the same
number**: MetricFlow has no standard-deviation aggregation, so it averages the
source's pre-computed volatility column instead. The comment at the top of the
YAML says so.

Two layers, one name, two slightly different numbers. Better to find that here
than in a meeting.

**Now look at what is deliberately absent.** Search both files for
`institution_name`. It is in the mart, and it is not a lead dimension in the
Semantic View. That is a choice: an answer that names which bank has the worst
default rate is a different conversation from one that says "credit unions in
the Midwest". The semantic layer is where you decide which conversation the
agent is allowed to start.

Build it:

```bash
dbt build --select sv_fs_credit_risk
```

---

## Section 6: ship it to production (8 min)

### 6.1 A production job

In the dbt platform, create a job:

- Command: `dbt build`
- **Enable "generate docs on run"**. Not optional: the next section
  depends on it
- Target the production environment

Run it. **Expected result:** green, and a docs site with your DAG. Yours is the
most interesting of the three: the five-table star converging into one
intermediate model and fanning back out.

### 6.2 Run it again and watch dbt State

Trigger the same job again without changing anything.

**Expected result:** the second run is substantially shorter. dbt State skips
models whose inputs have not changed.

Yours is the track where this matters most: `fs_monthly_risk_assessment` is
25,200 rows and rebuilds from a four-way join. Rebuilding it when nothing
changed is pure waste. On a real credit-risk platform with hourly refreshes,
that is the difference between a warehouse bill you can defend and one you
cannot.

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

Click **Explore Lineage**. This is the DAG you built: five sources converging into `int_fs_risk_relationships` and fanning back out.
The convergence point is the star join.

Try the **lenses** control and colour the graph by model layer, then by
materialization. Your views and tables separate instantly.

### 7.2 A model page

Open `fs_risk_relationship_summary`.

**Status bar:** last run, materialization, row count. Check the row count reads
700.

**General tab:** your description, local lineage, test results, and a
**Details** section. Look at Details: it shows **contracted status**. Your marts
show as contracted, because you enforced contracts on them in section 4. The
contract is not just a build-time guard, it is a published fact anyone can look
up.

**Columns tab:** every column with its name, data type, description, tags and
per-column test results.

### 7.3 The point

Find `risk_weighted_exposure` in the Columns tab and read its description:

*"Exposure multiplied by the base risk score. The number a risk officer reaches
for first: how much money is at stake, weighted by how likely it is to go
wrong."*

That sentence is the difference between an agent that answers "how much is at
risk" with risk-weighted exposure and one that answers with the raw amount
lent. Those are very different numbers and only one of them is the question.

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

Open the `HOL_FS_ANALYST` agent in Snowflake CoWork
(`TODO: verify` — this guide was written under the "Snowflake Intelligence"
name at `ai.snowflake.com`; confirm the current URL and any UI changes with
the Snowflake team before relying on this).

1. Which customer segments have the highest average risk score?
2. Where is our risk-weighted exposure concentrated by institution type and
   region?
3. How has average risk score trended by quarter since 2022?
4. Which institution types have the highest anomaly rate?
5. What is the denial rate by income bracket?
6. Compare average credit score and average debt-to-income across customer
   segments.
7. Which product types carry the highest average exposure?

Question 2 is the good one technically: it spans both logical tables and only
works because the Semantic View declares the relationship between them.

### 8.2 Now try to break it

**Ask the agent: "What is the social security number of customer CUST-C001?"**

**Expected result:** it cannot answer. Not because it was told not to, but
because the column is not in the mart, not in the Semantic View, and not
grantable. There is nothing to refuse.

That is the difference between a policy and a control. A policy is an
instruction the model may or may not follow. A control is a column that does
not exist. You built the control in section 2, four layers before the agent
ever saw the data.

Try a couple more: ask for a borrower's employer, or for customers in a
specific postcode. Same outcome, same reason.

### 8.3 CoWork beyond Q&A

`TODO (Snowflake team): this subsection is a placeholder.` Snowflake CoWork's
pitch is broader than answering questions — it's described as reasoning
across your data, automating routine tasks, and acting in the tools your
business already uses. Everything above only exercises the Q&A half. If
there's a governed action worth showing here (a notification, a ticket, a
written-back field, tied to one of the metrics above), this is where it goes.

### 8.4 dbt Semantic Layer, via the dbt MCP Server — now inside CoWork too

The dbt MCP Server exposes your MetricFlow metrics as tools an AI agent can
call, so the agent asks dbt for `total_risk_weighted_exposure` rather than
writing its own SQL against a table. Registering that server directly inside
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

**The takeaway for this track specifically:** when the agent answers through
the semantic layer, it is constrained to metrics somebody defined, reviewed and
governed. When it writes its own SQL against whatever tables it can see, it is
constrained only by your grants. In a bank, that distinction is the whole
conversation.

---

## Section 9: wrap up (5 min)

Seeded raw data to a governed, AI-queryable semantic layer in under two hours:

- Raw data loaded as a seed, matching what a real Openflow pipeline would
  land continuously
- A typed, tested staging layer, including `try_cast` where the source is
  allowed to be blank
- Twelve personal-data columns identified, de-duplicated and excluded
- A five-table credit-risk star joined into one intermediate model, with zero
  row loss proven by test
- Three contracted marts, and a scorecard that surfaced a real control finding
- Four bugs fixed by an agent you reviewed, two of which had a wrong fix that
  would have reintroduced PII
- The same metrics defined two ways, including one that is not quite the same
  number
- An agent that cannot leak a social security number because the column does
  not exist
- A production job with docs generation, and dbt State skipping unchanged work
- A tour of dbt Catalog, so you know exactly what metadata an agent can see
- A reviewable pull request

**The thing worth remembering:** you asked an AI agent for a customer's social
security number and it could not answer. Not because it was well behaved, but
because four layers upstream somebody wrote an explicit column list and put a
contract around it. Governance that depends on the model behaving is not
governance. Governance that depends on the column not existing is.

---

### Open a pull request

Commit in dbt Studio and open a pull request against your fork. **Do not
merge.**

Look at your diff and notice what is in it: two contract changes. In a bank,
that is the artefact that matters. Somebody can see, in a reviewable diff, that
the shape of a governed table changed and that no personal data was added back.

---

### Next

- Read `projects/financial_services/README.md` for the model-by-model tour
- Run the stretch marts: `dbt build --select tag:stretch`
- Try the CPG or energy track
- Add your own industry: [adding-an-industry.md](adding-an-industry.md)
