# Run of show: two hours

Hard stop at 120 minutes. Everything below is timeboxed, and every attendee
guide carries the same minute budgets in its section headers so people can tell
at a glance whether they are ahead or behind.

---

## The schedule

| Clock | Section | Min | Who is doing what |
|---|---|---|---|
| 0:00 | Welcome, fork the repo, pick your industry | 8 | Instructor leads, attendees fork and choose |
| 0:08 | dbt platform setup, load your industry's seed data, sources and staging, **first green build** | 18 | Hands-on. `dbt/setup.md` then guide section 3 |
| 0:26 | dbt Studio and Fusion tour on the data-quality view | 8 | Instructor demos, attendees follow along |
| 0:34 | **dbt Wizard: fix four broken things, then build one from intent** | 25 | Hands-on. The centre of the lab |
| 0:59 | Semantic layer, defined two ways | 10 | Hands-on |
| 1:09 | Production job, docs generation, dbt State | 8 | Hands-on |
| 1:17 | **dbt Catalog: the metadata the agent will use** | 8 | Instructor demos, attendees follow in their own Catalog |
| 1:25 | **Ask, and act, in English — Snowflake CoWork** | 25 | Hands-on — dbt MCP half is hands-on too if wired to a shared dbt account, otherwise instructor-demoed |
| 1:50 | Wrap, pull request, next steps | 5 | Instructor |
| 1:55 | Buffer | 5 | Unclaimed. Use it or don't |
| 2:00 | End | | |

Hands-on time: 94 minutes. The remaining 26 is welcome, the two instructor-led
demos (Fusion and Catalog), the wrap, and a real 5-minute buffer.

**Note the ordering.** The production job now runs *before* the Catalog tour,
and Catalog runs *before* the AI section. That is deliberate: Catalog needs a
successful production job to have anything in it, and the whole point of
Catalog here is to show attendees what metadata the agent is about to consume.
Build it, publish it, look at it, then let CoWork use it.

**Note what's gone.** Earlier versions of this agenda had a dedicated
"Fivetran connector, start the sync" block, because a live sync took several
minutes and attendees needed something to do while it ran. Raw data now
ships as a seed per industry (see
[../openflow/openflow-overview.md](../openflow/openflow-overview.md)), so
loading it is a `dbt seed` command that finishes in seconds — it's folded
into the 0:08 setup block rather than standing on its own. That freed roughly
ten minutes, which went to a genuine buffer and to a longer CoWork section.

---

## Where the slack actually is

There is no dedicated buffer block in the hands-on portion, because in a
two-hour lab a buffer block in the middle is the first thing that gets eaten.
There is a real 5-minute buffer at the end now (there wasn't one before), and
beyond that, here are the places to take time back, in order.

**1. Section 9, the dbt MCP half of the CoWork section, is still the
designed compression point, for a different reason than before.** The
integration itself is fixed and fast (a one-click OAuth connect once
it's wired in — see below), but if you are behind at 1:45, skip the live
"watch me connect it" moment and just say it exists, pointing at
[dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md). Costs nothing,
because the Snowflake Semantic View half already delivered the
natural-language experience the room came for.

**2. Section 6 (production job) can drop to 5 minutes.** Show the dbt State
second run on the projector rather than having 30 people trigger jobs
simultaneously. But **the job itself must run for every attendee**, or their
Catalog is empty in the next section.

**3. Section 5 (semantic layer) can drop to 8 minutes.** The two semantic
definitions are already written in the repo. If time is short, read them
side by side and skip building a new metric.

**4. Section 7, dbt Catalog, can drop to 4 minutes.** Show lineage and one
model's Columns tab on the projector and move on. Do not cut it entirely: it is
what makes the AI section land as engineering rather than as a magic trick.

**Do not compress section 4 (dbt Wizard).** It is the reason people came.

---

## What each section has to land

### 0:00 Welcome, fork, pick (8 min)

Get three things done: everyone has forked the repo, everyone has chosen a
track, and everyone knows what to do if their fork breaks.

Say it out loud now, not at 1:00 when someone is stuck: *"if you break
something you can't undo, re-fork. Your seed data ships in the repo, so a
fresh fork is a fresh start, no account or sync to wait on."*

Steer nervous attendees to consumer packaged goods or energy, confident ones to
financial services. Nobody is scoring this.

### 0:08 dbt platform setup, seed data, first green build (18 min)

Attendees work through [../dbt/setup.md](../dbt/setup.md), then guide section 3.
Connect the fork, **set the project subdirectory**, create a dev and a
production environment, `dbt deps`, `dbt seed`, `dbt build --select staging`.

**This is checkpoint 1 and it must be green for everyone.** Nothing in staging
is booby-trapped, and `dbt seed` either succeeds or tells you exactly why (a
wrong project subdirectory, almost always).

Two things to police here, because both bite later. The **project
subdirectory** must be `projects/<track>`, or nothing works at all — including
`dbt seed`, which will report no seeds found. The **production environment**
must exist, or dbt Catalog is empty at 1:17.

### 0:26 Fusion tour (8 min)

Instructor drives, attendees follow in their own editor. Use the
`vw_*_data_quality` view in each track: it is a chain of small CTEs chosen for
exactly this.

Three beats: hover a column and see the type Fusion inferred without running
anything; break a `ref()` and watch the error appear before you run; preview a
single CTE in the middle of the model.

### 0:34 dbt Wizard (25 min), the centre of the lab

Run `dbt build`. It fails. Four things in every track are deliberately broken.

Attendees prompt dbt Wizard to diagnose and fix each one, reviewing and
accepting every change rather than letting it apply blind. The review step is
the teaching point: the agent writes, the human stays accountable.

Then one model built from intent, so it is not purely a repair exercise.

Budget roughly 15 minutes on the bugs and 10 on building something new. If the
room is fast, the answer key has stretch prompts.

### 0:59 Semantic layer, two ways (10 min)

The crux. The same metrics exist in a Snowflake Semantic View and in dbt
Semantic Layer specs. Open both files side by side.

The question to leave them with is not "which is better" but "where should the
definition of revenue live, and who else needs to read it".

### 1:09 Ship it to production (8 min)

A production job: `dbt build`, **"generate docs on run" enabled**, targeting the
production environment. Run it twice; the second run skips unchanged models via
dbt State.

Two reasons this moved earlier in the day. dbt State is a better story once
people have actually built something, and Catalog in the next section is empty
without a successful production run behind it.

**Police the "generate docs on run" checkbox.** Without it the Catalog Columns
tab is blank, and the Columns tab is the whole point of the next section.

### 1:17 dbt Catalog (8 min)

The bridge between what they built and what the AI is about to consume.

The line to say out loud: **dbt Catalog and the dbt MCP Server read the same
metadata, through the same Discovery API.** Catalog renders it for a human, the
MCP Server hands it to an agent. So this is not a documentation tour, it is a
preview of the agent's context window.

Three beats: the lineage graph with lenses, a mart's Columns tab, and the
Details section showing **contracted status** on the marts they contracted in
section 4.

Then the payoff. Have them read one good column description out loud, and then
find a thin one. Good AI answers come from descriptions, tests, contracts and
metric definitions, which means they come from the pull request, not the prompt.

Note that column-level lineage and model performance are Enterprise+ only, so
trial accounts may not show them. Everything else works on all plans.

### 1:25 Ask, and act, in English — Snowflake CoWork (25 min)

Cortex Analyst against the Snowflake Semantic View: fully hands-on, works
today. Sample questions are in
[../snowflake/cortex_semantic/agents_setup.md](../snowflake/cortex_semantic/agents_setup.md).

This lands harder straight after Catalog, because they have just seen the
metadata the agent is using.

The dbt MCP Server half **used to be a guided read-through because direct
registration into Snowflake's agent surface didn't work. That's fixed as of
August 24, 2026** — Snowflake shipped OAuth support for the kind of public
client dbt's remote MCP server already issues. If it's wired in for this
room (see the pre-flight checklist and the multi-tenancy note in
[dbt-mcp-on-snowflake-ai.md](dbt-mcp-on-snowflake-ai.md)), this is now a
real hands-on moment: attendees connect once via OAuth, then ask CoWork the
same governed question through the dbt Semantic Layer instead of the
Snowflake Semantic View, and compare the two. If the room is on individual
dbt trial accounts rather than a shared workshop account, demo this live
from one account instead — the fix is per-dbt-host, not something every
attendee configures themselves in two minutes.

Financial services attendees should ask the agent for a customer's social
security number. It cannot answer, because the column was never selected. That
is the governance beat and it lands better as a demo than as a bullet.

`TODO (Snowflake team): this section has 7 extra minutes versus the old
"ask your data" block, specifically freed up for CoWork material beyond
Q&A — the rebrand's pitch is an agent that "reasons across your data,
automates routine tasks and acts in the tools your business already uses,"
not just a chat window. Slot a short demo of that here once you've picked
one worth showing; a governed metric plus an action taken on it (a
notification, a ticket, a written-back field) would land well right after
the SSN-refusal beat above.`

### 1:50 Wrap and pull request (5 min)

Commit and open a pull request. Do not merge; the point is that the change is
reviewable, not that it ships.

Then what they built, what to read next, and how to get the data into their own
account.

### 1:55 Buffer (5 min)

Genuinely unclaimed. Use it to let the room catch up, or to let the CoWork
demo above run long if it's landing well.

---

## If you are running behind

| At this clock | You should be at | If you are not |
|---|---|---|
| 0:26 | Checkpoint 1 green, moving to Fusion tour | Fine, but stop stragglers by 0:34 |
| 0:59 | Everyone green on checkpoint 1 | Stop and fix stragglers now. Everything after depends on it |
| 1:09 | At least two bugs fixed | Move on anyway. Two is enough to make the point |
| 1:17 | Production job green for everyone | Demo Catalog from your own account instead |
| 1:25 | Catalog toured | Compress the MCP half to a projector walkthrough |

Two hard gates: checkpoint 1 at 0:34, and a green production job at 1:17,
because an empty Catalog makes the next section pointless. Everything else
degrades gracefully, and the 5-minute buffer at the end is there precisely so
one of these slipping doesn't cascade into the wrap.
