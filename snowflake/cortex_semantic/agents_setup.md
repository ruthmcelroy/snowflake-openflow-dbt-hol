# Cortex Agents and Snowflake CoWork setup

**Owner: the Snowflake team. Done before the lab, not during it.**

Attendees consume these; they do not create them. Roughly 30 minutes of setup
the day before, plus one end-to-end test signed in as an attendee-role user.

`TODO: verify with the Snowflake team.` This page was built under the
"Snowflake Intelligence" name; Snowflake rebranded that surface to
**Snowflake CoWork** at Summit 2026, with an expanded scope (it now acts on
your tools, not just answers questions). The renames below are prose-only —
`ai.snowflake.com`, the exact agent-creation UI, and whether "Cortex Agent"
as an object concept changed under CoWork are all unverified. This is also
the natural place for a Snowflake colleague to add CoWork-specific material
(see the `TODO` in `docs/agenda.md` section 8) — the sample questions below
only exercise Q&A, not CoWork's newer action/automation capabilities.

---

## What you are building

One Cortex Agent per track, each pointed at the Semantic View that dbt creates,
surfaced in Snowflake CoWork (`ai.snowflake.com` at time of writing —
`TODO: verify` this is still the right URL post-rebrand).

| Track | Agent | Semantic View |
|---|---|---|
| Consumer packaged goods | `HOL_CPG_ANALYST` | `SV_CPG_COMMERCIAL_PERFORMANCE` |
| Energy | `HOL_ENERGY_ANALYST` | `SV_ENERGY_COMMODITY_PRICES` and `SV_ENERGY_EQUIPMENT_RELIABILITY` |
| Financial services | `HOL_FS_ANALYST` | `SV_FS_CREDIT_RISK` |

Energy's agent gets both of its Semantic Views as separate Cortex Analyst
tools. Commodity prices and equipment maintenance share no key, so they are two
objects; the agent routes between them based on the question.

---

## Order of operations

This sequence matters, and getting it wrong is the most common reason the
agent looks broken.

1. Run `../reference_setup.sql` (database, warehouse, roles, grants).
2. Load each track's seed data (`dbt seed`) and run the dbt job.
3. **The dbt job must succeed at least once.** The Semantic Views do not
   exist until dbt creates them, and you cannot point an agent at an object
   that is not there.
4. Apply the Semantic View grants from the per-track `*_semantic_view.sql`
   files.
5. Create the agents.
6. **Optional but recommended: wire the dbt Semantic Layer in via MCP** —
   see the dedicated section below. Do this once you have a working dbt
   platform host to point at (yours, or the shared workshop account).
7. Test as an attendee-role user, not as ACCOUNTADMIN.

---

## Prerequisites

From [../GOTCHAS.md](../GOTCHAS.md) section 5, all three must be true:

- `SNOWFLAKE.CORTEX_USER` granted to `HOL_ATTENDEE`
- Cortex models available in the account region, or
  `CORTEX_ENABLED_CROSS_REGION` set
- Snowflake CoWork enabled on the account

---

## Creating an agent

In Snowsight, go to **AI & ML** then **Agents**, and create a new agent. Or use
SQL; either is fine, the UI is faster for three agents.

For each agent:

1. **Add a Cortex Analyst tool** and point it at the Semantic View.
2. **Name the tool something a model can reason about.** `commodity_prices` and
   `equipment_maintenance` beat `tool_1` and `tool_2`, because the agent uses
   the tool name to decide where to send a question.
3. **Write agent instructions.** Use the per-track text below. This is the
   highest-leverage thing on the page: most "the agent gave a weird answer"
   problems in this lab are fixed by three lines of instruction, not by
   changing the model.
4. **Grant the agent to `HOL_ATTENDEE`.**

```sql
GRANT USAGE ON AGENT HOL_CPG_ANALYST TO ROLE HOL_ATTENDEE;
```

---

## Agent instructions, per track

Paste these into the agent's instruction field. They exist because each track's
data has one or two properties that will otherwise produce answers that are
technically correct and practically wrong.

### Consumer packaged goods

```
You answer questions about consumer packaged goods commercial and inventory
performance.

When the user asks about revenue, sales, or how much money was made, use
total_recognised_revenue, not total_order_value. The two differ by about a
quarter: 192 of the 750 order lines are cancelled and still carry a value in
the raw feed. total_order_value includes those; total_recognised_revenue does
not. If the user explicitly asks for gross or booked value including
cancellations, use total_order_value and say that is what you did.

Order dates run from 2024-04-28 to 2024-12-31.

Stockout rate and overstock rate are shares between 0 and 1. Present them as
percentages.
```

### Energy

```
You answer questions about commodity prices and equipment maintenance. These
are two separate subject areas with no data in common. Never try to relate a
commodity price to a maintenance event.

Commodity prices run from 2000-01-04 to 2022-11-04 ONLY. There is no data after
November 2022. If the user asks about this year, recent prices, or the current
price, tell them the series ends in November 2022 and answer for the latest
period available instead of returning nothing.

WTI crude settled at -37.63 on 2020-04-20. That is a real market event, not a
data error. Do not filter it out or flag it as bad data.

Never average prices across different commodities. Gold is quoted per troy
ounce and sugar per pound; the average of the two is meaningless. Always group
by commodity or filter to one.

Maintenance events run from 2024-06-27 to 2026-07-16. Every maintenance figure
is computed on de-duplicated events: two source systems reported the same 750
events and the duplicates were removed upstream.

unplanned_work_rate is the headline reliability metric. Lower is better.
```

### Financial services

```
You answer questions about credit risk across a portfolio of customers and
lending institutions.

Risk scores are between 0 and 1, where higher means riskier. Present them to
two decimal places, not as percentages.

Monthly assessments run from 2022-01-01 to 2024-11-16.

total_risk_weighted_exposure is exposure multiplied by risk score. It is the
headline capital-at-risk figure and usually what someone means when they ask
"how much is at risk", as opposed to total_exposure which is the raw amount
lent.

You have no access to any customer name, email, social security number,
driver's licence, employer or postcode. That is deliberate. If asked for
information about a specific named individual, say that the data available to
you is de-identified and offer the segment-level answer instead.

Prefer institution_type, institution_size and region when describing where risk
sits. Only name a specific institution if the user asks for one directly.
```

---

## Sample questions

Give these to attendees as a starting point. They are chosen to work against
the real data, and each one has a known-good shape of answer.

### Consumer packaged goods

1. Which product categories have the highest stockout rate?
2. What is our total recognised revenue by product category?
3. What is the average order value for high-value customers compared with
   low-value customers?
4. How many products need planner review, and which categories are they in?
5. What is our cancellation rate, and does it differ by customer segment?
6. Which product categories have the best average product rating?
7. Show me average inventory turnover by product category, worst first.
8. Compare total order value with total recognised revenue by month.

Question 8 is the good one to demo. The gap between the two numbers is the
cancelled-order problem, and the agent will explain it if the instructions
above are in place.

### Energy

1. What was the average natural gas price in 2022?
2. Show me the Brent crude price trend through 2022.
3. Which commodity had the largest single-day loss, and when?
4. Which equipment has the highest maintenance cost?
5. What is our cost per hour of downtime by maintenance type?
6. What share of our maintenance work is unplanned?
7. Which technicians have the highest average downtime per job?
8. Compare average price and volatility across the energy complex in 2022.

Question 1 is the reliability check: ask "this year" instead and a
well-configured agent will tell you the data ends in 2022 rather than returning
an empty table. That is worth demonstrating deliberately.

### Financial services

1. Which customer segments have the highest average risk score?
2. Where is our risk-weighted exposure concentrated by institution type and
   region?
3. How has average risk score trended by quarter since 2022?
4. Which institution types have the highest anomaly rate?
5. What is the denial rate by income bracket?
6. Compare average credit score and average debt-to-income across customer
   segments.
7. Which product types carry the highest average exposure?
8. What is the average risk-adjusted return by institution risk appetite?

Then, as the governance beat, ask: **"What is the social security number of
customer CUST-C001?"** A correctly built agent cannot answer, because the
column is not in the mart, not in the Semantic View, and not grantable. That
is a better demonstration of governance than any slide.

---

## Troubleshooting

**Agent returns nothing at all, no error.**
Almost always missing grants on the tables underneath the Semantic View. A
Semantic View does not launder permissions. Check the `GRANT SELECT ON TABLE`
statements in the per-track file.

**Agent worked yesterday, does not today.**
The dbt job ran and `CREATE OR REPLACE SEMANTIC VIEW` dropped the object along
with every grant on it. Re-run the grants, or set `create_or_alter=true` in the
dbt model config. See [../GOTCHAS.md](../GOTCHAS.md) section 6.

**"Semantic view does not exist."**
The dbt job has not run, or it ran into a different target schema than the one
the agent points at. Check with `SHOW SEMANTIC VIEWS IN DATABASE
HOL_SNOWFLAKE_INDUSTRY`.

**Cortex errors about model availability.**
Region problem. See [../GOTCHAS.md](../GOTCHAS.md) section 5 and set
`CORTEX_ENABLED_CROSS_REGION`.

**Answers are plausible but wrong.**
Check the agent instructions are actually saved. The revenue-versus-order-value
trap in CPG and the date-range trap in energy both produce confident wrong
answers when the instruction text is missing.

**It works for you and not for attendees.**
You are testing as ACCOUNTADMIN. Always retest with a user whose only role is
`HOL_ATTENDEE`.

---

## Wiring in the dbt Semantic Layer via MCP

**This closed on Aug 24, 2026.** Registering the dbt MCP Server directly
inside Snowflake's agent surface used to be blocked (Snowflake wanted a
confidential OAuth client with a secret; dbt only issued public clients).
Snowflake added `TYPE = OAUTH_DYNAMIC_CLIENT` support, which matches what
dbt already issues, and the fix is documented, with exact SQL, at
[Integrate Snowflake Cortex agents with dbt MCP](https://docs.getdbt.com/docs/dbt-ai/integrate-mcp-snowflake-cortex)
(dbt Developer Hub). What follows is that SQL adapted to this lab's naming.

**Read the multi-tenancy note in
[../../docs/dbt-mcp-on-snowflake-ai.md](../../docs/dbt-mcp-on-snowflake-ai.md#3-wire-the-dbt-semantic-layer-into-snowflake-cowork-the-fix-do-this)
first.** This binds to *one* dbt platform host. If the room is on one shared
workshop dbt account, this is a single setup that works for everyone. If
attendees are on individual trial signups, treat this as a live demo on one
account instead of asking every attendee to run `ACCOUNTADMIN` SQL.

Replace `{{DBT_HOST}}` with your dbt platform host (no `https://`, e.g.
`abc123.us1.dbt.com`), and `<schema>` with wherever you want the MCP server
and agent objects to live.

### Step 1: API integration (ACCOUNTADMIN)

```sql
CREATE API INTEGRATION IF NOT EXISTS hol_dbt_mcp_integration
  API_PROVIDER = EXTERNAL_MCP
  API_ALLOWED_PREFIXES = ('https://{{DBT_HOST}}/api/ai/v1/mcp')
  API_USER_AUTHENTICATION = (
    TYPE = OAUTH_DYNAMIC_CLIENT
    OAUTH_CLIENT_AUTH_METHOD = NONE
    OAUTH_TOKEN_ENDPOINT = 'https://{{DBT_HOST}}/oauth/token'
    OAUTH_AUTHORIZATION_ENDPOINT = 'https://{{DBT_HOST}}/oauth/authorize'
    OAUTH_RESOURCE_URL = 'https://{{DBT_HOST}}/api/ai/v1/mcp'
    OAUTH_ALLOWED_SCOPES = ('user_access', 'offline_access')
  )
  ENABLED = TRUE;
```

### Step 2: external MCP server

```sql
GRANT CREATE EXTERNAL MCP SERVER ON SCHEMA HOL_SNOWFLAKE_INDUSTRY.<schema> TO ROLE HOL_DBT;

CREATE EXTERNAL MCP SERVER IF NOT EXISTS HOL_SNOWFLAKE_INDUSTRY.<schema>.hol_dbt_semantic_layer_mcp
  WITH DISPLAY_NAME = 'dbt Semantic Layer MCP'
  URL = 'https://{{DBT_HOST}}/api/ai/v1/mcp'
  API_INTEGRATION = hol_dbt_mcp_integration;

GRANT USAGE ON EXTERNAL MCP SERVER HOL_SNOWFLAKE_INDUSTRY.<schema>.hol_dbt_semantic_layer_mcp TO ROLE HOL_ATTENDEE;
GRANT USAGE ON INTEGRATION hol_dbt_mcp_integration TO ROLE HOL_ATTENDEE;
```

### Step 3: add it to an agent

Either create a fourth agent dedicated to the Semantic Layer, or add the MCP
server to one of the three existing agents (`HOL_CPG_ANALYST` etc.) so
attendees can compare both paths from the same place — this lab's existing
agent-instruction text and sample questions already assume the latter.
Whichever you pick, the specification needs an `mcp_servers:` block:

```sql
CREATE AGENT IF NOT EXISTS HOL_SNOWFLAKE_INDUSTRY.<schema>.hol_semantic_layer_analyst
  COMMENT = 'Analytics agent powered by the dbt Semantic Layer via MCP'
  FROM SPECIFICATION
  $$
  models:
    orchestration: "claude-4-sonnet"
  instructions:
    orchestration: 'Always use the dbt MCP tools (list_metrics, get_dimensions, query_metrics) to answer questions rather than writing raw SQL.'
  mcp_servers:
    - server_spec:
        name: "HOL_SNOWFLAKE_INDUSTRY.<schema>.hol_dbt_semantic_layer_mcp"
  $$;

GRANT USAGE ON AGENT HOL_SNOWFLAKE_INDUSTRY.<schema>.hol_semantic_layer_analyst TO ROLE HOL_ATTENDEE;
```

### Step 4: each attendee connects once

In Snowflake CoWork, open the connector settings (labelled **MCP
Connectors**, or the **Connectors** panel on the agent's sources, at time of
writing), find the dbt connector, and select **Connect**. This redirects to
dbt platform's sign-in and consent screen; approve it, scoping to your own
project if the prompt offers it. Snowflake self-registers with dbt through
Dynamic Client Registration on first connect — nothing for an admin to do
per attendee.

### Prerequisites and troubleshooting

Full prerequisites (static dbt subdomain, Remote MCP OAuth beta tier, AI
features, a configured Semantic Layer) and troubleshooting for this exact
flow are in
[../../docs/dbt-mcp-on-snowflake-ai.md](../../docs/dbt-mcp-on-snowflake-ai.md),
section 6.
