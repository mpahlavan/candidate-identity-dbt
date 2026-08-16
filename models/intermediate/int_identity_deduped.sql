-- models/intermediate/int_identity_deduped.sql
-- Most-recent-non-null dedup. One row per candidate_sk.
--
-- The explicit frame is load-bearing. FIRST_VALUE defaults to
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW; combined with keeping the
-- first row of the same ordering, every window would see only its own row and
-- the coalescing would silently do nothing. UNBOUNDED FOLLOWING makes each
-- window scan the whole partition, which is what "most recent non-null" means.
--
-- email and customer_id need no windowing: both are inputs to candidate_sk and
-- are therefore constant within a partition.

SELECT
    candidate_sk,
    customer_id,
    email,

    FIRST_VALUE(phone_number IGNORE NULLS) OVER (
        PARTITION BY candidate_sk ORDER BY source_timestamp DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                       AS phone_number,

    FIRST_VALUE(hiring_manager IGNORE NULLS) OVER (
        PARTITION BY candidate_sk ORDER BY source_timestamp DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                       AS hiring_manager,

    FIRST_VALUE(recruiter IGNORE NULLS) OVER (
        PARTITION BY candidate_sk ORDER BY source_timestamp DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                       AS recruiter,

    FIRST_VALUE(department_name IGNORE NULLS) OVER (
        PARTITION BY candidate_sk ORDER BY source_timestamp DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                       AS department_name,

    FIRST_VALUE(ats IGNORE NULLS) OVER (
        PARTITION BY candidate_sk ORDER BY source_timestamp DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                                                       AS ats,

    -- Snowflake's MAX() rejects BOOLEAN; BOOLOR_AGG is the boolean aggregate.
    BOOLOR_AGG(source_system = 'crm')
        OVER (PARTITION BY candidate_sk)                    AS is_in_crm,
    BOOLOR_AGG(source_system = 'ats')
        OVER (PARTITION BY candidate_sk)                    AS is_in_ats,
    BOOLOR_AGG(source_system = 'srv')
        OVER (PARTITION BY candidate_sk)                    AS is_in_srv,

    MAX(source_timestamp)
        OVER (PARTITION BY candidate_sk)                    AS last_updated_at

FROM {{ ref('int_identity_unioned') }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY candidate_sk ORDER BY source_timestamp DESC
) = 1
