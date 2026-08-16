-- Regression guard for the most-recent-non-null windows.
--
-- The invariant: if ANY system supplied a non-null value for a field, the
-- deduped row for that candidate must not be null for it. When the FIRST_VALUE
-- windows lose their explicit frame they silently stop coalescing and the
-- newest row's NULLs win -- no error, just quietly wrong data. This fires on
-- real data the moment that happens.
WITH available AS (
    SELECT
        candidate_sk,
        COUNT(phone_number)    AS n_phone,
        COUNT(hiring_manager)  AS n_hiring_manager,
        COUNT(recruiter)       AS n_recruiter,
        COUNT(department_name) AS n_department,
        COUNT(ats)             AS n_ats
    FROM {{ ref('int_identity_unioned') }}
    GROUP BY candidate_sk
)

SELECT
    a.candidate_sk
FROM available a
JOIN {{ ref('int_identity_deduped') }} d
    ON a.candidate_sk = d.candidate_sk
WHERE (a.n_phone           > 0 AND d.phone_number    IS NULL)
   OR (a.n_hiring_manager  > 0 AND d.hiring_manager  IS NULL)
   OR (a.n_recruiter       > 0 AND d.recruiter       IS NULL)
   OR (a.n_department      > 0 AND d.department_name IS NULL)
   OR (a.n_ats             > 0 AND d.ats             IS NULL)
