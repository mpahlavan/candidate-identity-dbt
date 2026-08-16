-- A candidate must not span multiple customers.
--
-- This is the alarm for cross-tenant merging, so it has to run against the
-- UNIONED model. Pointed at int_identity_deduped it could never fail, because
-- candidate_sk is unique there by construction and the distinct count is
-- always 1.
--
-- customer_id is an input to candidate_sk, so a hit here means the surrogate
-- key logic is broken rather than the data being unusual.
SELECT
    candidate_sk,
    COUNT(DISTINCT customer_id) AS customer_count
FROM {{ ref('int_identity_unioned') }}
GROUP BY candidate_sk
HAVING COUNT(DISTINCT customer_id) > 1
