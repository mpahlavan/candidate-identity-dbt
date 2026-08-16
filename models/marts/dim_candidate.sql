-- models/marts/dim_candidate.sql
-- Snowflake has no indexes; the `indexes` config is silently ignored by
-- dbt-snowflake, so it gave the appearance of tuning while doing nothing.
-- Clustering is the Snowflake equivalent. customer_id leads the key because
-- every tenant-scoped query filters on it first.
{{
    config(
        materialized = 'table',
        cluster_by = ['customer_id', 'candidate_sk']
    )
}}

-- candidate_sk is the identity key. Native per-system candidate ids live in
-- int_candidate_system_bridge.
SELECT
    candidate_sk,
    customer_id,
    email,
    phone_number,
    hiring_manager,
    recruiter,
    department_name,
    ats,
    is_in_crm,
    is_in_ats,
    is_in_srv,
    last_updated_at
FROM {{ ref('int_identity_deduped') }}
