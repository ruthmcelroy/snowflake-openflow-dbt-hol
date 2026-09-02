# Build notes

A running log of the decisions behind this lab, and of what the real source
data turned out to be. Written for whoever maintains the repo next, including
future me.

---

## 1. Ground truth: the source data was introspected, not assumed

Every column list, type, row count and value set in this repo came from
querying the live Google Cloud SQL for PostgreSQL source directly, not from the
project brief. Several things differed. They are listed here because they
changed the design.

### Row counts (exact, `count(*)`, not `reltuples` estimates)

These are the real source counts, and still what a production Openflow
pipeline would land. This lab's seed CSVs are not a full extract, though —
see "Seed data" under Decisions below for what's actually in `seeds/`.

| Table | Rows in the real source |
|---|---|
| `consumer_packaged_goods.cpg_records` | 750 |
| `energy.commodity_prices` | 5,898 |
| `energy.fts_records` | 750 |
| `energy.loglynx` | 750 |
| `financial_services.risk_assess_customers` | 1,000 |
| `financial_services.risk_assess_financial_institutions` | 20 |
| `financial_services.risk_assess_risk_profiles` | 2,948 |
| `financial_services.risk_assess_performance_metrics` | 2,948 |
| `financial_services.risk_assess_monthly_assessments` | 106,128 |
| `financial_services.loan` | 39,717 |
| `financial_services.predict_term_deposit` | 45,211 |
| `financial_services.fpr_records` | 751 |

Largest table is 106k rows. Everything would build in seconds on an XS
warehouse either way, seeded or Openflow-landed.

### Where the brief and the data disagreed

| Brief said | Data says | What changed |
|---|---|---|
| `loan` has 119 columns | 118 columns; `ctid` is not a real Postgres column, an ingestion tool synthesises it | Nothing material. The curated subset is 20 columns |
| `predict_term_deposit` has 20 columns, ~44,396 rows | 19 columns, 45,211 rows | Documented counts corrected throughout |
| `fpr_records` 750 rows | 751 rows | Corrected |
| CPG has one table | Three exist, but the lab source user has no `SELECT` on `cpg_records_orig` or `cpg_stockout_rates`, so only `cpg_records` will sync | CPG stays a one-table track, as intended |
| `risk_appetite` is categorical | It is a float, 0.17 to 0.68 | Renamed `risk_appetite_score` in staging, with a derived `risk_appetite_band` alongside |
| `collateral_quality_score`, `liquidity_ratio`, `projected_cash_flow_rating` are numeric | All three are `text` with empty strings on ~two thirds of rows | `try_cast` in staging, and this became the FS teaching beat |
| `CORTEX_ENABLE_CROSS_REGION` | The parameter is `CORTEX_ENABLED_CROSS_REGION` | Corrected in `snowflake/GOTCHAS.md` |

### The big one: `loglynx` is a byte-for-byte duplicate of `fts_records`

All 750 `record_id`s appear in both. `SELECT * FROM fts_records EXCEPT SELECT *
FROM loglynx` returns zero rows, and so does the reverse.

The instruction was "two feeds, union them." A plain union would have doubled
every energy metric silently, which the brief elsewhere forbids ("never silent
wrong numbers that a beginner can't detect"). So the design is **union then
de-duplicate**, with `fts_records` as system of record and a `source_system`
column surviving on every row as evidence.

This turned out to be the best thing in the energy track. It is a real
post-migration estate problem, it is invisible without looking, and
`vw_energy_data_quality` reports the overlap as a consistency failure so it
stays visible instead of being quietly fixed and forgotten.

### Other real-data details that shaped models

- **WTI crude settles at -37.63 on 2020-04-20.** Real market event. There is
  deliberately no positivity test on `wti_crude`, and `price_change_pct`
  divides by `abs(previous_price)` so the percentage survives the sign change.
- **`commodity_prices` row `id = 1` (2000-01-03) is entirely null.** Filtered
  out in staging on `brent_crude is not null`.
- **`gasoline` starts later than the other 22 series**, ~1,480 nulls. Snowflake
  `UNPIVOT` drops nulls by default, which is the behaviour we want, so it is
  absent on days it did not trade rather than present as zero.
- **The commodity series ends 2022-11-04.** Every sample question says "in
  2022", never "this year". Worth repeating out loud in the room.
- **`predict_term_deposit.age` has two sentinels**, `999` (1 row) and `-1`
  (3 rows). Real ages are 18 to 95. Staging rejects anything outside 17 to 120
  rather than enumerating the two known bad values, so a third sentinel next
  quarter is handled without anyone noticing.
- **CPG `order_total` is populated on 192 cancelled orders.** Hence
  `recognised_revenue`, and a singular test that keeps it honest.
- **FS star has zero orphans** in every direction, verified against the real
  source. Join counts are exact: 2,948 relationships join 1:1 to performance
  metrics on all three keys, and 106,128 monthly rows join to relationships
  with no fanout and no loss. The seed generator preserves this invariant
  exactly at its own (smaller) scale — see "Seed data" below.
- **`loan` PII is redundant, not just present.** `ssn`, `social_security_number`
  and `ssnumber` hold the identical value on every row; `ssnumber1` holds
  a different one; `dl` and `drivers_license` are identical on every row. Six
  identity columns, two actual identifiers. That redundancy is the FS
  governance lesson: dropping `ssn` alone ships the same number twice more.
  Preserved in the seed at reduced scale, same rule.

---

## 2. Decisions

### Naming

- Database `HOL_SNOWFLAKE_INDUSTRY`, to be created by the Snowflake team.
- Each project exposes `track_key`, `track_name` and `track_description` as
  vars in one block at the top of `dbt_project.yml`. That block is the only
  per-track config; there is no source-schema pointer to set, because raw
  data comes from a seed committed in the project, not a live sync.

### Seed data: full fidelity for CPG and energy, trimmed for financial services

Earlier versions of this lab ingested the real source live (first Fivetran,
conceptually now Openflow; see `openflow/openflow-overview.md` for why the
lab doesn't run that live at all). This version ships each track's raw
tables as `dbt seed` CSVs, generated by `scripts/generate_seed_data.py` with
a fixed random seed, so it's reproducible and reviewable in a diff rather
than a one-off manual export.

- **CPG and energy seed at the real source's exact scale**, with every quirk
  in section 1 above reproduced deliberately (192 cancelled CPG orders still
  carrying `order_total`, the WTI -37.63 print, the null `id=1` row, gasoline
  starting late, `loglynx` byte-identical to `fts_records`). Nothing
  downstream — models, tests, seeded bugs, agent instructions — needed a
  number changed for these two tracks.
- **Financial services seeds at roughly 5-10% of the real source's scale**,
  because the real `risk_assess_monthly_assessments` table alone is 106,128
  rows, and three FS tables together would be over 190k rows of CSV
  committed to a public repo. The generator preserves every documented
  invariant exactly at the smaller scale: the zero-orphan star join, the
  36-months-per-relationship structure (so `monthly_assessments` is still
  exactly `relationships × 36`, not an arbitrary number), the loan PII
  redundancy pattern, the empty-string sentinels in ~two-thirds of the
  numeric-but-text columns, and the `age` sentinels (999, -1) in
  `predict_term_deposit`. Current scale: `risk_assess_customers` 250,
  `risk_assess_financial_institutions` 20 (unchanged — it's a small dimension
  either way), `risk_assess_risk_profiles` and `risk_assess_performance_metrics`
  700 each, `risk_assess_monthly_assessments` 25,200, `loan` 3,000,
  `predict_term_deposit` 3,000, `fpr_records` 750. Every FS doc, test and
  agent instruction that quotes an absolute row count uses these numbers, not
  the real source's.

### Three separate dbt platform projects

Confirmed with the author. Each attendee sets up one dbt platform project
pointing at their track's subdirectory. Three folders in git; one project
object per attendee.

### Contracts on all marts, PII beat in financial services

Every mart in every track has `contract: enforced: true` with a full pinned
column list. To make that safe without a live warehouse to test against, **every
contracted column is explicitly cast in the model SQL to exactly the type
declared in the YAML**. A contract mismatch is then impossible except where one
is deliberately seeded.

Contracts are the enforcement mechanism for the FS PII story: the contract on
`fs_loan_portfolio` is the written-down list of what is allowed out of the
project, reviewable in a pull request.

### Semantic views: one per subject area, not one per track

CPG has one (`sv_cpg_commercial_performance`), FS has one
(`sv_fs_credit_risk`), energy has two. Energy's two subject areas, commodity
prices and equipment maintenance, share no key. Forcing them into one object
would hand Cortex Analyst a join it cannot make. The file naming pattern
`sv_<track>_<subject>.sql` holds across all three.

### Data-quality views read from staging, not marts

`vw_*_data_quality` in each track reads staging models. Two reasons: it keeps
that branch of the DAG independent of the seeded bugs so it always builds, and
in energy the most important finding (the duplicated feed) is only visible
before de-duplication.

### An `as_of_date` on the FS relationship mart

MetricFlow requires an `agg_time_dimension` for any semantic model with
measures. `fs_risk_relationship_summary` is a snapshot with no natural date, so
`int_fs_risk_relationships` attaches the maximum assessment date from staging
via a cross join to a one-row CTE. Reading it from staging rather than from
`int_fs_monthly_risk_enriched` keeps the DAG acyclic.

### What was deliberately not built

- **No macros.** Every `macros/` directory is empty. A beginner should be able
  to read any model top to bottom without following an abstraction.
- **No incremental models.** Nothing here is big enough to justify the
  explaining time.
- **No source freshness checks.** The data is static, so freshness would fail
  for every attendee by design. The config is present but commented out in each
  sources file with an explanation.
- **An INFORMATION_SCHEMA-based PII test was written and then removed.** It had
  no `ref()`, so dbt could not order it, and it depended on schema-name casing
  and `ESCAPE` quoting through Jinja. Too fragile for a live room. The
  contracts do that job.

---

## 3. Seeded bugs

Twelve total, four per track, all marked with a greppable `HOL_BUG_<TRACK>_<nn>`
comment. Full detail in `docs/answer-key.md`.

Design rules applied:

- **Checkpoint 1 is `dbt build --select staging` and is always green.** No bug
  sits in staging SQL or staging tests. The brief asked for a staging-layer bug;
  instead, two of the bugs are *consequences* of a staging rename, which teaches
  the same thing without breaking the first checkpoint.
- **No bug is a parse-time error.** A malformed semantic YAML would fail the
  whole project at parse and block checkpoint 1 too. All twelve are
  compile-time, run-time or test failures scoped to one node.
- **Bugs are spread across branches** so one failure does not block the DAG.

| Track | Wave 1 (first `dbt build`) | Wave 2 (after fixing wave 1) |
|---|---|---|
| CPG | 01 intermediate, 02 mart ref typo, 03 test threshold | 04 contract mismatch |
| Energy | 01 intermediate unpivot, 02 missing `group by`, 03 accepted_values | 04 contract mismatch |
| Financial services | 01, 02, 03 and 04 all surface at once | none |

CPG and energy have a deliberate two-wave shape: bug 04 is the contract
equivalent of bug 01, so fixing the model and then being told the contract also
has to agree is the intended "oh, right" moment. FS surfaces all four at once
because its branches are cleanly independent.

---

## 4. Open items and honest gaps

### RESOLVED 2026-08-24: the dbt MCP Server can now be registered directly in Snowflake's agent surface

This was the one place the lab could not be built as specified, for as long
as this repo existed. It's closed now — worth leaving this note in place so
nobody re-discovers the old blocker and "fixes" it backwards.

**What it used to be:** Snowflake's `CREATE EXTERNAL MCP SERVER` required an
API integration with `API_USER_AUTHENTICATION = (TYPE = OAUTH2 ...)`,
including `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` — a confidential
client. dbt's remote MCP server only ever issued public clients (dynamic
registration per RFC 7591, or PKCE per RFC 7636, no secret). Separately,
dbt's endpoint required an `x-dbt-prod-environment-id` header Snowflake had
no documented way to send. Two independent blockers.

**What changed:** Snowflake shipped `TYPE = OAUTH_DYNAMIC_CLIENT` with
`OAUTH_CLIENT_AUTH_METHOD = NONE` for external MCP integrations — a public
client via Dynamic Client Registration + PKCE, matching what dbt already
issues. Project scoping moved into the OAuth consent step, so the header
requirement is gone too. Documented by dbt Labs at
[Integrate Snowflake Cortex agents with dbt MCP](https://docs.getdbt.com/docs/dbt-ai/integrate-mcp-snowflake-cortex),
last updated Aug 24, 2026 — fetched and read in full to confirm this, not
taken from a search summary.

`docs/dbt-mcp-on-snowflake-ai.md` section 3 has the full mechanism and a
multi-tenancy caveat (this binds to one dbt platform host, so it's a single
setup for a shared workshop account but a per-account thing for individual
trial signups). `snowflake/cortex_semantic/agents_setup.md` has the exact
SQL, adapted to this lab's naming, alongside the three Cortex Agents it
already builds.

Re-check before each delivery anyway — both products are still moving
quickly, and dbt's own page still says "Snowflake Intelligence" rather than
"CoWork," which is a naming lag worth watching, not a sign the mechanism
changed back.

### What HAS been verified with the dbt CLI

`dbt deps` and `dbt parse` were run against all three projects with
dbt-fusion 2.0.0-preview.200. All three now report
`Finished 'parse' successfully`, with no errors and no warnings.

That run found two real defects, both since fixed.

**1. A bad `ref()` is a parse-time error on Fusion, so it broke checkpoint 1.**
`HOL_BUG_CPG_02` was originally a typo'd `ref('int_cpg_inventory_helth')`.
Fusion raises `DependencyNotFound (dbt1048)` at parse, which fails the whole
project before any model runs, including `dbt build --select staging`. Proven,
not theorised: the build command was run and returned the parse error.

The bug is now a wrong column name (`inventory_coverage_rate` instead of
`inventory_coverage_ratio`), which behaves the same way pedagogically without
touching the checkpoint. The ref-typo lesson survives in section 4.2 of each
attendee guide, where attendees break a `ref()` on purpose and watch Fusion
catch it instantly, which is a better demonstration anyway.

**2. All three tracks were on the deprecated semantic-layer YAML spec.**
Fusion raised `SemanticModelDeprecated (dbt1157)`: "defines semantic models and
metrics using the legacy YAML. Please migrate to the new YAML to use the
semantic layer with dbt Fusion." Since the semantic layer is a headline feature
of this lab, legacy was not acceptable.

Migrated with the official tool, `uvx dbt-autofix deprecations
--semantic-layer`. The new spec embeds semantic annotations in the model they
describe, so:

- top-level `semantic_models:` and `metrics:` are gone
- `semantic_model: {enabled: true}` and `agg_time_dimension:` sit on the model
- `entity:` and `dimension:` attach to the column, not to separate lists
- `measures:` no longer exist; a simple metric with `agg:` and `expr:` replaces
  each one
- `type_params:` is gone; ratio metrics take `numerator`/`denominator`
  directly, derived metrics take `input_metrics:`

Because a dbt model can only be configured in one YAML file, the semantic
definitions now live in `models/marts/_<track>__marts.yml` beside the contract,
**not** in `models/semantic/<track>.yml` as the original brief specified. That
folder now holds a README explaining the change. This is a forced deviation
from the brief, not a preference.

The autofix output needed hand cleanup: it concatenated descriptions, displaced
comment banners, and appended an entity-only `commodity_code` column into a
contracted model. All repaired and re-verified.

### Still not verified against a live warehouse

`dbt compile` and `dbt build` have not run: the workshop Snowflake account did
not exist at build time. Parse is as far as it goes without credentials, and
that's true regardless of whether raw data arrives via seed or via a live
ingestion tool.

**One open risk that only a warehouse can settle.** Fusion does column-aware
static analysis when it has catalog metadata. Without a connection it did not
flag the wrong-column-name bugs (CPG_01, CPG_02, ENERGY_01) or the missing
`group by` (ENERGY_02). With a live connection it may raise some of those at
parse rather than at build, which would break checkpoint 1 the same way the bad
`ref()` did.

The dry run must check this explicitly, and `docs/facilitator-guide.md` now
carries the procedure and the fallback. The bug classes that are provably safe
are test failures and runtime data errors (FS_01's `cast('' as number)` cannot
be known statically); contract mismatches are very likely safe but unconfirmed.

**Also unverified: the switch from `source()`/Fivetran to `dbt seed`/`ref()`.**
Every staging model was rewired to read from a seed instead of a landed
source table, and the `_fivetran_synced` audit column was dropped throughout.
This was checked with `dbt parse` (see above) but not yet with a real `dbt
seed` + `dbt build` against a warehouse. Do that on the next dry run before
trusting the "expected result" row counts in the attendee guides.

### Placeholders left for the author

`{{DBT_WORKSHOP_URL}}`, `{{LAB_CREDENTIALS_URL}}`, `{{PASSCODE}}`,
`{{SNOWFLAKE_ACCOUNT}}`, `{{DBT_HOST}}`, `{{DBT_TOKEN}}`, `{{DBT_PROD_ENV_ID}}`,
`{{DBT_USER_ID}}`. All collected in one table in `docs/account-setup.md`.

There's no source Postgres host/user/password placeholder anymore: attendees
never connect to the source database directly, since raw data ships as a
seed in the repo. `openflow/openflow-overview.md` covers what a live
connection would look like if this pipeline ran ingestion for real.
