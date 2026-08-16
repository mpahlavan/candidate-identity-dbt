-- models/intermediate/int_identity_unioned.sql
-- One row per candidate-per-system. No dedup yet.
--
-- Identity key: the brief defines candidate_id as a primary key *within* each
-- system (Appendix A), so it is not comparable across systems -- CRM candidate 5
-- and ATS candidate 5 are unrelated people. Email is the cross-system common
-- denominator, so identity is a minted surrogate over (customer_id, email).
--
-- customer_id is part of the key because the warehouse is multi-tenant: the same
-- email under two customers is two distinct candidates. This also guarantees a
-- partition can never span tenants, which is what keeps the dedup downstream
-- from mixing one customer's attributes into another's row.
--
-- The coalesce matters: generate_surrogate_key renders NULL as a literal string,
-- so without a fallback every candidate lacking an email would hash identically
-- and collapse into one person. Falling back to the native per-system id keeps
-- them distinct.

WITH unioned AS (

    SELECT
        candidate_id                    AS source_candidate_id,
        customer_id,
        email,
        phone_number,
        source_timestamp,
        recruiter,
        hiring_manager,
        department_name,
        CAST(NULL AS VARCHAR)           AS ats,
        source_system
    FROM {{ ref('stg_crm_candidates') }}

    UNION ALL

    SELECT
        candidate_id                    AS source_candidate_id,
        customer_id,
        email,
        phone_number,
        source_timestamp,
        recruiter,
        hiring_manager,
        department_name,
        CAST(NULL AS VARCHAR)           AS ats,
        source_system
    FROM {{ ref('stg_ats_candidates') }}

    UNION ALL

    SELECT
        candidate_id                    AS source_candidate_id,
        customer_id,
        email,
        CAST(NULL AS VARCHAR)           AS phone_number,
        source_timestamp,
        recruiter,
        hiring_manager,
        department_name,
        ats,
        source_system
    FROM {{ ref('stg_srv_applicants') }}

)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'customer_id',
        "coalesce(email, source_system || ':' || source_candidate_id::varchar)"
    ]) }}                               AS candidate_sk,
    source_candidate_id,
    customer_id,
    email,
    phone_number,
    source_timestamp,
    recruiter,
    hiring_manager,
    department_name,
    ats,
    source_system
FROM unioned
