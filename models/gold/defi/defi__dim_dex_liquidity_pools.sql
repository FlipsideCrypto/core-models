{{ config(
    materialized = 'view',
    persist_docs ={ "relation": true,
    "columns": true },
    meta={
    'database_tags':{
        'table': {
            'PROTOCOL': 'SUSHI, BITFLUX, GLYPH, COREX',
            'PURPOSE': 'DEX, LIQUIDITY, POOLS, LP, SWAPS',
            }
        }
    }
) }}

SELECT
    block_number AS creation_block,
    block_timestamp AS creation_time,
    tx_hash AS creation_tx,
    platform,
    contract_address AS factory_address,
    pool_address,
    pool_name,
    tokens,
    symbols,
    decimals,
    COALESCE (
        complete_dex_liquidity_pools_id,
        {{ dbt_utils.generate_surrogate_key(
            ['pool_address']
        ) }}
    ) AS dim_dex_liquidity_pools_id,
    inserted_timestamp,
    modified_timestamp
FROM
    {{ ref('silver_dex__complete_dex_liquidity_pools') }}