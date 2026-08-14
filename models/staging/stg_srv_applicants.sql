SELECT
    candidate_id,
    customer_id,
    LOWER(TRIM(email))                        AS email,
    import_date                               AS source_timestamp,
    tags,
    ats,
    'srv'                                     AS source_system,
    -- Extract from JSON tags
    tags:"Hiring manager"[0]::VARCHAR         AS hiring_manager,
    tags:"Recruiter"[0]::VARCHAR              AS recruiter,
    tags:"Department"[0]::VARCHAR             AS department_name
FROM {{ source('raw', 'srv_applicants') }}
