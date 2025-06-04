{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = 'block_number',
    cluster_by = ['block_timestamp::DATE'],
    tags = ['silver_dex','defi','dex','curated']
) }}

WITH pool_data AS (

    SELECT
        token0,
        token1,
        fee,
        tick_spacing,
        pool_address
    FROM
        {{ ref('silver_dex__corex_pools') }}
),
base_swaps AS (
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        contract_address,
        event_index,
        origin_function_signature,
        origin_from_address,
        origin_to_address,
        CONCAT('0x', SUBSTR(topic_1, 27, 40)) AS sender,
        CONCAT('0x', SUBSTR(topic_2, 27, 40)) AS recipient,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        utils.udf_hex_to_int(
            's2c',
            segmented_data [0] :: STRING
        ) :: FLOAT AS amount0_unadj,
        utils.udf_hex_to_int(
            's2c',
            segmented_data [1] :: STRING
        ) :: FLOAT AS amount1_unadj,
        utils.udf_hex_to_int(
            's2c',
            segmented_data [2] :: STRING
        ) :: FLOAT AS sqrtPriceX96,
        utils.udf_hex_to_int(
            's2c',
            segmented_data [3] :: STRING
        ) :: FLOAT AS liquidity,
        utils.udf_hex_to_int(
            's2c',
            segmented_data [4] :: STRING
        ) :: FLOAT AS tick,
        CONCAT(
            tx_hash :: STRING,
            '-',
            event_index :: STRING
        ) AS _log_id,
        modified_timestamp AS _inserted_timestamp,
    FROM
        {{ ref('core__fact_event_logs') }} l
    INNER JOIN pool_data p
    ON p.pool_address = l.contract_address
    WHERE
        topic_0 = '0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67'
        AND tx_succeeded

{% if is_incremental() %}
AND _inserted_timestamp >= (
    SELECT
        MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
        {{ this }}
)
AND _inserted_timestamp >= SYSDATE() - INTERVAL '7 day'
{% endif %}
)
SELECT
    block_number,
    block_timestamp,
    tx_hash,
    contract_address,
    pool_address,
    origin_function_signature,
    origin_from_address,
    origin_to_address,
    recipient,
    sender,
    fee,
    tick,
    tick_spacing,
    liquidity,
    event_index,
    token0,
    token1,
    amount0_unadj,
    amount1_unadj,
    _log_id,
    _inserted_timestamp
FROM
    base_swaps
    INNER JOIN pool_data
    ON pool_data.pool_address = base_swaps.contract_address qualify(ROW_NUMBER() over(PARTITION BY _log_id
ORDER BY
    _inserted_timestamp DESC)) = 1
