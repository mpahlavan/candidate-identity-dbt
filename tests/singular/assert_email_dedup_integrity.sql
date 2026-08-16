-- One email should not map to two different candidates *within a customer*.
--
-- Scoped by customer_id deliberately: in a multi-tenant warehouse two genuinely
-- different people at two different customers can share an address such as
-- info@company.com. Grouping globally would report that as corruption.
WITH dupes AS (
    SELECT
        customer_id,
        email,
        COUNT(DISTINCT candidate_sk)     AS candidate_count,
        ARRAY_AGG(DISTINCT candidate_sk) AS candidate_sks
    FROM {{ ref('int_identity_deduped') }}
    WHERE email IS NOT NULL
    GROUP BY customer_id, email
    HAVING COUNT(DISTINCT candidate_sk) > 1
)
SELECT * FROM dupes
