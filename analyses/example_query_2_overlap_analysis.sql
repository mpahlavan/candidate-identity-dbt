-- Example 2: System overlap analysis
--
-- "Which candidates exist in more than one system, and how many?"
--
-- This is the question the identity layer exists to answer, and the one that
-- was unanswerable before it: with per-system candidate_ids there was no way to
-- tell whether CRM 5 and ATS 5 were the same person. Now presence is a property
-- of candidate_sk.
--
-- Reads fct_candidate_presence rather than recomputing flags, so the aggregation
-- is a single scan of a pre-computed bitmask (1=crm, 2=ats, 4=srv).

WITH labelled AS (

    SELECT
        system_bitmask,
        CASE system_bitmask
            WHEN 1 THEN 'CRM only'
            WHEN 2 THEN 'ATS only'
            WHEN 3 THEN 'CRM + ATS'
            WHEN 4 THEN 'Survey only'
            WHEN 5 THEN 'CRM + Survey'
            WHEN 6 THEN 'ATS + Survey'
            WHEN 7 THEN 'All three systems'
        END                                     AS presence,
        system_bitmask IN (3, 5, 6, 7)          AS is_multi_system
    FROM {{ ref('fct_candidate_presence') }}
    WHERE customer_id = {{ var('tenant_id', 1) }}

)

SELECT
    presence,
    COUNT(*)                                                        AS candidates,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct_of_total,
    ROUND(100.0 * COUNT_IF(is_multi_system) / NULLIF(COUNT(*), 0), 1)
                                                                    AS pct_multi_system
FROM labelled
GROUP BY presence, system_bitmask
ORDER BY candidates DESC
