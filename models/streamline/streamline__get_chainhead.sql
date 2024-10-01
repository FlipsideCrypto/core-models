{{ config (
    materialized = 'table',
    tags = ['streamline_core_complete']
) }}
{{ fsc_evm.streamline_core_chainhead(
    vault_secret_path = var('VAULT_SECRET_PATH'),
    api_url = var('API_URL')
) }}
