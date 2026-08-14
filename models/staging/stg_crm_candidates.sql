SELECT
    candidate_id,
    customer_id,
    LOWER(TRIM(email))        AS email,
    phone_number,
    first_seen                 AS source_timestamp,
    recruiter,
    hiring_manager,
    department_name,
    'crm'                      AS source_system
FROM {{ source('raw', 'crm_candidates') }}
