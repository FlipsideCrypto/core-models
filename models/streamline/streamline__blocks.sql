{{ config (
    materialized = "view",
    tags = ['streamline_core_complete']
) }}
{{ fsc_evm.block_sequence(min_block = 17962900) }}
