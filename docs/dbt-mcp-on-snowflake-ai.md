# The dbt MCP Server and Snowflake CoWork

**This now works natively.** As of **August 24, 2026**, dbt Labs published a
supported path to register the dbt MCP Server directly inside Snowflake's
agent surface (Cortex Agents, the layer Snowflake CoWork is built on), so the
dbt Semantic Layer is a first-class tool CoWork can call — not a workaround,
not a separate MCP client. Section 3 below is the exact setup. Read it before
you touch anything else on this page; the rest of the doc (options B/C) is
now the *secondary* path, for MCP clients other than Snowflake.

Source: [Integrate Snowflake Cortex agents with dbt MCP](https://docs.getdbt.com/docs/dbt-ai/integrate-mcp-snowflake-cortex)
(dbt Developer Hub, last updated Aug 24, 2026). Verified by fetching that page
directly, not by search-result summary. Both products are moving quickly —
re-check before each delivery.

**Naming note, not a blocker:** dbt's own page still says "Snowflake
Intelligence," not "Snowflake CoWork." Snowflake rebranded that surface at
Summit 2026, and dbt's docs haven't caught up on the name yet. The mechanism
this page documents (Cortex Agents calling an external MCP server) is the
same regardless of which name the UI shows you. `TODO: verify` the current
UI labels (`ai.snowflake.com` vs. wherever CoWork lives now) with the
Snowflake team, but don't let a label mismatch make you think the underlying
capability isn't there.

---

## 1. What the dbt MCP Server is, and why it is here

Your track defines metrics twice. One copy lives in a Snowflake Semantic View,
which Cortex Analyst reads directly. The other lives in
`models/marts/_<track>__marts.yml` as dbt Semantic Layer (MetricFlow) specs.

The dbt MCP Server is how the second copy gets consumed. It exposes your
metrics, dimensions, model metadata and lineage as MCP tools, so an AI agent
**asks dbt for a governed metric** instead of writing its own SQL against
whatever tables it can see.

> **Want to see that metadata before you wire anything up?** Open dbt Catalog.
> Its discovery tools and Catalog both read the **Discovery API**, so what
> Catalog shows a human is what the MCP Server hands an agent. The guided tour
> is [../dbt/catalog-tour.md](../dbt/catalog-tour.md), and it is section 8 of
> every attendee guide for exactly this reason.

The difference matters more than it sounds.

| | Agent writes SQL against tables | Agent calls a metric through the semantic layer |
|---|---|---|
| Where the definition lives | in the prompt, or invented | in a YAML file, reviewed in a pull request |
| If two people ask the same question | two answers, both plausible | one answer |
| Changing the definition | change every prompt | change one file |
| What it can reach | every table it has grants on | only what the semantic layer exposes |

In the CPG track, this is the difference between an agent that knows revenue
means `total_recognised_revenue` and one that sums `order_total` and overstates
by a quarter. In energy, it is the difference between an agent that uses the
de-duplicated maintenance mart and one that finds `stg_loglynx` and doubles
your costs. In financial services, it is the difference between an answer you
can put in front of a regulator and one you cannot.

### How this compares with the Snowflake Semantic View path

| | Snowflake Semantic View | dbt Semantic Layer via MCP |
|---|---|---|
| Definition lives in | Snowflake, as an object | your dbt repo, in git |
| Consumed by | Cortex Analyst, Snowflake CoWork | Snowflake CoWork (via MCP, see section 3), plus any other MCP client |
| Available to non-Snowflake tools | no | yes |
| Change control | rebuild the dbt model | pull request on the YAML |
| Status in this lab | **fully hands-on, works today** | **fully hands-on, works today — one-time admin setup, then attendees just connect** |

Neither is the winner. If everything you own is in Snowflake, the Semantic View
is closer to the data and simpler. If a metric has to mean the same thing in
Snowflake, a BI tool, a notebook and a Slack bot, the definition needs to live
upstream of all of them.

---

## 2. What you need from your dbt platform account

Collect these before configuring anything. All are in the dbt platform UI.

| Placeholder | Where to find it | Notes |
|---|---|---|
| `{{DBT_HOST}}` | **Account settings → Access URLs** | Full hostname with subdomain, for example `abc123.us1.dbt.com`. Accepts with or without `https://` |
| `{{DBT_TOKEN}}` | **Account settings → Service tokens**, or a personal access token | A service token is enough for Semantic Layer tools. `execute_sql` requires a PAT and does **not** work with a service token |
| `{{DBT_PROD_ENV_ID}}` | The URL of your production environment, or the environment settings page | Numeric |
| `{{DBT_DEV_ENV_ID}}` | Same, for your development environment | Numeric. Only needed for `execute_sql` |
| `{{DBT_USER_ID}}` | Your profile page URL | Numeric. Only needed for `execute_sql` |
| `{{DBT_ACCOUNT_ID}}` | Account settings | Numeric. Required for the Admin API and when using a PAT |

**Also required:** the dbt Semantic Layer must be enabled on your environment,
and you need at least one successful production job run so there is a semantic
manifest to serve. A Semantic Layer with no successful run behind it returns an
empty metric list and looks broken.

**Never commit these.** `{{DBT_TOKEN}}` is a credential.

---

## 3. Wire the dbt Semantic Layer into Snowflake CoWork (the fix, do this)

**What used to block this, and how it got fixed.** Snowflake's
`CREATE EXTERNAL MCP SERVER` used to require a *confidential* OAuth client —
an `OAUTH_CLIENT_ID` plus an `OAUTH_CLIENT_SECRET` — while dbt's remote MCP
server only ever issued *public* clients (dynamic registration per RFC 7591,
or manually registered clients using PKCE per RFC 7636, with no secret).
Separately, dbt's endpoint required an `x-dbt-prod-environment-id` header
that Snowflake's connector had no documented way to send. Two independent
blockers, both closed by the same change: Snowflake added a new API
integration auth type, `TYPE = OAUTH_DYNAMIC_CLIENT` with
`OAUTH_CLIENT_AUTH_METHOD = NONE` — a **public client via Dynamic Client
Registration + PKCE**, exactly what dbt already issues. The header
requirement disappeared too: project scoping now happens during the OAuth
consent step (the connecting user picks which dbt project to expose)
instead of via a header dbt required Snowflake to send.

**Who does this, and when.** This is admin-level Snowflake DDL
(`ACCOUNTADMIN` or a role with account-level `CREATE INTEGRATION`), done
once ahead of the lab — the same category of setup as building the three
Cortex Agents in [`snowflake/cortex_semantic/agents_setup.md`](../snowflake/cortex_semantic/agents_setup.md),
which is where the exact SQL for this lab lives. Attendees don't run this
SQL; they do a one-click OAuth "Connect" afterward. Section 3 here explains
the mechanism and links there for the copy-pasteable steps.

### A multi-tenancy caveat, said plainly

The Snowflake object this creates (`CREATE EXTERNAL MCP SERVER`) points at
**one dbt platform host** (`{{DBT_HOST}}`). If this workshop's room is on
**one shared dbt platform account** (the `{{DBT_WORKSHOP_URL}}` path in
[account-setup.md](account-setup.md), with pre-created developer seats),
this is a **single one-time setup that works for the whole room** — each
attendee's OAuth consent scopes the connection to *their own* dbt project,
so everyone gets their own track's metrics through the same Snowflake
object. If instead attendees are on **their own individual dbt trial
signups** (different hosts each), each would need their own Snowflake
external MCP server pointing at their own host — not something to set up
live for 30 people. In that case, treat this as a **facilitator-led live
demo** on one account (yours, or the shared fallback account) rather than a
per-attendee exercise, and point interested attendees at this page to try it
on their own accounts afterward.

### The mechanism, in short

1. **Snowflake, `ACCOUNTADMIN`:** `CREATE API INTEGRATION` with
   `API_PROVIDER = EXTERNAL_MCP` and
   `API_USER_AUTHENTICATION = (TYPE = OAUTH_DYNAMIC_CLIENT, OAUTH_CLIENT_AUTH_METHOD = NONE, ...)`,
   pointing at dbt's OAuth token/authorization endpoints and its MCP
   resource URL.
2. **Snowflake:** `CREATE EXTERNAL MCP SERVER` on that integration, pointing
   at `https://{{DBT_HOST}}/api/ai/v1/mcp`.
3. **Snowflake:** `CREATE AGENT`, or update an existing one (like the three
   Cortex Agents this lab already builds), adding an `mcp_servers:` block in
   its specification pointing at that MCP server. Grant `USAGE` on the MCP
   server and the integration to `HOL_ATTENDEE`.
4. **Each attendee, once:** in Snowflake CoWork's connector settings, find
   the dbt connector and select **Connect**. This opens dbt platform's
   sign-in and consent screen; approve it, optionally scoping to your own
   project. Snowflake self-registers with dbt through Dynamic Client
   Registration on first connect — no admin action needed per attendee.

Full copy-pasteable SQL, prerequisites (a static dbt subdomain; Remote MCP
OAuth is public beta on Starter/Enterprise-tier dbt accounts; AI features and
a configured Semantic Layer), and troubleshooting are in
[`snowflake/cortex_semantic/agents_setup.md`](../snowflake/cortex_semantic/agents_setup.md).

---

## 4. The other path: dbt MCP in a non-Snowflake MCP client

Section 3 is how CoWork gets the dbt Semantic Layer natively. This section is
for a different question: wiring the same dbt MCP Server into a general-
purpose MCP client (Claude Desktop, Cursor, VS Code) instead of, or alongside,
Snowflake. Do it after the lab, or during if you are ahead.

### Option A: remote MCP with OAuth (simplest)

Works with any client that supports dynamic client registration, which includes
Claude Desktop, Claude Code, Cursor and VS Code.

Your MCP endpoint is:

```
https://{{DBT_HOST}}/api/ai/v1/mcp/
```

You can also copy it from **Account settings → Access URLs → MCP Endpoint URL**.

Add it in your client as an HTTP MCP server with that URL and no credentials.
The first connection opens a browser for sign-in and the client self-registers.

> **Requires a static subdomain.** OAuth with the remote MCP server is only
> available to accounts with a static subdomain, for example the `abc123` in
> `abc123.us1.dbt.com`. If your workshop account has a generic host, use
> option B.

### Option B: remote MCP with a token

For clients that let you set custom headers.

| Header | Value |
|---|---|
| `Authorization` | `Token {{DBT_TOKEN}}` or `Bearer {{DBT_TOKEN}}` |
| `x-dbt-prod-environment-id` | `{{DBT_PROD_ENV_ID}}` |
| `x-dbt-dev-environment-id` | `{{DBT_DEV_ENV_ID}}` (only for `execute_sql`) |
| `x-dbt-user-id` | `{{DBT_USER_ID}}` (only for `execute_sql`) |

### Option C: self-hosted, with the Semantic Layer tools only

Run it locally with `uvx`. This config enables the Semantic Layer tools and
nothing else, which is the right shape for this lab: you want the agent asking
for metrics, not writing SQL.

```json
{
  "mcpServers": {
    "dbt": {
      "command": "uvx",
      "args": ["dbt-mcp"],
      "env": {
        "DBT_HOST": "{{DBT_HOST}}",
        "DBT_TOKEN": "{{DBT_TOKEN}}",
        "DBT_PROD_ENV_ID": "{{DBT_PROD_ENV_ID}}",
        "DBT_ACCOUNT_ID": "{{DBT_ACCOUNT_ID}}",

        "DBT_MCP_ENABLE_SEMANTIC_LAYER": "true"
      }
    }
  }
}
```

**Read this before you copy it.** dbt's MCP server has two configuration modes
and mixing them silently breaks things.

- **Disable mode (the default).** Everything is on except SQL, codegen and
  server metadata. You turn things off with `DISABLE_SEMANTIC_LAYER=true`,
  `DISABLE_DISCOVERY=true` and so on.
- **Enable mode (an allowlist).** Setting any `DBT_MCP_ENABLE_*=true` switches
  to allowlist behaviour: only what you explicitly enabled is on.

The config above uses enable mode deliberately, so the agent gets Semantic
Layer tools and nothing else.

**Do not mix the two for the same toolset**, and **never leave an empty
`DBT_MCP_ENABLE_*=` line**: an empty value still activates enable mode and
silently disables every other toolset. That failure looks exactly like "the
server started but has no tools".

Two Semantic Layer tuning variables worth knowing:

| Variable | Default | What it does |
|---|---|---|
| `DBT_MCP_SL_METRICS_RELATED_MAX` | `10` | How many metrics `list_metrics` returns inline with their dimensions and entities. Raising it means fewer round trips; `0` returns metrics only |
| `DBT_MCP_SL_MAX_RESPONSE_CHARS` | `16000` | Character cap on the `list_metrics` response. `0` disables trimming |

Your track defines between 20 and 28 metrics, so the default of 10 means the
agent will make extra tool calls to discover dimensions. Raising it to `30` is
reasonable here.

Source: [MCP environment variables](https://docs.getdbt.com/docs/dbt-ai/mcp-environment-variables).

---

## 5. Verify it works

Whether you connected through Snowflake CoWork (section 3) or a separate MCP
client (section 4), ask the agent to list what it can see. You should get
your track's metrics by name.

**Expected result:** the metric names from `models/marts/_<track>__marts.yml`.

| Track | Metrics you should see include |
|---|---|
| Consumer packaged goods | `total_recognised_revenue`, `average_order_value`, `cancellation_rate`, `average_stockout_rate`, `share_of_products_needing_review` |
| Energy | `average_commodity_price`, `unplanned_work_rate`, `cost_per_downtime_hour`, `maintenance_completion_rate` |
| Financial services | `average_risk_score`, `total_risk_weighted_exposure`, `anomaly_rate`, `approval_rate`, `unassessed_collateral_rate` |

Then ask the same questions you asked Cortex Analyst:

- **CPG:** "What is total recognised revenue by product category?"
- **Energy:** "What is the unplanned work rate by maintenance type?"
- **Financial services:** "What is average risk score by institution type?"

### How to tell the answer came through the semantic layer

This is the part worth checking, because an agent with warehouse access can
answer the same question the wrong way and look identical.

1. **Watch the tool calls.** A governed answer shows `list_metrics` and
   `query_metrics` in the trace. If you see `execute_sql` or raw SQL, it went
   around the semantic layer.
2. **Ask for a metric that does not exist.** "What is the average shipping cost
   by carrier?" A governed agent says it has no such metric. An agent writing
   its own SQL will try to invent one.
3. **Compare against Cortex Analyst.** Ask both. In CPG the revenue figures
   should agree. In energy and financial services, `risk_score_volatility` and
   `price_volatility` will differ slightly between the two paths, and that is
   expected and documented: MetricFlow has no standard-deviation aggregation.
   Finding that difference is itself proof you went through two different
   definitions.

---

## 6. Troubleshooting

**(Section 3, CoWork) The connector won't authorize, or the OAuth flow fails.**
Confirm the dbt account has a static subdomain — OAuth with MCP requires one.
Check that the host in `API_ALLOWED_PREFIXES`, `OAUTH_TOKEN_ENDPOINT`,
`OAUTH_AUTHORIZATION_ENDPOINT` and `OAUTH_RESOURCE_URL` all match `{{DBT_HOST}}`
exactly, and that the integration is `ENABLED = TRUE`. Confirm AI features and
Remote MCP OAuth are available on the dbt account's tier (public beta,
Starter/Enterprise only at time of writing).

**(Section 3, CoWork) The agent returns no metrics or empty results.**
Confirm the dbt project you authorized has a configured Semantic Layer with
metrics and dimensions, that the connecting user has at least read-only
access to that project, and — if you scoped the OAuth connection to one
project — that it's the project containing your metrics.

**(Section 3, CoWork) Permission errors creating the integration or MCP server.**
`CREATE API INTEGRATION` and `CREATE EXTERNAL MCP SERVER` need `ACCOUNTADMIN`
or a role with account-level `CREATE INTEGRATION`. Run those as
`ACCOUNTADMIN`, then grant `USAGE` on the MCP server and integration to the
role that runs the agent.

**The server starts but exposes no tools.**
Almost always the enable-mode trap. Check for an empty `DBT_MCP_ENABLE_*=`
line. An empty value activates allowlist mode and disables everything else.

**"Unauthorized" or 401.**
Check `{{DBT_TOKEN}}` first. Then check `{{DBT_ACCOUNT_ID}}` is set, which is
required when the token is a PAT. Then check the `Authorization` header format:
it is `Token <value>` or `Bearer <value>`, not the bare token.

**Metric list is empty but the server connects.**
Three candidates, in order of likelihood. The Semantic Layer is not enabled on
the environment. `{{DBT_PROD_ENV_ID}}` points at an environment with no
successful run, so there is no semantic manifest to serve. Or it points at your
development environment instead of production, which is the easiest mistake to
make because both IDs look the same.

**Some metrics appear, others do not.**
You are probably hitting `DBT_MCP_SL_MAX_RESPONSE_CHARS`, which trims the
response at 16,000 characters by default. Financial services defines 28 metrics
with long descriptions. Set it to `0` to disable trimming.

**`execute_sql` fails but everything else works.**
It requires a PAT, not a service token, plus `{{DBT_DEV_ENV_ID}}` and
`{{DBT_USER_ID}}`. Nothing in this lab needs it.

**OAuth will not connect to the remote server.**
Check the account has a static subdomain. Without one, OAuth against the remote
MCP endpoint is unavailable and you need option B or C.

**Networking or timeouts on a self-hosted server.**
`uvx dbt-mcp` runs over stdio by default, so if the client is on the same
machine there is nothing to reach. If you have set `MCP_TRANSPORT` to
`streamable-http`, note that the documentation describes that as being for
local debugging only.

**The agent answers, but the number is wrong.**
Check it went through the metric path rather than writing its own SQL. See
section 5. This is the failure mode the whole exercise exists to make visible.

---

## 7. Sources

- [Integrate Snowflake Cortex agents with dbt MCP](https://docs.getdbt.com/docs/dbt-ai/integrate-mcp-snowflake-cortex) — the fix, last updated Aug 24, 2026. Primary source for section 3; fetched and read in full, not summarized from search results
- [About the dbt MCP server](https://docs.getdbt.com/docs/dbt-ai/about-mcp)
- [MCP environment variables](https://docs.getdbt.com/docs/dbt-ai/mcp-environment-variables)
- [Set up remote MCP](https://docs.getdbt.com/docs/dbt-ai/setup-remote-mcp)
- [Set up self-hosted MCP](https://docs.getdbt.com/docs/dbt-ai/setup-local-mcp)
- [Snowflake MCP Connectors](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp-connectors)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Snowflake Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
