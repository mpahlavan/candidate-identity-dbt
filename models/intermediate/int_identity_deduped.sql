-- models/intermediate/int_identity_deduped.sql
-- Most-recent-non-null dedup. One row per candidate_id.
WITH windowed AS (
    SELECT
        *,
        FIRST_VALUE(email IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_email,
        FIRST_VALUE(phone_number IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_phone,
        FIRST_VALUE(hiring_manager IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_hiring_manager,
        FIRST_VALUE(recruiter IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_recruiter,
        FIRST_VALUE(department_name IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_department,
        FIRST_VALUE(ats IGNORE NULLS)
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS dedup_ats,
        MAX(CASE WHEN source_system = 'crm' THEN TRUE ELSE FALSE END)
            OVER (PARTITION BY candidate_id) AS is_in_crm,
        MAX(CASE WHEN source_system = 'ats' THEN TRUE ELSE FALSE END)
            OVER (PARTITION BY candidate_id) AS is_in_ats,
        MAX(CASE WHEN source_system = 'srv' THEN TRUE ELSE FALSE END)
            OVER (PARTITION BY candidate_id) AS is_in_srv,
        MAX(source_timestamp)
            OVER (PARTITION BY candidate_id) AS last_updated_at,
        ROW_NUMBER()
            OVER (PARTITION BY candidate_id ORDER BY source_timestamp DESC) AS rn
    FROM {{ ref('int_identity_unioned') }}
)

SELECT
    candidate_id,
    dedup_email          AS email,
    customer_id,
    dedup_phone          AS phone_number,
    dedup_hiring_manager AS hiring_manager,
    dedup_recruiter      AS recruiter,
    dedup_department     AS department_name,
    dedup_ats            AS ats,
    is_in_crm,
    is_in_ats,
    is_in_srv,
    last_updated_at
FROM windowed
WHERE rn = 1
