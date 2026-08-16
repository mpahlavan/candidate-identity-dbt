# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A dbt project on Snowflake that resolves candidate identity across three Jobylon products (CRM, ATS, Survey) into one star schema. Built as an assignment submission; `README.md` carries the design rationale and the open-issue list.

## Commands

Everything runs from the project root, inside the venv:

```bash
source .venv/bin/activate
```

dbt reads `profiles.yml` from the project root (checked before `~/.dbt/`). It resolves credentials from environment variables, so load them first:

```bash
set -a && source .env && set +a
dbt debug
```

| Task | Command |
| --- | --- |
| Structural check, no warehouse needed | `dbt parse` |
| Full run + tests | `dbt build` |
| One model and everything it feeds | `dbt build --select dim_candidate+` |
| One test | `dbt test --select assert_dedup_preserves_non_null` |
| All tests for one model | `dbt test --select dim_candidate` |
| Unit tests only | `dbt test --select "test_type:unit"` |
| Tenant-scoped run | `dbt build --vars '{"tenant_id": 123}'` |

### Verifying without a warehouse

**No model in this project has ever executed.** The `raw` database does not exist in the target Snowflake account, so `dbt build` cannot succeed yet. `dbt parse` is the only verification available, and it needs *a* profile to exist even though it never connects. To check work without touching real credentials, point `DBT_PROFILES_DIR` at a throwaway profile:

```bash
DBT_PROFILES_DIR=/path/to/scratch dbt parse   # scratch/profiles.yml holds a dummy snowflake target
```

Treat "parses cleanly" as the ceiling of what you can claim. Column-level errors, `BOOLOR_AGG`, `IS_ARRAY`, and the double `FLATTEN` are all unexercised.

## Architecture

```
staging (view) -> intermediate (ephemeral) -> marts (table)
```

The intermediate layer is **ephemeral**, so those models have no physical relation. This matters: snapshots and anything needing a real table must target a mart, not `int_identity_deduped`.

### The identity key is the whole design

`candidate_id` is a primary key **within each system**. It is not a join key and never was — CRM candidate 5 and ATS candidate 5 are unrelated people. Identity is a surrogate minted once in `int_identity_unioned`:

```sql
{{ dbt_utils.generate_surrogate_key([
    'customer_id',
    "coalesce(email, source_system || ':' || source_candidate_id::varchar)"
]) }} AS candidate_sk
```

Three things about this are load-bearing, and breaking any of them fails silently:

1. **`customer_id` is in the key.** This is what enforces tenant isolation, not the `tenant_filter()` macro. The macro runs downstream of the dedup; if a partition could span customers, the hub row is already corrupted before any filter applies. Never partition on email alone.
2. **The `coalesce` fallback.** `generate_surrogate_key` renders NULL as a literal string, so without it every email-less candidate under one customer hashes identically and merges into one person.
3. **Native ids go to `int_candidate_system_bridge`.** That model is the only place `source_candidate_id` survives. `dim_candidate_attributes` resolves native ids to `candidate_sk` by joining it.

### The dedup windows need their explicit frame

`int_identity_deduped` implements most-recent-non-null per field. Every `FIRST_VALUE(... IGNORE NULLS)` carries `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`. Without it, `FIRST_VALUE` defaults to a frame ending at the current row, and since the model keeps the first row of the same ordering, every window collapses to reading its own row and stops coalescing — no error, just wrong values.

Two tests exist solely to catch this regression: the `dedup_keeps_most_recent_non_null` unit test and `assert_dedup_preserves_non_null`. Do not weaken either.

`email` and `customer_id` are deliberately not windowed — both are key inputs and constant within a partition.

## Snowflake specifics

The adapter is **not** swappable. `LATERAL FLATTEN`, `variant:path` access, `IS_ARRAY`, `BOOLOR_AGG`, and `QUALIFY` are all Snowflake-only.

- **`MAX()` rejects BOOLEAN.** Use `BOOLOR_AGG(source_system = 'crm')` for the `is_in_*` flags.
- **The `indexes` config is silently ignored** by dbt-snowflake. It was removed for exactly that reason; both marts use `cluster_by` instead. Do not reintroduce `indexes` — it implies tuning that never happens. Grain is enforced by `dbt_utils.unique_combination_of_columns`, not by the adapter.
- **Survey `tags` values are arrays.** A single `FLATTEN` yields `["Sales"]`, not `'Sales'`, and mixes VARIANT with the VARCHAR that CRM/ATS emit. `dim_candidate_attributes` flattens twice with an `IS_ARRAY` guard.

## Conventions

- **`dbt_expectations` is deliberately absent.** Nothing referenced it, and its transitive `dbt_date` pins dbt >=1.10.5, which breaks tooling on older dbt. Do not add it back without checking that constraint. `dbt_utils` is the only dependency.
- **Staging models are 1:1 with sources**, except `stg_ats_candidates`, which joins `ref('stg_ats_jobs')` to pick up job attributes. Always reach ATS jobs through that ref, never `source('raw', 'ats_jobs')` directly — two paths to the same data was a bug that got fixed.
- **`dim_candidate_attributes` is intentionally multi-valued.** Grain is `(candidate_sk, source_system, attribute_name, attribute_value)`, so a candidate with two recruiters keeps both and two systems may disagree without either value being lost. The identity hub takes `recruiters[0]` because it needs a scalar; the full list lives here.

## Known state

`README.md` tracks fixed and open issues; keep it in sync when changing model behaviour, since it documents claims about how the models work.

- **Issue #8 is open by the repo owner's decision.** Attribute *shape* is normalized (`'Hiring manager'` -> `hiring_manager`) but *vocabulary* is not: CRM/ATS emit `department_name` where Survey emits `department`. Closing it needs a `(source_system, raw_key) -> canonical_name` mapping. A seed was built and deliberately reverted — do not reintroduce one without asking.
- **Still empty:** the three `analyses/` queries (a numbered requirement in the assignment brief), `macros/dedup_helpers.sql`, and `snapshots/dim_candidate_snapshot.sql`.
- **dbt 1.12 deprecations outstanding:** `freshness` should move under `config:` in `_sources.yml`, and generic-test arguments (`accepted_values`' `values:`, `relationships`' `to:`/`field:`) should nest under `arguments:`.
- **Two dbt versions are present on this machine.** The venv has 1.12.2; the IDE extension runs 1.8.10. Package version constraints can pass in one and fail in the other.

## Credentials

`profiles.yml` is committed and safe — it reads everything through `env_var()`. Real values live in `.env`, which is gitignored. `.env.example` is a template and is committed, so it must never hold real values.
