-- models/marts/fct_candidate_presence.sql
SELECT
    candidate_sk,
    customer_id,
    department_name,
    is_in_crm,
    is_in_ats,
    is_in_srv,
    -- Bitmask for fast filtering: 1=crm, 2=ats, 4=srv
    (CASE WHEN is_in_crm THEN 1 ELSE 0 END +
     CASE WHEN is_in_ats THEN 2 ELSE 0 END +
     CASE WHEN is_in_srv THEN 4 ELSE 0 END) AS system_bitmask,
    last_updated_at
FROM {{ ref('dim_candidate') }}
