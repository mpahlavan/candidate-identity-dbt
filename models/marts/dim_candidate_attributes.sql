-- models/marts/dim_candidate_attributes.sql
--
-- Extensible key-value store for candidate attributes. Grain is one row per
-- (candidate_sk, source_system, attribute_name, attribute_value) -- deliberately
-- multi-valued, so a candidate with two recruiters keeps both and two systems
-- may disagree about the same attribute without either being lost.
--
-- Keyed on candidate_sk so it joins dim_candidate. Carries customer_id so
-- tenant_filter() applies here as it does to every other mart.
{{
    config(
        materialized = 'table',
        cluster_by = ['customer_id', 'attribute_name']
    )
}}

WITH bridge AS (

    SELECT DISTINCT
        candidate_sk,
        source_candidate_id,
        customer_id,
        source_system
    FROM {{ ref('int_candidate_system_bridge') }}

),

-- Each branch emits the system's RAW key. Normalization happens once, below.
raw_attributes AS (

    -- CRM: scalar columns become rows
    SELECT candidate_id AS source_candidate_id, 'crm' AS source_system,
           'department_name' AS raw_key, department_name AS attribute_value
    FROM {{ ref('stg_crm_candidates') }}
    WHERE department_name IS NOT NULL

    UNION ALL
    SELECT candidate_id, 'crm', 'recruiter', recruiter
    FROM {{ ref('stg_crm_candidates') }}
    WHERE recruiter IS NOT NULL

    UNION ALL
    SELECT candidate_id, 'crm', 'hiring_manager', hiring_manager
    FROM {{ ref('stg_crm_candidates') }}
    WHERE hiring_manager IS NOT NULL

    -- ATS: department and hiring manager come from the job
    UNION ALL
    SELECT candidate_id, 'ats', 'department_name', department_name
    FROM {{ ref('stg_ats_candidates') }}
    WHERE department_name IS NOT NULL

    UNION ALL
    SELECT candidate_id, 'ats', 'hiring_manager', hiring_manager
    FROM {{ ref('stg_ats_candidates') }}
    WHERE hiring_manager IS NOT NULL

    -- ATS recruiters are an array: one row per recruiter, not one row holding
    -- an array. The identity hub keeps only the first; nothing is lost here.
    UNION ALL
    SELECT
        ac.candidate_id,
        'ats',
        'recruiters',
        r.value::VARCHAR
    FROM {{ ref('stg_ats_candidates') }} ac,
    LATERAL FLATTEN(input => ac.recruiters) r
    WHERE r.value IS NOT NULL

    -- Survey: flatten the tags object to key/value, then flatten each value.
    -- Values are arrays, so a single FLATTEN would emit ["Sales"] rather than
    -- 'Sales' and the column would mix VARIANT with VARCHAR. The IS_ARRAY guard
    -- keeps scalar-valued tags working too.
    UNION ALL
    SELECT
        s.candidate_id,
        'srv',
        t.key::VARCHAR,
        v.value::VARCHAR
    FROM {{ ref('stg_srv_applicants') }} s,
    LATERAL FLATTEN(input => s.tags) t,
    LATERAL FLATTEN(
        input => CASE
                     WHEN IS_ARRAY(t.value) THEN t.value
                     ELSE ARRAY_CONSTRUCT(t.value)
                 END
    ) v
    WHERE v.value IS NOT NULL

)

SELECT DISTINCT
    b.candidate_sk,
    b.customer_id,

    -- Normalizes the SHAPE of the key only: case and spacing, so
    -- 'Hiring manager' becomes 'hiring_manager'.
    --
    -- It does NOT reconcile vocabulary across systems, which is open issue #8:
    -- CRM/ATS still say 'department_name' where Survey says 'department', and
    -- ATS says 'recruiters' where CRM says 'recruiter'. A single predicate
    -- therefore cannot yet match every system. Closing this needs an explicit
    -- raw_key -> canonical_name mapping.
    LOWER(REPLACE(TRIM(a.raw_key), ' ', '_'))   AS attribute_name,

    a.attribute_value::VARCHAR                  AS attribute_value,
    a.source_system

FROM raw_attributes a
JOIN bridge b
    ON  a.source_candidate_id = b.source_candidate_id
    AND a.source_system       = b.source_system
WHERE a.attribute_value IS NOT NULL
