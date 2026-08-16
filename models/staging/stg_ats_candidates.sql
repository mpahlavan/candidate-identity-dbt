-- models/staging/stg_ats_candidates.sql
-- Grain: one row per ATS candidate.
--
-- Joins ref('stg_ats_jobs') rather than source('raw', 'ats_jobs') so that any
-- cleaning rule added to the jobs staging model reaches every consumer. Going
-- direct to the source created two paths to the same data.
SELECT
    ac.candidate_id,
    ac.job_id,
    aj.customer_id,
    LOWER(TRIM(ac.email_address))   AS email,
    ac.phone                        AS phone_number,
    ac.created_at                   AS source_timestamp,
    aj.hiring_manager,

    -- A job can carry several recruiters. The identity hub is one row per
    -- candidate and needs a scalar, so it takes the first; the complete list
    -- stays available as an array for dim_candidate_attributes, which is
    -- multi-valued by design and keeps every recruiter.
    aj.recruiters,
    aj.recruiters[0]::VARCHAR       AS recruiter,

    aj.department_name,
    'ats'                           AS source_system
FROM {{ source('raw', 'ats_candidates') }} ac
LEFT JOIN {{ ref('stg_ats_jobs') }} aj
    ON ac.job_id = aj.job_id
