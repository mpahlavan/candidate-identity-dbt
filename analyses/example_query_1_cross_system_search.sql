-- Example 1: Cross-system candidate search
--
-- "Find every candidate in a given department, regardless of which product
-- holds that field."
--
-- Before the identity layer this needed three queries and manual reconciliation
-- by email. Now it is one join: the hub carries the resolved scalar, and the
-- attributes table carries every system's version so you can see who disagrees.
--
-- Compile with:  dbt compile --select example_query_1_cross_system_search \
--                  --vars '{"tenant_id": 123}'

{% set target_department = 'Sales' %}

SELECT
    c.candidate_sk,
    c.email,
    c.department_name                            AS resolved_department,
    c.hiring_manager,
    c.recruiter,

    -- Which systems know this person, and what each of them says.
    c.is_in_crm,
    c.is_in_ats,
    c.is_in_srv,
    LISTAGG(DISTINCT a.source_system, ', ')
        WITHIN GROUP (ORDER BY a.source_system)  AS systems_claiming_department,
    LISTAGG(DISTINCT a.attribute_value, ' | ')
        WITHIN GROUP (ORDER BY a.attribute_value) AS department_values_seen,

    c.last_updated_at

FROM {{ ref('dim_candidate') }} c

LEFT JOIN {{ ref('dim_candidate_attributes') }} a
    ON  a.candidate_sk = c.candidate_sk
    -- Both spellings are listed because attribute vocabulary is not yet
    -- reconciled across systems (open issue #8): CRM and ATS emit
    -- 'department_name' where Survey emits 'department'. Once a canonical
    -- mapping exists this collapses to a single value.
    AND a.attribute_name IN ('department_name', 'department')

WHERE c.customer_id = {{ var('tenant_id', 1) }}
  AND (
        c.department_name = '{{ target_department }}'
     OR a.attribute_value = '{{ target_department }}'
      )

GROUP BY
    c.candidate_sk, c.email, c.department_name, c.hiring_manager,
    c.recruiter, c.is_in_crm, c.is_in_ats, c.is_in_srv, c.last_updated_at

ORDER BY c.last_updated_at DESC
