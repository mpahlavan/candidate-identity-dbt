-- macros/tenant_isolation.sql
--
-- Pattern A (column-based tenant isolation): every mart carries customer_id and
-- callers scope their queries with this filter. Usage in a model:
--
--     SELECT * FROM {{ ref('dim_candidate') }}
--     {{ tenant_filter() }}
--
-- Set the tenant at runtime: dbt run --vars '{"tenant_id": 123}'
-- When tenant_id is unset the macro emits nothing, so unscoped builds run as normal.
--
-- Production upgrade path is Pattern B (row-level security): a Snowflake secure
-- view filters on the session's tenant so the application never writes the
-- predicate itself.
{% macro tenant_filter(customer_id_column='customer_id') %}
    {% if var('tenant_id', none) is not none %}
        WHERE {{ customer_id_column }} = {{ var('tenant_id') }}
    {% endif %}
{% endmacro %}
