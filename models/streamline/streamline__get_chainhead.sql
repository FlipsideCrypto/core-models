{{ config (
    materialized = 'table',
    tags = ['streamline_core_complete']
) }}
{{ fsc_evm.streamline_core_chainhead(
    vault_secret_path = 'Vault/prod/core/ankr/mainnet'
) }}
