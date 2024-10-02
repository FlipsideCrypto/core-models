{% macro add_database_or_schema_tags() %}
    {% set current_profile = var('profile') | upper %}
    {{ set_database_tag_value('BLOCKCHAIN_NAME', current_profile) }}
    {{ set_database_tag_value('BLOCKCHAIN_TYPE','EVM') }}
{% endmacro %}