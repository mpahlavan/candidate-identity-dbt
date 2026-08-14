-- tests/generic/test_email_format.sql
-- Reusable email-shape test. Apply to any email column:
--
--     columns:
--       - name: email
--         tests:
--           - not_null
--           - email_format
{% test email_format(model, column_name) %}
    SELECT {{ column_name }}
    FROM {{ model }}
    WHERE {{ column_name }} IS NOT NULL
      AND {{ column_name }} NOT LIKE '%@%.%'
      AND {{ column_name }} NOT REGEXP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
{% endtest %}
