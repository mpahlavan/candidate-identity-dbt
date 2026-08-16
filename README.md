# Jobylon DataForge — Unified Candidate Identity

A dbt project that resolves candidate identity across three separate Jobylon products — CRM, ATS, and Survey — into a single analytics surface.

> [!IMPORTANT]
> **Status: identity resolution and the attributes table are rebuilt. The project has not yet been run against a warehouse.**
>
> Identity is now a minted surrogate over `(customer_id, email)` rather than the per-system `candidate_id`, which resolves the cross-system collision and the cross-tenant merge. `dbt parse` and the unit tests register cleanly, but no model has executed against Snowflake — the `raw` database has not been loaded. One issue is deliberately left open — see [Remaining](#remaining).

---

## The problem

Each product stores its own candidate records. The same person can appear in all three with different attributes, different completeness, and conflicting values for the same field. There is no shared identity layer, so questions that cross product boundaries can't be answered:

- Which candidates exist in more than one system?
- What share of ATS candidates have also responded to a survey?
- Filter all candidates by department, recruiter, or hiring manager — regardless of which product holds that field.

On top of that, the warehouse is multi-tenant: every customer's data sits in shared tables, and no query may ever leak across tenants. This is enforced structurally, by making `customer_id` part of the identity key — see [below](#identity-resolution-what-the-key-must-be).

## What this builds

A layered dbt project that unions the three systems, resolves field-level conflicts down to one row per candidate, and exposes a small star schema built around a candidate identity hub.

```mermaid
flowchart LR
    subgraph raw["raw.public"]
        R1[crm_candidates]
        R2[ats_candidates]
        R3[ats_jobs]
        R4[srv_applicants]
    end

    subgraph stg["staging — views"]
        S1[stg_crm_candidates]
        S2[stg_ats_candidates]
        S3[stg_ats_jobs]
        S4[stg_srv_applicants]
    end

    subgraph int["intermediate — ephemeral"]
        I1[int_identity_unioned]
        I2[int_identity_deduped]
        I3[int_candidate_system_bridge]
    end

    subgraph marts["marts — tables"]
        M1[dim_candidate]
        M2[dim_candidate_attributes]
        M3[fct_candidate_presence]
    end

    R1 --> S1 --> I1
    R2 --> S2 --> I1
    R3 --> S3
    R4 --> S4 --> I1
    I1 --> I2 --> M1 --> M3
    I1 --> I3
    S1 --> M2
    S2 --> M2
    S3 --> M2
    S4 --> M2
```

## Layers

| Layer           | Materialization | Responsibility                                                                                    |
| --------------- | --------------- | ------------------------------------------------------------------------------------------------- |
| `staging/`      | view            | One model per source table. Rename, cast, stamp `source_system`. No business logic.               |
| `intermediate/` | ephemeral       | Union the systems, then resolve conflicts. Split into two steps so each is testable in isolation. |
| `marts/`        | table           | The analytics surface. Stable and documented.                                                     |

### Why intermediate is split in two

`int_identity_unioned` does the `UNION ALL` and nothing else, so you can assert that its row count equals the sum of the three staging models. `int_identity_deduped` does only the window-function conflict resolution, so you can assert the identity key is unique there. When something breaks, the failing test tells you which step broke.

### Identity resolution: what the key must be

The assignment's Appendix A declares `candidate_id: int (primary key)` **separately** on `crm_candidates`, `ats_candidates`, and `srv_applicants`. These are three independent surrogate keys in three independent systems. Nothing in the brief makes them a shared identifier, and the brief names **email** as the cross-system common denominator.

The correct identity key is therefore a minted surrogate:

```sql
{{ dbt_utils.generate_surrogate_key([
    'customer_id',
    "coalesce(email, source_system || ':' || source_candidate_id::varchar)"
]) }} AS candidate_sk
```

`customer_id` belongs in the key because the warehouse is multi-tenant: the same email under two customers is two distinct candidate records, not one. Each system's native `candidate_id` is then an *attribute*, preserved per-system in `int_candidate_system_bridge`.

The `coalesce` is load-bearing: `generate_surrogate_key` renders NULL as a literal string, so without a fallback every candidate lacking an email would hash identically and collapse into a single person. Falling back to the native per-system id keeps them distinct. Email arrives already lowercased and trimmed from the staging layer.

Because `customer_id` is an input to the key, a partition can never span tenants. That is what prevents one customer's department and recruiter landing on another customer's hub row — a guarantee the `tenant_filter()` macro cannot provide on its own, since it runs downstream of the dedup.

## Models

| Model                         | Grain                         | Purpose                                                                                                                       |
| ----------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `int_identity_unioned`        | candidate × system            | Every appearance of every candidate, un-deduplicated.                                                                         |
| `int_identity_deduped`        | candidate                     | One row per candidate, conflicts resolved, system-presence flags set.                                                         |
| `int_candidate_system_bridge` | candidate × customer × system | Preserves the full mapping the hub collapses, and the home for each system's native `candidate_id`.                           |
| `dim_candidate`               | candidate                     | The identity hub. A thin materialization over the deduped model, so dedup logic can change without breaking downstream contracts. |
| `dim_candidate_attributes`    | candidate × attribute         | Key-value store for extensible attributes.                                                                                    |
| `fct_candidate_presence`      | candidate                     | Pre-aggregated system presence plus a bitmask, for fast overlap analytics.                                                    |

### Conflict resolution: most-recent-non-null

When two systems disagree on a field, the most recent non-null value should win — per field, not per row. A candidate whose ATS record is newer but has no phone number should still keep the phone number from their older CRM record. The intent is expressed with `FIRST_VALUE(... IGNORE NULLS)` windows partitioned by the identity key and ordered by `source_timestamp DESC`.

Each window carries an explicit `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING` frame. This is not decoration: `FIRST_VALUE` defaults to a frame ending at the current row, which — combined with keeping the first row of the same ordering — makes every window see only its own row and stop coalescing entirely. That failure mode is silent, so two tests guard it: a unit test whose newest row is deliberately NULL in fields an older row fills, and `assert_dedup_preserves_non_null`, which asserts on real data that no field is NULL in the hub when any system supplied a value.

`email` and `customer_id` need no windowing, since both are inputs to the key and therefore constant within a partition.

### Extensibility: the attributes table

The brief anticipates 50+ future filterable fields (country, city, brand, …). Adding those as columns on the hub means a schema migration per field. Instead, `dim_candidate_attributes` stores them as rows:

```sql
SELECT candidate_id, attribute_value AS country
FROM dim_candidate_attributes
WHERE attribute_name = 'country'
```

Adding a new attribute becomes an insert, not a migration. The hub stays narrow and fast.

The table is keyed on `candidate_sk`, so it joins `dim_candidate` directly, and carries `customer_id` so `tenant_filter()` applies to it like every other mart. Its grain is deliberately multi-valued — one row per `(candidate_sk, source_system, attribute_name, attribute_value)` — so a candidate with two recruiters keeps both, and two systems may disagree about an attribute without either value being lost.

> [!WARNING]
> Attribute **names** are not yet reconciled across systems ([issue 8](#8-the-attribute-namespace-doesnt-line-up)). Key shape is normalized — case and spacing, so `'Hiring manager'` becomes `hiring_manager` — but vocabulary is not: CRM and ATS say `department_name` where Survey says `department`. The query above therefore still needs to know which system it is asking about.

### System presence and the bitmask

`fct_candidate_presence` encodes presence as `1=crm, 2=ats, 4=srv`, so overlap questions become integer filters instead of three-way boolean logic — `system_bitmask = 3` is exactly "in CRM and ATS, not in Survey".

These flags are only as trustworthy as the identity key, which is why the surrogate matters: on the per-system `candidate_id` the bitmask reported near-total overlap that was purely an artifact of ID ranges coinciding.

## Tenant isolation

Every mart carries `customer_id`, and queries are scoped through the `tenant_filter()` macro:

```sql
SELECT * FROM {{ ref('dim_candidate') }}
{{ tenant_filter() }}
```

Set the tenant at run time:

```bash
dbt run --vars '{"tenant_id": 123}'
```

With `tenant_id` unset the macro emits nothing, so unscoped builds and CI runs work normally.

| Pattern                                      | Isolation | Query simplicity | Cross-tenant analytics      | Best for                   |
| -------------------------------------------- | --------- | ---------------- | --------------------------- | -------------------------- |
| **A — `customer_id` column** _(implemented)_ | Medium    | Simple           | Easy                        | Teams getting started      |
| **B — row-level security**                   | Strong    | Simplest         | Possible with elevated role | Snowflake shops            |
| **C — schema per tenant**                    | Strongest | Simple           | Hard                        | Compliance-heavy use cases |

Pattern A is what this project implements. **Pattern B is the production upgrade path**: a Snowflake secure view filters on the session's tenant, so the application never writes the predicate itself and can't forget to.

> [!WARNING]
> Worth noting why the macro alone was never sufficient. It runs *downstream* of the dedup, so while the partition could span tenants the hub row was already corrupted before any filter ran — filtering on the winning `customer_id` would happily serve another tenant's department and recruiter. The fix belongs in the key, not the filter, which is why `customer_id` is an input to `candidate_sk`.

## Testing

**Source level** — `_sources.yml` declares freshness thresholds (warn at 24h, error at 48h) and primary-key tests on all four raw tables.

**Generic** — `email_format` is a reusable custom test applied to any email column.

**Singular** — business rules that don't fit a column test:

| Test                              | Asserts                                                                                  |
| --------------------------------- | ---------------------------------------------------------------------------------------- |
| `assert_no_orphan_candidates`     | Every candidate appears in at least one system.                                          |
| `assert_customer_id_consistency`  | No candidate spans multiple customers. Runs against the **unioned** model — against the deduped model it could never fail. |
| `assert_email_dedup_integrity`    | Within a customer, one email maps to one candidate. Scoped by `customer_id`, since two customers can legitimately share `info@company.com`. |
| `assert_dedup_preserves_non_null` | If any system supplied a value, the hub is not NULL for that field.                      |

**Unit tests** — `_unit_tests.yml` runs fixtures without any warehouse data:

| Unit test                                     | Asserts                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------- |
| `dedup_keeps_most_recent_non_null`            | Coalescing reaches across the partition; the newest row's NULLs don't win.  |
| `same_email_different_customers_stay_distinct` | The same address under two customers mints two keys.                       |

## Getting started

**Requirements:** Python 3.9+ and a Snowflake account. The models use Snowflake-specific SQL (`LATERAL FLATTEN`, `variant:path` access), so the adapter is not interchangeable.

**1. Install:**

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
dbt deps
```

**2. Configure credentials.** `profiles.yml` lives in the project root and reads every value from the environment, so no secrets enter the repo:

```bash
cp .env.example .env      # then fill in account, user, password
set -a && source .env && set +a
dbt debug                 # confirms the connection before you build
```

The account identifier is in Snowsight under **Account → View account details** (format `ORGNAME-ACCOUNTNAME`). Role, warehouse, database, and schema default to what a fresh trial provides.

**3. Build:**

```bash
dbt source freshness      # check raw data recency
dbt build                 # run models + tests in dependency order
dbt docs generate && dbt docs serve
```

Scoped to a single tenant:

```bash
dbt build --vars '{"tenant_id": 123}'
```

## Layout

```
.
├── dbt_project.yml
├── packages.yml                      # dbt_utils, dbt_expectations
├── package-lock.yml                  # pinned package versions (committed)
├── profiles.yml                      # env-var based; safe to commit
├── requirements.txt                  # dbt-core + dbt-snowflake
├── .env.example                      # credential template (copy to .env)
├── macros/
│   ├── tenant_isolation.sql          # tenant_filter() — Pattern A
│   └── dedup_helpers.sql             # reusable dedup patterns
├── models/
│   ├── staging/       _sources.yml + 4 staging models
│   ├── intermediate/  _intermediate.yml + union, dedup, bridge
│   └── marts/         _marts.yml + dim_candidate, attributes, presence
├── tests/
│   ├── generic/       test_email_format.sql
│   └── singular/      3 business-rule assertions
├── analyses/          3 worked example queries
└── snapshots/         dim_candidate_snapshot.sql — SCD Type 2 history
```

## Current status

All models, the source declarations, the tenant macro, and the test suite are written, and `dbt parse` succeeds. The project has **not been run against a warehouse**, and the issues below are outstanding.

Required deliverables still empty (0 bytes):

- **`analyses/`** — the brief lists "add 2–3 example queries" as its own numbered requirement. Three files are scaffolded and none are written: cross-system candidate search, system overlap analysis, and survey responses segmented by ATS.
- **`macros/dedup_helpers.sql`** — the dedup windows are written inline in `int_identity_deduped.sql` and belong here.
- **`snapshots/dim_candidate_snapshot.sql`** — SCD Type 2 history. Should snapshot `dim_candidate`, not the ephemeral intermediate model.

---

## Fixed

| #   | Issue                                                                        | Resolution                                                                                                       |
| --- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 1   | `candidate_id` treated as a shared key, colliding unrelated people           | surrogate `candidate_sk` over `(customer_id, email)`; native ids moved to `int_candidate_system_bridge`           |
| 2   | Dedup partition spanned tenants, mixing one customer's attributes into another's row | `customer_id` is an input to the key, so a partition structurally cannot span tenants                     |
| 3   | `assert_customer_id_consistency` could never fail                            | repointed at `int_identity_unioned`, grouped by `candidate_sk`                                                   |
| 4   | Most-recent-non-null windows were dead code                                  | explicit `UNBOUNDED FOLLOWING` frame, guarded by a unit-test fixture and `assert_dedup_preserves_non_null`        |
| —   | `MAX()` over BOOLEAN, which Snowflake rejects                                | `BOOLOR_AGG`                                                                                                     |
| —   | `stg_crm_candidates` missing `ats`, breaking the union                       | `CAST(NULL AS VARCHAR) AS ats`, and explicit casts on the other NULL branches for union type stability            |
| 5   | `stg_ats_candidates` did not expose `job_id`                                 | `job_id` selected through, with a `relationships` test back to `stg_ats_jobs`                                    |
| 6   | ATS recruiter data silently dropped                                          | `recruiters[0]` feeds the hub's scalar `recruiter`; the full array stays for the multi-valued attributes table    |
| 10  | `assert_email_dedup_integrity` grouped emails globally                       | grouped by `(customer_id, email)`                                                                                |
| 11  | `stg_ats_candidates` bypassed `stg_ats_jobs`                                 | joins `ref('stg_ats_jobs')`, so one cleaning path serves every consumer                                          |
| —   | staging layer had no schema file                                             | `_staging.yml` documents all four models and adds key, FK and email-format tests                                  |
| 7   | `dim_candidate_attributes` had no `customer_id`, so could not be tenant-scoped | rebuilt on `candidate_sk` + `customer_id`, joined through the bridge; `tenant_filter()` now applies                |
| 9   | `attribute_value` mixed VARIANT arrays with scalars                          | double `FLATTEN` emits one row per array element, cast to `VARCHAR`; `IS_ARRAY` guard keeps scalar tags working    |
| 12  | `indexes` config silently ignored by dbt-snowflake                           | replaced with `cluster_by` on both marts, `customer_id` leading; grain now guarded by `unique_combination_of_columns` |
| —   | `dbt_expectations` installed but never referenced                            | dropped; its transitive `dbt_date` pins dbt >=1.10.5 and broke tooling on older dbt                               |

> [!NOTE]
> These are correct by construction and by `dbt parse`, **not by execution** — no model has yet run against a warehouse.

## Remaining

### 8. The attribute namespace doesn't line up

`dim_candidate_attributes` normalizes the *shape* of each key — lowercased, spaces to underscores, so `'Hiring manager'` becomes `hiring_manager` — but not the *vocabulary*. CRM and ATS emit `department_name` while Survey emits `department`; ATS emits `recruiters` where CRM emits `recruiter`. A single predicate still cannot match every system, which is the one thing this table exists to enable.

**Fix:** an explicit `(source_system, raw_key) -> canonical_name` mapping. A seed keeps new fields to a CSV row; a macro or `CASE` block works identically at runtime but means a SQL edit per field. Left open deliberately.

---

**dbt 1.12 deprecations:** `freshness` should move under `config:` in `_sources.yml`, and `accepted_values`' `values:` should nest under `arguments:` in `_intermediate.yml`.
