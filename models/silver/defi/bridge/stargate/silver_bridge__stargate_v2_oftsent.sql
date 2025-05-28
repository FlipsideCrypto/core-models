{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = "block_number",
    cluster_by = ['block_timestamp::DATE'],
    tags = ['silver_bridge','defi','bridge','curated']
) }}

WITH stargate_contracts AS (

    SELECT
        block_timestamp,
        tx_hash,
        to_address AS contract_address,
        POSITION(
            '00000000000000000000000000000000000000000000000000000000000000c0',
            input,
            LENGTH(input) - 703
        ) AS argument_start, -- starting position of arguments
        SUBSTR(input, argument_start, LENGTH(input) - argument_start + 1) AS arguments,
        regexp_SUBSTR_all(SUBSTR(arguments, 0, len(arguments)), '.{64}') AS segmented_arguments,
        ARRAY_SIZE(segmented_arguments) AS data_size,
        CONCAT(
            '0x',
            SUBSTR(
                segmented_arguments [2] :: STRING,
                25,
                40
            )
        ) AS token_address,
        utils.udf_hex_to_int(
            segmented_arguments [data_size-8] :: STRING
        ) AS decimals,
        utils.udf_hex_to_int(
            segmented_arguments [data_size-7] :: STRING
        ) AS shared_decimals,
        CONCAT(
            '0x',
            SUBSTR(
                segmented_arguments [data_size-6] :: STRING,
                25,
                40
            )
        ) AS endpoint,
        CONCAT(
            '0x',
            SUBSTR(
                segmented_arguments [data_size-5] :: STRING,
                25,
                40
            )
        ) AS owner,
        utils.udf_hex_to_string(
            segmented_arguments [data_size-3] :: STRING
        ) AS token_name,
        utils.udf_hex_to_string(
            segmented_arguments [data_size-1] :: STRING
        ) AS token_symbol
    FROM
        {{ ref('core__fact_traces') }}
    WHERE
        origin_function_signature = '0x61014060'
        AND from_address = '0x1d7c6783328c145393e84fb47a7f7c548f5ee28d'
        AND trace_succeeded

{% if is_incremental() %}
AND _inserted_timestamp >= (
    SELECT
        MAX(_inserted_timestamp) - INTERVAL '12 hours'
    FROM
        {{ this }}
)
AND _inserted_timestamp >= SYSDATE() - INTERVAL '7 day'
{% endif %}
),
oft_sent AS (
    -- bridging transactions from stargate v2 only
    SELECT
        block_number,
        block_timestamp,
        tx_hash,
        origin_function_signature,
        origin_from_address,
        origin_to_address,
        contract_address,
        event_index,
        'OFTSent' AS event_name,
        'stargate-v2' AS platform,
        topic_1 AS guid,
        CONCAT('0x', SUBSTR(topic_2, 27, 40)) AS from_address,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [0] :: STRING)) AS dstEid,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [1] :: STRING)) AS amountsentld,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [2] :: STRING)) AS amountreceivedld,
        CONCAT(
            tx_hash :: STRING,
            '-',
            event_index :: STRING
        ) AS _log_id,
        modified_timestamp AS _inserted_timestamp
    FROM
        {{ ref('core__fact_event_logs') }}
        e
        INNER JOIN stargate_contracts USING(contract_address)
    WHERE
        topics [0] = '0x85496b760a4b7f8d66384b9df21b381f5d1b1e79f229a47aaf4c232edc2fe59a'
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
),
bus_mode AS (
    SELECT
        tx_hash,
        regexp_substr_all(SUBSTR(DATA, 3, len(DATA)), '.{64}') AS segmented_data,
        TRY_TO_NUMBER(
            utils.udf_hex_to_int(
                segmented_data [0] :: STRING
            )
        ) AS dst_eid,
        TRY_TO_NUMBER(
            utils.udf_hex_to_int(
                segmented_data [1] :: STRING
            )
        ) AS ticket,
        TRY_TO_NUMBER(
            utils.udf_hex_to_int(
                segmented_data [2] :: STRING
            )
        ) AS fare,
        SUBSTR(
            DATA,
            3 + 64 * 5,
            128
        ) AS passenger,
        TRY_TO_NUMBER(utils.udf_hex_to_int(SUBSTR(passenger, 3, 4))) AS asset_id,
        CONCAT('0x', SUBSTR(passenger, 3 + 4 + 24, 40)) AS receiver,
    FROM
        {{ ref('core__fact_event_logs') }}
    WHERE
        contract_address = LOWER('0xaf54be5b6eec24d6bfacf1cce4eaf680a8239398') -- tokenmessaging
        AND topics [0] = '0x15955c5a4cc61b8fbb05301bce47fd31c0e6f935e1ab97fdac9b134c887bb074' -- BusRode
        AND tx_hash IN (
            SELECT
                tx_hash
            FROM
                oft_sent
        )
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
),
taxi_mode AS (
    SELECT
        tx_hash,
        input,
        SUBSTR(input, 11, len(input)),
        regexp_substr_all(SUBSTR(input, 11, len(input)), '.{64}') AS segmented_data,
        CONCAT('0x', SUBSTR(segmented_data [4] :: STRING, 25, 40)) AS sender,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [5] :: STRING)) AS dstEid,
        CONCAT('0x', SUBSTR(segmented_data [6] :: STRING, 25, 40)) AS receiver,
        TRY_TO_NUMBER(utils.udf_hex_to_int(segmented_data [7] :: STRING)) AS amountSD
    FROM
        {{ ref('core__fact_traces') }}
    WHERE
        to_address = '0xaf54be5b6eec24d6bfacf1cce4eaf680a8239398'
        AND from_address IN (
            SELECT
                contract_address
            FROM
                stargate_contracts
        )
        AND tx_hash IN (
            SELECT
                tx_hash
            FROM
                oft_sent
        )
        AND LEFT(
            input,
            10
        ) = '0xff6fb300'
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
    b.block_timestamp,
    b.tx_hash,
    origin_function_signature,
    origin_from_address,
    origin_to_address,
    '0x1a44076050125825900e736c501f859c50fe728c' AS bridge_address,
    event_index,
    event_name,
    platform,
    origin_from_address AS sender,
    receiver,
    receiver AS destination_chain_receiver,
    amountSentLD AS amount_unadj,
    b.dstEid AS destination_chain_id,
    LOWER(
        s.chain :: STRING
    ) AS destination_chain,
    C.token_address,
    _log_id,
    b._inserted_timestamp
FROM
    oft_sent b
    INNER JOIN stargate_contracts C
    ON b.contract_address = C.contract_address
    LEFT JOIN (
        SELECT
            receiver,
            tx_hash
        FROM
            bus_mode
        UNION ALL
        SELECT
            receiver,
            tx_hash
        FROM
            taxi_mode
    ) m
    ON m.tx_hash = b.tx_hash
    INNER JOIN {{ ref('silver_bridge__layerzero_bridge_seed') }}
    s
    ON b.dstEid :: STRING = s.eid :: STRING
ORDER BY
    block_timestamp DESC
