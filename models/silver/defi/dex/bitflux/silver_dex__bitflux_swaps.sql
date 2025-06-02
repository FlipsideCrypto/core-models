{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = 'block_number',
    cluster_by = ['block_timestamp::DATE'],
    tags = ['curated','reorg']
) }}

WITH bitflux_pools AS (

    SELECT
        pool_address,
        token0,
        token1,
        token2,
        token3,
        decimal0,
        decimal1,
        decimal2,
        decimal3,
    FROM
        {{ ref('silver_dex__bitflux_pools') }}
),
base_swaps AS (
    SELECT
        l.block_number,
        l.block_timestamp,
        l.tx_hash,
        l.contract_address,
        l.origin_function_signature,
        l.origin_from_address,
        l.origin_to_address,
        event_index,
        COALESCE(
            p1.pool_address,
            p2.pool_address
        ) AS pool_address,
        CONCAT('0x', SUBSTR(topic_1, 27, 40)) AS buyer,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [0] :: STRING)) AS tokensSold,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [1] :: STRING)) AS tokensBought,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [2] :: STRING)) AS soldId,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [3] :: STRING)) AS boughtId,
        p1.token0,
        p1.token1,
        p1.token2,
        p1.token3,
        CASE
            WHEN boughtId = 0 THEN p1.token0
            WHEN boughtId = 1 THEN p1.token1
            WHEN boughtId = 2 THEN p1.token2
            WHEN boughtId = 3 THEN p1.token3
            ELSE NULL
        END AS token_out,
        CASE
            WHEN soldId = 0 THEN p2.token0
            WHEN soldId = 1 THEN p2.token1
            WHEN soldId = 2 THEN p2.token2
            WHEN soldId = 3 THEN p2.token3
            ELSE NULL
        END AS token_in,
        tokensSold AS amount_in_unadj,
        tokensBought AS amount_out_unadj,
        CONCAT(
            l.tx_hash :: STRING,
            '-',
            event_index :: STRING
        ) AS _log_id,
        modified_timestamp AS _inserted_timestamp
    FROM
        {{ ref('core__fact_event_logs') }}
        l
        INNER JOIN bitflux_pools p1
        ON l.contract_address = p1.pool_address
        INNER JOIN bitflux_pools p2
        ON l.contract_address = p2.pool_address
    WHERE
        topic_0 = '0xc6c1e0630dbe9130cc068028486c0d118ddcea348550819defd5cb8c257f8a38'
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
    buyer AS recipient,
    buyer AS sender,
    buyer AS tx_to,
    'TokenSwap' AS event_name,
    event_index,
    token0,
    token1,
    token2,
    token3,
    token_in,
    token_out,
    amount_in_unadj,
    amount_out_unadj,
    _log_id,
    _inserted_timestamp
FROM
    base_swaps
