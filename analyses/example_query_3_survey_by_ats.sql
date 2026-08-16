-- Example 3: Survey response rate, segmented by ATS vendor
--
-- "What share of ATS candidates have also responded to a survey, and does it
-- differ by which ATS the customer runs?"
--
-- Needs all three systems at once: the ATS population, the survey population,
-- and the vendor attribute — which only the Survey export carries, so it
-- reaches ATS-only candidates purely through identity resolution.

SELECT
    COALESCE(c.ats, '(unknown)')                AS ats_vendor,

    COUNT(*)                                    AS ats_candidates,
    COUNT_IF(c.is_in_srv)                       AS also_responded_to_survey,
    ROUND(
        100.0 * COUNT_IF(c.is_in_srv) / NULLIF(COUNT(*), 0)
    , 1)                                        AS pct_responded,

    -- How many of these the CRM also knows about, as a completeness signal.
    COUNT_IF(c.is_in_crm)                       AS also_in_crm,

    COUNT(DISTINCT c.department_name)           AS departments_covered,
    MAX(c.last_updated_at)                      AS most_recent_activity

FROM {{ ref('dim_candidate') }} c

WHERE c.customer_id = {{ var('tenant_id', 1) }}
  AND c.is_in_ats

GROUP BY COALESCE(c.ats, '(unknown)')
ORDER BY ats_candidates DESC
