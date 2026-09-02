# Openflow, Snowflake and dbt: a two-hour hands-on lab

Build the full modern data stack loop on your own data, in your own accounts,
in two hours.

```
Openflow          Snowflake       dbt platform        semantic layer         Snowflake
(ingest)     ->   (store)    ->   (transform     ->   (define meaning)  ->   CoWork
                                   and govern)                                (ask and act in English)
```

You will model seeded raw data in dbt Studio with dbt Wizard doing the heavy
lifting, define the same metrics two different ways, and then ask (and have
CoWork act on) questions about your own data in plain English.

> **Fixed Aug 24, 2026: the dbt Semantic Layer now plugs directly into
> Snowflake CoWork.** Consuming it used to require a separate MCP client
> because of an OAuth mismatch between the two products. Snowflake shipped
> the fix — a public-client OAuth flow that matches what dbt's MCP server
> already issues — so this is now a real, hands-on part of the lab: connect
> once, then ask CoWork a governed metric straight from the dbt Semantic
> Layer, not just the Snowflake Semantic View. Exact setup, and the one
> caveat worth knowing before you rely on it for a room full of people:
> **[docs/dbt-mcp-on-snowflake-ai.md](docs/dbt-mcp-on-snowflake-ai.md)**.

**[Open the interactive guide](https://hicham-bab.github.io/snowflake-openflow-dbt-hol/)**
for a click-through version of this lab: pick your track and the whole run of
show tailors itself, with checkboxes that remember where you got to.

---

## Start here: three steps, about a minute

### 1. Fork this repo

Click **Fork** at the top right of
`github.com/hicham-bab/snowflake-openflow-dbt-hol`. Work in your fork, not in
the original. You will connect the fork to dbt Studio in a few minutes.

### 2. Pick your industry

You only do one. Pick the one closest to your day job, or the one that sounds
most interesting. All three take the same time.

| Track | Folder | The story | Pick it if |
|---|---|---|---|
| **Consumer packaged goods** | [`projects/cpg`](projects/cpg) | Order and product performance: order value, customer lifetime value, stockout and overstock risk, price optimisation | You want the cleanest run. One source table, two marts, no surprises |
| **Energy** | [`projects/energy`](projects/energy) | Commodity price history across 23 traded commodities, plus equipment reliability and maintenance economics | You like a reshaping problem. Wide-to-long unpivot, and two source feeds that are secretly the same data |
| **Financial services** | [`projects/financial_services`](projects/financial_services) | Credit risk across 250 customers and 20 lending institutions: risk scores, fraud probability, exposure, approvals | You are comfortable with joins and want the hardest one. A five-table star, and real personal data to govern |

New to dbt? Take **consumer packaged goods** or **energy**. Both finish
comfortably. Financial services is the same length but the data works harder to
trip you up.

> ### Whichever track you pick, you must tell the dbt platform about it
>
> This repo holds three separate dbt projects. The dbt platform does not know
> which one is yours until you say so.
>
> When you set up your dbt platform project, there is a field called
> **Project subdirectory**. Type your track's folder path into it:
>
> | If you picked | Type this into **Project subdirectory** |
> |---|---|
> | Consumer packaged goods | `projects/cpg` |
> | Energy | `projects/energy` |
> | Financial services | `projects/financial_services` |
>
> Leave it blank and dbt looks in the repo root, finds no `dbt_project.yml`,
> and nothing works. This is the single most common setup mistake in the lab.
>
> Where to find it: **Account settings → Projects → your project → Edit**,
> under the repository settings. You can change it later if you pick the wrong
> one.

### 3. Set up your two tools

One folder per tool. dbt has no fallback; Snowflake usually doesn't need one
either because the instructor supplies the account.

| Tool | Setup page | Time |
|---|---|---|
| **dbt platform** | **[dbt/setup.md](dbt/setup.md)** | **15 min, including loading your seed data. Cannot be skipped** |
| Snowflake | [docs/account-setup.md](docs/account-setup.md) | Usually supplied by the instructor |

There's no separate ingestion tool to set up. In production this pipeline
would land raw data with **Openflow**; see
[openflow/openflow-overview.md](openflow/openflow-overview.md) for why, and
for why this lab loads the same raw data with a `dbt seed` instead of running
a live ingestion tool in a two-hour room.

### 4. Open your guide and go

| Track | Your guide |
|---|---|
| Consumer packaged goods | [docs/attendee-guide-cpg.md](docs/attendee-guide-cpg.md) |
| Energy | [docs/attendee-guide-energy.md](docs/attendee-guide-energy.md) |
| Financial services | [docs/attendee-guide-financial-services.md](docs/attendee-guide-financial-services.md) |

Every section in those guides carries a minute budget. If you fall behind,
each one also tells you how to skip ahead without breaking anything.

---

## What you will actually do

| | What | Minutes |
|---|---|---|
| 1 | Fork the repo, pick your industry, get your accounts | 8 |
| 2 | Point dbt at your data, load your seed data, tour dbt Studio and Fusion | 26 |
| 3 | Build with dbt Wizard, and fix four deliberately broken things | 25 |
| 4 | Define your metrics twice: Snowflake Semantic View and dbt Semantic Layer | 10 |
| 5 | Ship it: a production job with docs, and dbt State | 8 |
| 6 | Tour dbt Catalog: see exactly what metadata an AI agent will use | 8 |
| 7 | Ask, and have CoWork act on, questions about your data in plain English | 25 |
| 8 | Wrap up and open a pull request | 5 |
| | Buffer | 5 |

Full run of show: [docs/agenda.md](docs/agenda.md).

---

## The one thing that will save you

**If your fork breaks, re-fork.** Your seed data is checked into the repo, so
your fork is self-contained: nothing about it depends on a live sync, a
personal schema prefix, or an account that might not have arrived yet. If you
get stuck in a way you can't unwind, forking `hicham-bab/snowflake-openflow-dbt-hol`
again (or the instructor's fork, if they've fixed something) gets you back to
a known-good state in under a minute. Nobody will know and the lab still
teaches the same thing.

---

## Two things this lab is really about

**dbt Wizard is an agent, not autocomplete.** You will not spend two hours
typing SQL that is already written. You will describe what you want, review
what the agent produces, and accept or push back. The review step is the point:
the agent writes, you stay accountable. Four things in your track are
deliberately broken, and you will fix them by talking to the agent rather than
by reading the answer key.

**Good AI answers come from the pull request, not the prompt.** Before you ask
an AI anything, you will tour dbt Catalog and see the exact metadata it is
about to read: your descriptions, your data types, your test results, your
contracts. Catalog and the dbt MCP Server pull from the same Discovery API, so
what you see there is what the agent gets. It reframes documentation from
hygiene into the thing that decides whether the answer is right.

**Meaning gets defined twice, on purpose.** The same metrics exist in two
places: a Snowflake Semantic View, native to Snowflake and read by Cortex
Analyst, and dbt Semantic Layer specs, living in this repo and read through the
dbt MCP Server. They are not redundant, they are two answers to "where should
the definition of revenue live". Your track has both, side by side, and the
guides are explicit about when you would reach for each.

---

## Repo map

```
├── README.md                    you are here
├── BUILD-NOTES.md               design decisions and what the real data does
├── docs/
│   ├── agenda.md                the two-hour run of show
│   ├── account-setup.md         dbt platform and Snowflake signup, and fallbacks
│   ├── attendee-guide-*.md      one step-by-step guide per track
│   ├── dbt-mcp-on-snowflake-ai.md   wiring the dbt MCP Server into Snowflake
│   │                                CoWork (fixed Aug 2026) or any other AI client
│   ├── facilitator-guide.md     instructor runbook
│   ├── answer-key.md            facilitator only: every seeded bug and its fix
│   └── adding-an-industry.md    how to add a fourth track
├── openflow/                    CONTEXT: how this pipeline ingests in production
│   └── openflow-overview.md     what Openflow does, and why the lab seeds instead
├── dbt/                         SETUP: transform and govern
│   ├── setup.md                 dbt platform: connection, repo, subdirectory,
│   │                            environments, seed data. The one you cannot skip
│   └── catalog-tour.md          dbt Catalog: the metadata an AI agent can see
├── snowflake/                   SETUP: store. Owned by the Snowflake team
│   ├── GOTCHAS.md               the integration traps that break Snowflake-to-dbt labs
│   ├── reference_setup.sql      minimal database, warehouse, roles and grants
│   └── cortex_semantic/         reference Semantic View DDL and agent setup
└── projects/
    ├── _template/               skeleton for adding a new industry
    ├── cpg/
    ├── energy/
    └── financial_services/
```

## Adding a fourth industry

The source database has 26 schemas; this lab uses three. Adding another is a
copy-paste-and-adapt job: see [docs/adding-an-industry.md](docs/adding-an-industry.md)
and start from [`projects/_template`](projects/_template).

## Running the lab yourself

Facilitators start at [docs/facilitator-guide.md](docs/facilitator-guide.md).
The Snowflake team starts at [snowflake/GOTCHAS.md](snowflake/GOTCHAS.md),
which is short, opinionated, and will save an afternoon.
