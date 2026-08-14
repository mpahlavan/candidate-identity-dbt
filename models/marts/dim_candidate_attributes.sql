-- models/marts/dim_candidate_attributes.sql
{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['candidate_id', 'attribute_name'], 'unique': True}
        ]
    )
}}

-- Pull attributes from CRM (direct fields become rows)
SELECT
    candidate_id,
    'department_name' AS attribute_name,
    department_name   AS attribute_value,
    'crm'             AS source_system
FROM {{ ref('stg_crm_candidates') }}
WHERE department_name IS NOT NULL

UNION ALL

-- Pull attributes from Survey tags (flatten JSON)
SELECT
    candidate_id,
    f.key   AS attribute_name,
    f.value AS attribute_value,
    'srv'   AS source_system
FROM {{ ref('stg_srv_applicants') }},
LATERAL FLATTEN(input => tags) f

UNION ALL

-- Pull attributes from ATS jobs
SELECT
    ac.candidate_id,
    'department_name' AS attribute_name,
    aj.department_name AS attribute_value,
    'ats'             AS source_system
FROM {{ ref('stg_ats_candidates') }} ac
JOIN {{ ref('stg_ats_jobs') }} aj
    ON ac.job_id = aj.job_id
WHERE aj.department_name IS NOT NULL
