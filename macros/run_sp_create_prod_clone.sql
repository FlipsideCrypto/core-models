{% macro run_sp_create_prod_clone() %}
    {% set clone_query %}
    call core._internal.create_prod_clone(
        'core',
        'core_dev',
        'internal_dev'
    );
{% endset %}
    {% do run_query(clone_query) %}
{% endmacro %}
