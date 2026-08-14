-- A candidate_id should not map to more than one customer_id
-- (unless the bridge table is your source of truth for that)
WITH multi_customer AS (
    SELECT candidate_id, COUNT(DISTINCT customer_id) AS customer_count
    FROM {{ ref('int_identity_deduped') }}
    GROUP BY candidate_id
    HAVING customer_count > 1
)
SELECT * FROM multi_customer
