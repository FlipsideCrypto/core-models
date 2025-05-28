-- depends_on: {{ ref('silver__complete_token_prices') }}
{{ config(
    materialized = 'incremental',
    incremental_strategy = 'delete+insert',
    unique_key = ['block_number','platform','version'],
    cluster_by = ['block_timestamp::DATE','platform'],
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION ON EQUALITY(tx_hash, origin_from_address, origin_to_address, origin_function_signature, bridge_address, sender, receiver, destination_chain_receiver, destination_chain_id, destination_chain, token_address, token_symbol), SUBSTRING(origin_function_signature, bridge_address, sender, receiver, destination_chain_receiver, destination_chain, token_address, token_symbol)",
    tags = ['curated','reorg','heal']
) }}

WITH corebridge AS (

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
        version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id :: STRING AS destination_chain_id,
        destination_chain,
        token_address,
        NULL AS token_symbol,
        amount_unadj,
        _log_id AS _id,
        _inserted_timestamp
    FROM
        {{ ref('silver_bridge__corebridge_unwraptoken') }}

{% if is_incremental() and 'corebridge' not in var('HEAL_MODELS') %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
        FROM
            {{ this }}
    )
{% endif %}
),
gaszip_lz AS (
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
        version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id :: STRING AS destination_chain_id,
        destination_chain,
        token_address,
        NULL AS token_symbol,
        amount_unadj,
        _log_id AS _id,
        _inserted_timestamp
    FROM
        {{ ref('silver_bridge__gaszip_lz_sentdeposits') }}

{% if is_incremental() and 'gaszip_lz' not in var('HEAL_MODELS') %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
        FROM
            {{ this }}
    )
{% endif %}
),
meson AS (
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
        'v1' AS version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id :: STRING AS destination_chain_id,
        destination_chain,
        token_address,
        NULL AS token_symbol,
        amount_unadj,
        _id,
        _inserted_timestamp
    FROM
        {{ ref('silver_bridge__meson_transfer') }}

{% if is_incremental() and 'meson' not in var('HEAL_MODELS') %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
        FROM
            {{ this }}
    )
{% endif %}
),
stargate_v2 AS (
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
        'v2' AS version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id :: STRING AS destination_chain_id,
        destination_chain,
        token_address,
        NULL AS token_symbol,
        amount_unadj,
        _log_id AS _id,
        _inserted_timestamp
    FROM
        {{ ref('silver_bridge__stargate_v2_oftsent') }}

{% if is_incremental() and 'stargate_v2' not in var('HEAL_MODELS') %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
        FROM
            {{ this }}
    )
{% endif %}
),
symbiosis AS (
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
        'v1' AS version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id :: STRING AS destination_chain_id,
        NULL AS destination_chain,
        token_address,
        NULL AS token_symbol,
        amount_unadj,
        _log_id AS _id,
        _inserted_timestamp
    FROM
        {{ ref('silver_bridge__symbiosis_synthesizerequest') }}

{% if is_incremental() and 'symbiosis' not in var('HEAL_MODELS') %}
WHERE
    _inserted_timestamp >= (
        SELECT
            MAX(_inserted_timestamp) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
        FROM
            {{ this }}
    )
{% endif %}
),
all_protocols AS (
    SELECT
        *
    FROM
        corebridge
    UNION ALL
    SELECT
        *
    FROM
        gaszip_lz
    UNION ALL
    SELECT
        *
    FROM
        meson
    UNION ALL
    SELECT
        *
    FROM
        stargate_v2
    UNION ALL
    SELECT
        *
    FROM
        symbiosis
),
complete_bridge_activity AS (
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
        version,
        sender,
        receiver,
        destination_chain_receiver,
        CASE
            WHEN CONCAT(
                platform,
                '-',
                version
            ) IN (
                'meson-v1',
                'stargate-v2-v2',
                'gaszip-lz-v2-v2',
                'core-bridge-v1'
            ) THEN destination_chain_id :: STRING
            WHEN d.chain_id IS NULL THEN destination_chain_id :: STRING
            ELSE d.chain_id :: STRING
        END AS destination_chain_id,
        CASE
            WHEN CONCAT(
                platform,
                '-',
                version
            ) IN (
                'meson-v1'
            ) THEN LOWER(destination_chain)
            WHEN d.chain IS NULL THEN LOWER(destination_chain)
            ELSE LOWER(
                d.chain
            )
        END AS destination_chain,
        b.token_address,
        CASE
            WHEN platform = 'axelar' THEN COALESCE(
                C.token_symbol,
                b.token_symbol
            )
            ELSE C.token_symbol
        END AS token_symbol,
        C.token_decimals AS token_decimals,
        amount_unadj,
        CASE
            WHEN C.token_decimals IS NOT NULL THEN (amount_unadj / pow(10, C.token_decimals))
            ELSE amount_unadj
        END AS amount,
        CASE
            WHEN C.token_decimals IS NOT NULL THEN ROUND(
                amount * p.price,
                2
            )
            ELSE NULL
        END AS amount_usd,
        _id,
        b._inserted_timestamp
    FROM
        all_protocols b
        LEFT JOIN {{ ref('silver__contracts') }} C
        ON b.token_address = C.contract_address
        LEFT JOIN {{ ref('price__ez_prices_hourly') }}
        p
        ON b.token_address = p.token_address
        AND DATE_TRUNC(
            'hour',
            block_timestamp
        ) = p.hour
        LEFT JOIN {{ source(
            'external_gold_defillama',
            'dim_chains'
        ) }}
        d
        ON d.chain_id :: STRING = b.destination_chain_id :: STRING
        OR LOWER(
            d.chain
        ) = LOWER(
            b.destination_chain
        )
),

{% if is_incremental() and var(
    'HEAL_MODEL'
) %}
heal_model AS (
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
        version,
        sender,
        receiver,
        destination_chain_receiver,
        destination_chain_id,
        destination_chain,
        t0.token_address,
        C.token_symbol AS token_symbol,
        C.token_decimals AS token_decimals,
        amount_unadj,
        CASE
            WHEN C.token_decimals IS NOT NULL THEN (amount_unadj / pow(10, C.token_decimals))
            ELSE amount_unadj
        END AS amount_heal,
        CASE
            WHEN C.token_decimals IS NOT NULL THEN amount_heal * p.price
            ELSE NULL
        END AS amount_usd_heal,
        _id,
        t0._inserted_timestamp
    FROM
        {{ this }}
        t0
        LEFT JOIN {{ ref('silver__contracts') }} C
        ON t0.token_address = C.contract_address
        LEFT JOIN {{ ref('price__ez_prices_hourly') }}
        p
        ON t0.token_address = p.token_address
        AND DATE_TRUNC(
            'hour',
            block_timestamp
        ) = p.hour
    WHERE
        CONCAT(
            t0.block_number,
            '-',
            t0.platform,
            '-',
            t0.version
        ) IN (
            SELECT
                CONCAT(
                    t1.block_number,
                    '-',
                    t1.platform,
                    '-',
                    t1.version
                )
            FROM
                {{ this }}
                t1
            WHERE
                t1.token_decimals IS NULL
                AND t1._inserted_timestamp < (
                    SELECT
                        MAX(
                            _inserted_timestamp
                        ) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
                    FROM
                        {{ this }}
                )
                AND EXISTS (
                    SELECT
                        1
                    FROM
                        {{ ref('silver__contracts') }} C
                    WHERE
                        C._inserted_timestamp > DATEADD('DAY', -14, SYSDATE())
                        AND C.token_decimals IS NOT NULL
                        AND C.contract_address = t1.token_address)
                    GROUP BY
                        1
                )
                OR CONCAT(
                    t0.block_number,
                    '-',
                    t0.platform,
                    '-',
                    t0.version
                ) IN (
                    SELECT
                        CONCAT(
                            t2.block_number,
                            '-',
                            t2.platform,
                            '-',
                            t2.version
                        )
                    FROM
                        {{ this }}
                        t2
                    WHERE
                        t2.amount_usd IS NULL
                        AND t2._inserted_timestamp < (
                            SELECT
                                MAX(
                                    _inserted_timestamp
                                ) - INTERVAL '{{ var("LOOKBACK", "4 hours") }}'
                            FROM
                                {{ this }}
                        )
                        AND EXISTS (
                            SELECT
                                1
                            FROM
                                {{ ref('silver__complete_token_prices') }}
                                p
                            WHERE
                                p._inserted_timestamp > DATEADD('DAY', -14, SYSDATE())
                                AND p.price IS NOT NULL
                                AND p.token_address = t2.token_address
                                AND p.hour = DATE_TRUNC(
                                    'hour',
                                    t2.block_timestamp
                                )
                        )
                    GROUP BY
                        1
                )
        ),
    {% endif %}

    FINAL AS (
        SELECT
            *
        FROM
            complete_bridge_activity

{% if is_incremental() and var(
    'HEAL_MODEL'
) %}
UNION ALL
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
    version,
    sender,
    receiver,
    destination_chain_receiver,
    destination_chain_id,
    destination_chain,
    token_address,
    token_symbol,
    token_decimals,
    amount_unadj,
    amount_heal AS amount,
    amount_usd_heal AS amount_usd,
    _id,
    _inserted_timestamp
FROM
    heal_model
{% endif %}
)
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
    version,
    sender,
    receiver,
    destination_chain_receiver,
    destination_chain_id,
    destination_chain,
    token_address,
    token_symbol,
    token_decimals,
    amount_unadj,
    amount,
    amount_usd,
    _id,
    _inserted_timestamp,
    {{ dbt_utils.generate_surrogate_key(
        ['_id']
    ) }} AS complete_bridge_activity_id,
    SYSDATE() AS inserted_timestamp,
    SYSDATE() AS modified_timestamp,
    '{{ invocation_id }}' AS _invocation_id
FROM
    FINAL
WHERE
    destination_chain <> 'core' qualify (ROW_NUMBER() over (PARTITION BY _id
ORDER BY
    _inserted_timestamp DESC)) = 1
