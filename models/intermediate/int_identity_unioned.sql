-- models/intermediate/int_identity_unioned.sql
-- One row per candidate-per-system. No dedup yet.
SELECT
    candidate_id,
    customer_id,
    email,
    phone_number,
    source_timestamp,
    recruiter,
    hiring_manager,
    department_name,
    ats,
    source_system
FROM {{ ref('stg_crm_candidates') }}

UNION ALL

SELECT
    candidate_id,
    customer_id,
    email,
    phone_number,
    source_timestamp,
    NULL AS recruiter,
    hiring_manager,
    department_name,
    NULL AS ats,
    source_system
FROM {{ ref('stg_ats_candidates') }}

UNION ALL

SELECT
    candidate_id,
    customer_id,
    email,
    NULL AS phone_number,
    source_timestamp,
    recruiter,
    hiring_manager,
    department_name,
    ats,
    source_system
FROM {{ ref('stg_srv_applicants') }}
