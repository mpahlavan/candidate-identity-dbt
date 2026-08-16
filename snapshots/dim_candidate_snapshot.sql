-- SCD Type 2 history for the candidate identity hub.
--
-- Snapshots dim_candidate rather than int_identity_deduped: the intermediate
-- layer is materialized ephemeral and so has no relation for dbt to diff
-- against between runs.
--
-- Uses the `timestamp` strategy because dim_candidate already exposes
-- last_updated_at (MAX(source_timestamp) across every system that knows the
-- candidate). Any source system touching the record moves that column, which is
-- exactly the change signal wanted here. The `check` strategy would work too but
-- costs a column-by-column comparison for no extra fidelity.
--
-- hard_deletes='invalidate' closes the dbt_valid_to window when a candidate
-- stops appearing upstream, so history shows when they left rather than
-- implying they are still current.
--
-- NOTE (GDPR): this table retains candidate PII after deletion upstream, by
-- design -- that is what SCD2 means. A right-to-erasure request therefore has to
-- reach this relation explicitly; invalidation is not deletion.

{% snapshot dim_candidate_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='candidate_sk',
        strategy='timestamp',
        updated_at='last_updated_at',
        hard_deletes='invalidate'
    )
}}

SELECT * FROM {{ ref('dim_candidate') }}

{% endsnapshot %}
