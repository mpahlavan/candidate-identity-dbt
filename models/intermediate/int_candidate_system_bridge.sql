-- models/intermediate/int_candidate_system_bridge.sql
-- Preserves the full candidate-to-customer mapping. The identity hub picks a
-- single customer_id per candidate; this bridge keeps every pairing so that
-- multi-customer candidates (e.g. staffing agency records) are not lost.
SELECT DISTINCT
    candidate_id,
    customer_id,
    source_system,
    source_timestamp
FROM {{ ref('int_identity_unioned') }}
