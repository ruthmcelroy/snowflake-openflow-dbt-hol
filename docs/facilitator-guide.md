# Facilitator guide

Everything you need to run this in a room of about 30 people creating accounts
on the day.

Companion documents: [agenda.md](agenda.md) for timings,
[answer-key.md](answer-key.md) for the seeded bugs, and
[../snowflake/GOTCHAS.md](../snowflake/GOTCHAS.md) for the Snowflake team.

---

## The one thing to internalise

**Every attendee's raw data is already in their fork, as a seed.** There is
no live sync to wait on, no destination schema prefix to type correctly, and
no fallback schema to fall back to, because there's nothing that can be slow
or flaky on the ingestion side. `dbt seed` either succeeds (almost always,
because the only way to fail it is the project subdirectory being wrong) or
tells you immediately why.

That changes what you need to internalise: the failure modes that used to
come from a live Fivetran sync are gone. What's left is simpler — the project
subdirectory, the Snowflake connection, and the four seeded bugs. Spend your
prep time there instead.

---

## Pre-flight

### Two weeks before

- [ ] Snowflake team has [../snowflake/GOTCHAS.md](../snowflake/GOTCHAS.md) and
      [../snowflake/reference_setup.sql](../snowflake/reference_setup.sql)
- [ ] Confirm who owns the Snowflake account and who will be in the room from
      that team
- [ ] dbt platform workshop accounts requested
- [ ] Confirm the Snowflake account region supports the Cortex models, or that
      `CORTEX_ENABLED_CROSS_REGION` will be set

### One week before

- [ ] `HOL_SNOWFLAKE_INDUSTRY` exists, warehouse exists, roles and grants
      applied
- [ ] `DBT_SVC` is `TYPE = SERVICE` with key-pair auth, and the connection
      tests green. **Password-only service users are being blocked right
      now, between August and October 2026.** Gotcha 1
- [ ] Grants applied for the dbt role, including `CREATE SCHEMA` so each
      attendee's dev schema can be created. Gotcha 2

### Three days before: the dry run

**Do not skip this.** `dbt deps` and `dbt parse` have been run against all three
tracks and all three pass cleanly on dbt-fusion 2.0.0-preview.200. `dbt seed`,
`dbt compile` and `dbt build` have **not** run against a real warehouse yet —
see `BUILD-NOTES.md` section 4. This dry run is where that gets closed, and
it's more important than it used to be, because the source-to-seed rewrite
hasn't been checked against a warehouse at all.

For each of the three tracks, as an attendee would:

- [ ] `dbt deps`
- [ ] `dbt parse` → **`Finished 'parse' successfully`**, no errors, no warnings
- [ ] `dbt seed` → all seeds load. Record the row counts and compare against
      `BUILD-NOTES.md`'s "Seed data" section — this is the first real test of
      the source-to-seed rewrite
- [ ] `dbt build --select staging` → **green**. Record the model and test counts
      so you can put real numbers in front of the room
- [ ] `dbt build` → fails with exactly the bugs in [answer-key.md](answer-key.md),
      and no others
- [ ] Apply every fix from the answer key → `dbt build` fully green
- [ ] Time the full build and note it

If anything fails that is not in the answer key, fix it in the repo before the
day and tell the author.

#### The one check that actually matters: when do the bugs surface?

Fusion does column-aware static analysis when it can reach the catalog. Parsed
without a warehouse connection, it did **not** flag the wrong-column-name bugs
or the missing `group by`. With a live connection it might raise some of them at
**parse** instead of at build, and a parse error fails the whole project,
including `dbt build --select staging`. That would break checkpoint 1 for
everyone, which is the one hard gate in the lab.

This is already proven to be a real failure mode: `HOL_BUG_CPG_02` used to be a
typo'd `ref()`, and on Fusion that is a parse-time error that took checkpoint 1
down. It was changed to a column-name error for exactly this reason.

**Run this check, per track, with the real Snowflake connection:**

```bash
dbt seed
dbt parse          # must succeed
dbt build --select staging   # must be green
```

- **Both clean:** you are fine. The bugs surface at build, as designed.
- **`dbt parse` errors:** note which bug IDs appear. Those bugs break
  checkpoint 1 and must be swapped before the day.

**If a bug does surface at parse**, swap it for one of these, which cannot be
caught statically because they depend on data values or on test results:

| Broken bug | Safe replacement |
|---|---|
| A wrong column name | A `cast()` of a text column that holds non-numeric values, like `HOL_BUG_FS_01` |
| A missing `group by` | An `accepted_values` test missing a real value, like `HOL_BUG_ENERGY_03` |
| A contract mismatch | A `dbt_utils.accepted_range` with an unreachable threshold, like `HOL_BUG_CPG_03` |

Tell the author either way, so the repo gets fixed rather than just your copy.

### Two days before

- [ ] dbt job run in production so the Semantic Views exist
- [ ] Semantic View grants applied **after** that job. Gotcha 6
- [ ] Three Cortex Agents created per
      [../snowflake/cortex_semantic/agents_setup.md](../snowflake/cortex_semantic/agents_setup.md),
      with the agent instructions pasted in. Those instructions are not
      optional: they are what stops the CPG agent reporting the wrong revenue
      and the energy agent returning empty answers for "this year"
- [ ] Ask one question per track in Snowflake CoWork, **signed in as a
      user whose only role is `HOL_ATTENDEE`**
- [ ] **Wire the dbt Semantic Layer into CoWork via MCP** —
      [agents_setup.md](../snowflake/cortex_semantic/agents_setup.md#wiring-in-the-dbt-semantic-layer-via-mcp).
      This used to be blocked; it's fixed as of Aug 24, 2026 and it's the
      best moment in section 8 now. Skip only if you're on individual
      per-attendee dbt trials rather than a shared workshop account (see
      the multi-tenancy note there) — demo it live instead

### Day of, before doors open

- [ ] Warehouse resumed and warm
- [ ] Lab credentials card published, all `{{PLACEHOLDER}}` values filled in
- [ ] Projector shows the repo README, and the track picker table is legible
      from the back of the room

---

## Room logistics for three tracks at once

### Steering people

Ask two questions as they arrive, not one:

1. **"How comfortable are you with SQL joins?"**
2. **"What industry are you in?"**

| Answer | Send them to |
|---|---|
| New to dbt, wants a clean run | **Consumer packaged goods.** One source table, two marts, nothing surprising |
| Comfortable, likes a puzzle | **Energy.** The unpivot and the duplicate-feed discovery are the most fun in the lab |
| Confident with joins, wants the hardest | **Financial services.** Five-table star, real PII |
| Works in a bank or insurer | **Financial services**, if they are comfortable. The narrative sells itself |
| Retail, manufacturing, consumer | **Consumer packaged goods** |
| Utilities, oil and gas, industrials | **Energy** |
| Genuinely no preference | **Consumer packaged goods.** It is the safest |

Expect roughly 40 / 30 / 30. If financial services goes above about a third of
the room, spend more of your floor time there: it has the most places to get
stuck.

### Supporting three tracks

**Do not try to track three DAGs in your head.** Work from the symptom.

| Attendee says | It is almost always |
|---|---|
| "It can't find dbt_project.yml" | Project subdirectory not set to `projects/<track>` |
| "No seeds found" on `dbt seed` | Same cause — wrong or missing project subdirectory |
| "Object does not exist" | A grants problem in their dev schema, not the seed data |
| "invalid identifier" on a staging column | They are past checkpoint 1 and hit bug 01 |
| "Contract failed" | Bug 04 in CPG or energy, bug 02 in financial services |
| "My test failed but the data looks fine" | Bug 03. That is the lesson, let them sit with it |
| "The agent gave a weird number" | Agent instructions not saved on the agent |

**Timebox any individual to three minutes.** Then help them re-fork if
they're truly stuck, and move on. One person's setup is not worth ten
people's attention.

### The two moments to pull the whole room together

**At about 0:50, energy bug 02.** Adding `maintenance_status` to the `group by`
makes the error disappear and silently changes the grain. Ask who fixed it that
way. Usually a third of them.

**At about 0:55, financial services bug 02.** The contract fails because a PII
column is declared but not produced. One fix removes it from the contract; the
other adds employer names back into a table an AI agent can read. Both compile.
Ask the room which one they would have accepted at 4pm on a Friday.

Those two moments are the argument for reviewing agent output, and they land
far better as a live show of hands than as a slide.

---

## Failure playbook

| Symptom | First response | If that fails |
|---|---|---|
| `dbt seed` fails or finds nothing | Check the project subdirectory first | Re-fork; the seed CSVs are committed, so a fresh fork always has them |
| `dbt build --select staging` red | Check the project subdirectory, then the dbt-Snowflake connection | Re-fork and redo setup — 5 minutes, not worth debugging further mid-lab |
| "Object does not exist" across several people at once | **Stop. This is a grants problem, not theirs.** Gotcha 2 | Escalate to the Snowflake team |
| dbt platform will not connect to Snowflake | Check account identifier format, then key vs password | Shared dbt account |
| Cortex agent returns nothing, no error | Missing grants on the tables under the Semantic View. Gotcha 6 | Demo on the projector from your own session |
| Cortex agent worked yesterday, not today | The dbt job re-created the Semantic View and dropped its grants. Re-run them. Gotcha 6 | Same |
| Cortex not available at all | Region. `CORTEX_ENABLED_CROSS_REGION`. Gotcha 5 | Shared lab Snowflake account |
| Whole room behind at 1:25 | Compress section 7 (dbt Catalog) to a projector demo, section 8 (CoWork) to the Semantic View half only | Drop the pull request to homework |
| Someone finished early | Stretch prompts at the end of [answer-key.md](answer-key.md) | Have them help a neighbour |

---

## Timing table

Matches [agenda.md](agenda.md). Print this.

| Clock | Section | Min | Gate |
|---|---|---|---|
| 0:00 | Welcome, fork, pick, accounts | 8 | Everyone has forked and chosen |
| 0:08 | dbt platform setup, seed data, sources, staging | 18 | **Checkpoint 1 green** |
| 0:26 | dbt Studio and Fusion tour | 8 | |
| 0:34 | dbt Wizard, four bugs, one model | 25 | At least two bugs fixed |
| 0:59 | Semantic layer, two ways | 10 | Both definitions opened |
| 1:09 | Production job, docs, dbt State | 8 | **Job succeeded in production** |
| 1:17 | dbt Catalog tour | 8 | Catalog is populated |
| 1:25 | Ask, and act, in English — CoWork | 25 | One question answered |
| 1:50 | Wrap, pull request | 5 | |
| 1:55 | Buffer | 5 | |
| 2:00 | End | | |

**Two gates now.** Checkpoint 1 at 0:26, and a successful production job at
1:17. The second is new: dbt Catalog only shows metadata from a deployment
environment marked production or staging, after a job has succeeded there. If
someone's job failed, their Catalog is empty and section 7 has nothing to show.

Watch for two causes: no production environment created (send them to
`dbt/setup.md` step 5) and "generate docs on run" not enabled, which leaves the
Columns tab blank.

Everything else degrades gracefully, and there's now a real 5-minute buffer at
the end to absorb whatever slipped.

---

## Things to say out loud

**At 0:05, the fork.** *"If you break something you can't undo, just re-fork.
Your seed data is committed, so a fresh fork is a fresh start — no account,
no sync, nothing to wait on."*

**At 0:15, why there's no Fivetran/Openflow step.** *"In production this
pipeline would land raw data with Openflow, continuously. We're skipping
that here and loading it as a seed instead, purely to keep two hours on
schedule — watching a sync bar teaches you less than you'd think."*
(`openflow/openflow-overview.md` has the full version if anyone wants it.)

**At 0:45, on Fusion.** The error appeared before anything ran. That is the
whole pitch: the feedback loop is at typing speed, not at warehouse speed.

**At 0:50, before they run `dbt build`.** *"This is going to fail. Four things
are broken on purpose. Do not fix them by hand, and do not let the agent fix
them without reading the diff."*

**At 1:05, on the two semantic layers.** The question is not which is better.
It is where the definition of revenue should live and who else needs to read it.

**At 1:20, financial services.** Have somebody ask the agent for a customer's
social security number. It cannot answer, because the column does not exist.
That is the difference between a policy and a control, and it demonstrates
better than any slide.

**At 1:15, on dbt State.** On a project this size it saves seconds. On 2,000
models running hourly it is the difference between a warehouse bill you can
defend and one you cannot.

**At 1:35, the dbt Semantic Layer inside CoWork.** *"Until three days ago,
this was two products that couldn't talk to each other directly — you'd have
had to use a separate app to get this. Snowflake shipped the fix on August
24th. Watch: same question, same governed metric, now asked straight from
CoWork."* If you've wired it in (see the pre-flight checklist), this is the
line to say right before you ask it live.

---

## Known gaps, so you are not caught out

**The dbt MCP Server ↔ Snowflake integration is fixed, as of Aug 24, 2026 —
it used to be the gap here, it isn't anymore.** Snowflake added
`OAUTH_DYNAMIC_CLIENT` support for external MCP integrations, matching the
public-client OAuth dbt's remote MCP server already issues. Section 8 now
treats this as a real hands-on (or facilitator-demo, depending on your dbt
account setup — see the multi-tenancy note) part of the lab rather than a
walkthrough-because-it's-broken. Full detail, exact SQL, and citations in
[dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md) and
[../snowflake/cortex_semantic/agents_setup.md](../snowflake/cortex_semantic/agents_setup.md).

**If it's your first time delivering this since the fix landed, budget a
few extra minutes to set it up and test it** — it's new, and "new" means
worth a dry run of its own, same as everything else in this lab.

**Re-check it before every delivery anyway.** Both products are moving fast,
and this fix is only two days old as of this writing.

**`ai.snowflake.com`, the exact Cortex Agent object model under the CoWork
rebrand, and the CoWork automation demo slotted into section 8's agenda are
all marked `TODO: verify` in this repo.** Confirm with the Snowflake team
before the day — see `index.html` and `snowflake/cortex_semantic/agents_setup.md`
for exactly where.

**No live `dbt seed` or `dbt build` has been run against a warehouse for this
repo since the source-to-seed rewrite.** The dry run three days out is how
that gets closed. See `BUILD-NOTES.md` section 4.

---

## After the lab

- [ ] Suspend the warehouse
- [ ] Consider dropping attendee dev schemas: 30 people times one schema each
- [ ] Note anything that broke, and open an issue on the repo
- [ ] If the dbt MCP ↔ CoWork setup behaved differently than documented
      (new UI labels, changed SQL, tier restrictions lifted), update
      [dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md),
      [../snowflake/cortex_semantic/agents_setup.md](../snowflake/cortex_semantic/agents_setup.md),
      the three attendee guides and this file
