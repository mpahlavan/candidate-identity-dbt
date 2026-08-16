-- Every row in the deduped model must have at least one system flag set
SELECT candidate_sk
FROM {{ ref('int_identity_deduped') }}
WHERE NOT is_in_crm AND NOT is_in_ats AND NOT is_in_srv
