{% macro create_sps() %}
    {% if var("UPDATE_UDFS_AND_SPS", false) %}
        {% set current_profile = var('PROD_DB_NAME') | upper %}
        {% if target.database | upper == current_profile and target.name == 'prod' %}
            {% set schema_name = var("SPS_SCHEMA_NAME", '_internal') %}
            CREATE SCHEMA IF NOT EXISTS {{ schema_name }};
            {{ sp_create_prod_clone(schema_name) }};
        {% endif %}
    {% endif %}
{% endmacro %}