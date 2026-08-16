-- models/intermediate/int_candidate_system_bridge.sql
-- The home for each system's native candidate_id, which the identity hub drops.
-- Also preserves the full candidate-to-customer mapping, so a candidate that
-- legitimately spans customers (e.g. a staffing agency record) is not lost when
-- the hub collapses to one row per candidate_sk.
SELECT DISTINCT
    candidate_sk,
    source_candidate_id,
    customer_id,
    source_system,
    source_timestamp
FROM {{ ref('int_identity_unioned') }}
