SELECT
    job_id,
    customer_id,
    hiring_manager,
    recruiters,
    department_name
FROM {{ source('raw', 'ats_jobs') }}
