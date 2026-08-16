-- models/marts/dim_candidate.sql
{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['candidate_sk'], 'unique': True},
            {'columns': ['email']},
            {'columns': ['customer_id']},
            {'columns': ['hiring_manager']},
            {'columns': ['department_name']}
        ]
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
