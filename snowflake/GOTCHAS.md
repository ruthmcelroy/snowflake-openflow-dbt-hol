# Snowflake setup gotchas for a dbt lab

**Audience: whoever on the Snowflake side is standing up the account for this
lab. Fifteen minutes of reading that will save an afternoon.**

None of this is about Snowflake being hard. It is about the specific seams
between dbt and Snowflake, which is where labs like this actually break. They
are ordered by how often they bite, not by how interesting they are.

Verified against Snowflake documentation in August 2026. Numbers 1 and 5 have
both moved recently; re-check them before each delivery.

**Note for anyone who ran an earlier delivery of this lab:** this version
loads raw data with a `dbt seed` per industry track instead of a live
Fivetran connector. That removed two gotchas that used to be here entirely —
identifier casing and Fivetran destination privileges — because both were
specific to variance in how a live ingestion tool lands data, which a seed
doesn't have. See `../openflow/openflow-overview.md` for what a real
production ingestion layer (Openflow) would look like if you're standing this
up for more than a two-hour lab.

---

## 1. Password-only service accounts are being switched off right now

This is first because the enforcement window is open as you read this.

Snowflake is deprecating single-factor password sign-ins in three phases. The
final phase, **August to October 2026**, enforces across all users and
accounts, and existing `TYPE = LEGACY_SERVICE` users are converted to
`TYPE = SERVICE`, which **blocks password authentication entirely**. From phase
2 (May to July 2026), `TYPE = LEGACY_SERVICE` is already an invalid option on
`CREATE USER` and `ALTER USER`.

Source: [Deprecation of single-factor password sign-ins](https://docs.snowflake.com/en/user-guide/security-mfa-rollout).

**What this means for you:** if you create the dbt service user with a
password and nothing else, it may work when you test it and stop working
before the lab. Use key-pair authentication.

```sql
-- Generate the key pair outside Snowflake:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out dbt_key.p8 -nocrypt
--   openssl rsa -in dbt_key.p8 -pubout -out dbt_key.pub
-- Then strip the BEGIN/END lines and all newlines from the .pub file.

CREATE USER IF NOT EXISTS DBT_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = HOL_DBT
  DEFAULT_WAREHOUSE = HOL_DBT_WH
  RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...';
```

**Where the private key goes:** in the dbt platform's Snowflake connection,
choose key-pair and paste the private key. If you generated it with a
passphrase, dbt platform has a separate field for that. Generating without a
passphrase (`-nocrypt` above) is simpler for a lab.

Two things people trip on. `RSA_PUBLIC_KEY` wants the base64 body only, with
the `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----` lines and every
newline removed. And key rotation uses `RSA_PUBLIC_KEY_2`, which is worth
knowing but irrelevant for a one-day lab.

Programmatic access tokens (PATs) exist as a drop-in password replacement for
applications that cannot do key-pair. Key-pair is still the better answer
here.

---

## 2. Future grants, or attendees cannot see what dbt just created

**This is the single most common breakage in a lab like this, and it presents
as the least helpful error message: "object does not exist, or operation
cannot be performed".**

Each attendee's dbt platform project creates its own development schema
(`dbt_<firstname>`) the first time they build, and later a production schema
too. Both are owned by the `HOL_DBT` role. Unless you've said otherwise in
advance, a brand-new schema is invisible to `HOL_ATTENDEE` — grants on
objects that exist today say nothing about objects created tomorrow, and dbt
creates a new one per attendee.

Two separate mistakes hide in here:

**Mistake one: no future grants at all.** You grant `SELECT` on the schemas
you can see, the demo works for the first attendee, then the second
attendee's `dbt build` creates their own schema and `HOL_ATTENDEE` cannot read
it.

**Mistake two: future grants only, forgetting that they are not retroactive.**
You add `ON FUTURE TABLES`, congratulate yourself, and the schemas dbt already
created before you ran the grant stay invisible. You need both.

```sql
-- Future schemas, at the database level. Needed because each attendee's
-- dbt platform project creates its own development schema.
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
GRANT SELECT ON FUTURE TABLES  IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
GRANT SELECT ON FUTURE VIEWS   IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;

-- And the same for what already exists. Future grants are NOT retroactive.
GRANT USAGE  ON ALL SCHEMAS IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
GRANT SELECT ON ALL TABLES  IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
GRANT SELECT ON ALL VIEWS   IN DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
```

One more trap: **database-level future grants and schema-level future grants
do not stack.** If someone has already set `ON FUTURE TABLES IN SCHEMA
<something>`, that more specific grant wins for that schema and the
database-level one is ignored there. Check with:

```sql
SHOW FUTURE GRANTS IN DATABASE HOL_SNOWFLAKE_INDUSTRY;
```

**Verify before the room fills up.** Run this as `HOL_ATTENDEE`, not as
ACCOUNTADMIN, which can see everything and will tell you nothing:

```sql
USE ROLE HOL_ATTENDEE;
SELECT COUNT(*) FROM HOL_SNOWFLAKE_INDUSTRY.dbt_hicham.stg_cpg_records;
```

---

## 3. Warehouse strategy

One XS warehouse is genuinely enough:

```sql
CREATE WAREHOUSE IF NOT EXISTS HOL_DBT_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
```

The largest seed table in this lab is roughly 25k rows and the whole DAG
builds in seconds. There's no separate ingestion warehouse to reason about
this time — attendees load their own seed data with `dbt seed` on this same
warehouse, so there's nothing running in the background that could keep it
warm unexpectedly the way a polling connector used to.

**After the lab:** suspend it, and consider dropping the attendee dev
schemas. Thirty people times one schema each adds up.

---

## 4. Network policies and IP allowlists

If the account has a network policy, the dbt platform needs to be allowed
through, and the failure mode is a connection that hangs and then times out
rather than one that says "blocked".

- **dbt platform** publishes its egress IPs per region, and you only need
  these if you are applying IP restrictions.

For a one-day lab in a Snowflake office, the pragmatic answer is usually to
run the lab account without a restrictive network policy. If the account is
shared with anything real, that is not an option, and PrivateLink is the
enterprise answer but is far too much setup for a workshop.

**If you stand this pipeline up for real with live Openflow ingestion**
(this lab's seeds skip that — see `../openflow/openflow-overview.md`),
Openflow's managed runtime, whether Snowflake-hosted or BYOC, has its own
network requirements. `TODO: verify with the Snowflake team` — nobody on this
project has configured that for a production deployment, so treat it as an
open question rather than a documented gotcha.

---

## 5. Cortex availability, region, and the role nobody grants

Three separate things have to be true before Cortex Analyst answers a question,
and trial accounts routinely fail the second one.

**The role.** Cortex functions require `SNOWFLAKE.CORTEX_USER`. It is granted
to `PUBLIC` by default in most accounts, but if someone has revoked it, or in a
hardened account, nothing works and the error is about privileges rather than
about Cortex.

```sql
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE HOL_ATTENDEE;
```

**The region.** Cortex models are not available in every region, and a trial
account signed up on the day lands wherever the person clicking the button
happened to land. If the model is not available locally, enable cross-region
inference. The parameter name is easy to get slightly wrong:

```sql
-- Note: CORTEX_ENABLED_CROSS_REGION, not CORTEX_ENABLE_CROSS_REGION.
-- ACCOUNTADMIN only. Cannot be set at user or session level.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
```

Valid values include `ANY_REGION`, `AWS_GLOBAL`, `AZURE_GLOBAL`, `GCP_GLOBAL`,
geography-scoped values such as `AWS_US` and `AWS_EU`, and `DISABLED`. Source:
[Cross-region inference](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cross-region-inference).

Be deliberate about which value you pick. `ANY_REGION` will send inference
requests outside the account's home geography, which is a straightforward
conversation for a synthetic-data lab and a much longer one if anyone assumes
the same setting is fine in production.

**Snowflake CoWork needs its own enablement.** It is not automatically on
just because Cortex functions work. Turn it on and confirm you can reach it
with the lab role well before the day. `TODO: verify with the Snowflake
team`: this lab was built under the "Snowflake Intelligence" name at
`ai.snowflake.com`; Snowflake rebranded that surface to **Snowflake CoWork**
at Summit 2026, and this repo hasn't been hands-on-verified against the
renamed product. Confirm the current URL and enablement steps before relying
on any of the screenshots or instructions here.

**Flag region problems early.** If attendees create their own trial accounts on
the morning, some of them will land in a region without the models, and you
want to discover that at 09:05 rather than at 11:30 when the room reaches the
consumption section.

---

## 6. Semantic View and Cortex privileges

The Semantic Views in this lab are created by dbt, using the
[Snowflake-Labs/dbt_semantic_view](https://hub.getdbt.com/Snowflake-Labs/dbt_semantic_view/latest/)
package. That means they are owned by the dbt role, not by whoever is asking
questions in Snowflake CoWork. Those are different identities and the
grants do not happen by themselves.

For Cortex Analyst to read a Semantic View, the querying role needs `SELECT` on
the Semantic View and `USAGE` on its database and schema, **plus** access to the
underlying tables the view references. A Semantic View does not launder
permissions: a role that cannot read `fs_monthly_risk_assessment` cannot get at
it through `sv_fs_credit_risk` either.

```sql
GRANT USAGE ON DATABASE HOL_SNOWFLAKE_INDUSTRY TO ROLE HOL_ATTENDEE;
GRANT USAGE ON SCHEMA   HOL_SNOWFLAKE_INDUSTRY.<dbt_target_schema> TO ROLE HOL_ATTENDEE;
GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA HOL_SNOWFLAKE_INDUSTRY.<dbt_target_schema> TO ROLE HOL_ATTENDEE;
GRANT SELECT ON ALL TABLES         IN SCHEMA HOL_SNOWFLAKE_INDUSTRY.<dbt_target_schema> TO ROLE HOL_ATTENDEE;

-- dbt rebuilds these on every run, so cover what it creates next time too.
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA HOL_SNOWFLAKE_INDUSTRY.<dbt_target_schema> TO ROLE HOL_ATTENDEE;
GRANT SELECT ON FUTURE TABLES         IN SCHEMA HOL_SNOWFLAKE_INDUSTRY.<dbt_target_schema> TO ROLE HOL_ATTENDEE;
```

**The rebuild trap.** By default the package issues `CREATE OR REPLACE SEMANTIC
VIEW`, which drops the object and takes every grant on it with it. Attendees
then find that the agent worked before lunch and does not after. Two ways out:
set `create_or_alter=true` in the model config, or set `copy_grants=true`.
Note that Snowflake does not support `COPY GRANTS` with `CREATE OR ALTER`, so
these are alternatives rather than a belt-and-braces pair. For a lab, re-running
the grant statements after the dbt job is the simplest thing that works.

**Empty agent, no error.** If Cortex Analyst returns nothing at all rather than
an error, missing grants on the underlying tables is the first thing to check.
It frequently looks like a modelling problem and is almost always a grant.

---

## 7. Wiring the dbt Semantic Layer in via MCP (fixed Aug 24, 2026 — do this)

This used to be the one thing the Snowflake side couldn't fix: registering
the dbt MCP Server directly inside Snowflake's agent surface required a
confidential OAuth client with a secret, and dbt's remote MCP server only
ever issued public clients. **That's resolved.** Snowflake added
`TYPE = OAUTH_DYNAMIC_CLIENT` support for external MCP server integrations —
a public client via Dynamic Client Registration + PKCE, exactly what dbt
issues — so this is now a real, admin-configurable integration rather than a
documented gap.

Exact SQL (`CREATE API INTEGRATION`, `CREATE EXTERNAL MCP SERVER`, adding
`mcp_servers:` to an agent spec) is in
[`cortex_semantic/agents_setup.md`](cortex_semantic/agents_setup.md#wiring-in-the-dbt-semantic-layer-via-mcp).
One thing worth knowing before you set it up: it binds to *one* dbt platform
host, so it's a single one-time setup if the room shares a workshop dbt
account, but a per-account thing if attendees are on individual trials —
see that page for the multi-tenancy note.

---

## Pre-flight checklist

Run through this the day before, not the morning of.

- [ ] `HOL_SNOWFLAKE_INDUSTRY` database exists
- [ ] `HOL_DBT_WH` exists, XS, auto-suspend 60
- [ ] `DBT_SVC` is `TYPE = SERVICE` with `RSA_PUBLIC_KEY` set
- [ ] The private key is loaded into the dbt platform, and the connection tests green
- [ ] Future grants set at the **database** level for `HOL_ATTENDEE`, and `SHOW FUTURE GRANTS` shows no conflicting schema-level grants
- [ ] Grants on **existing** objects set as well
- [ ] `HOL_DBT` has `CREATE SCHEMA` on the database, so each attendee's dev schema can be created
- [ ] `SNOWFLAKE.CORTEX_USER` granted to the attendee role
- [ ] Cortex model availability confirmed in the account region, or `CORTEX_ENABLED_CROSS_REGION` set
- [ ] Snowflake CoWork enabled and reachable with the lab role — `TODO: verify` the current URL/enablement steps under the CoWork rebrand
- [ ] Semantic View grants applied **after** the dbt job has run at least once
- [ ] One end-to-end question answered in Snowflake CoWork, signed in as an attendee-role user rather than as ACCOUNTADMIN
- [ ] dbt Semantic Layer wired in via MCP (section 7) — optional, but it's the highlight moment of the consumption section now that it works
