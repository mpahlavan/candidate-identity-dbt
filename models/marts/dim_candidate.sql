-- models/marts/dim_candidate.sql
{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['candidate_id'], 'unique': True},
            {'columns': ['email']},
            {'columns': ['customer_id']},
            {'columns': ['hiring_manager']},
            {'columns': ['department_name']}
        ]
    )
}}

SELECT
    candidate_id,
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
