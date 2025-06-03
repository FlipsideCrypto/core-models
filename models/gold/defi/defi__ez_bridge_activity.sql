{{ config(
    materialized = 'view',
    persist_docs ={ "relation": true,
    "columns": true },
    meta ={ 'database_tags':{ 'table':{ 'PROTOCOL': 'MESON, STARGATE, SYMBIOSIS, GASZIP, COREBRIDGE, GASZIP',
    'PURPOSE': 'BRIDGE' }} },
    tags = ['gold','defi','bridge','curated','ez']
) }}

SELECT
    block_number,
    block_timestamp,
    origin_from_address,
    origin_to_address,
    origin_function_signature,
    tx_hash,
    event_index,
    bridge_address,
    event_name,
    platform,
    sender,
    receiver,
    destination_chain_receiver,
    COALESCE(
        standard_destination_chain,
        b.destination_chain
    ) AS destination_chain,
    destination_chain_id,
    token_address,
    token_symbol,
    amount_unadj,
    amount,
    ROUND(
        CASE
            WHEN amount_usd < 1e + 15 THEN amount_usd
            ELSE NULL
        END,
        2
    ) AS amount_usd,
    {{ dbt_utils.generate_surrogate_key(
        ['_id']
    ) }} AS ez_bridge_activity_id,
    inserted_timestamp,
    modified_timestamp
FROM
    {{ ref('silver_bridge__complete_bridge_activity') }}
    b
    LEFT JOIN {{ ref('silver_bridge__standard_dst_chain_seed') }} C
    ON b.destination_chain = C.destination_chain
