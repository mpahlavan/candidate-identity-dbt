SELECT
    ac.candidate_id,
    aj.customer_id,
    LOWER(TRIM(ac.email_address)) AS email,
    ac.phone                      AS phone_number,
    ac.created_at                 AS source_timestamp,
    aj.hiring_manager,
    aj.recruiters,                -- still an array; flatten in the next step
    aj.department_name,
    'ats'                         AS source_system
FROM {{ source('raw', 'ats_candidates') }} ac
LEFT JOIN {{ source('raw', 'ats_jobs') }} aj
    ON ac.job_id = aj.job_id
