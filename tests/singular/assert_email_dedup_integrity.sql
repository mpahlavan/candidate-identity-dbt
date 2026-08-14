-- One email should not map to two different candidate_ids
-- (unless explicitly allowed, e.g., shared family accounts)
WITH dupes AS (
    SELECT
        email,
        COUNT(DISTINCT candidate_id) AS candidate_count,
        ARRAY_AGG(DISTINCT candidate_id) AS candidate_ids
    FROM {{ ref('int_identity_deduped') }}
    WHERE email IS NOT NULL
    GROUP BY email
    HAVING candidate_count > 1
)
SELECT * FROM dupes
