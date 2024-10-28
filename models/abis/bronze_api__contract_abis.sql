{{ config(
    materialized = 'incremental',
    unique_key = "contract_address",
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION on equality(contract_address)",
    full_refresh = false,
    tags = ['core']
) }}

WITH base AS (

    SELECT
        contract_address,
        total_interaction_count
    FROM
        {{ ref('silver__relevant_contracts') }}
    WHERE
        1=1

{% if is_incremental() %}
AND contract_address NOT IN (
    SELECT
        contract_address
    FROM
        {{ this }}
    WHERE
        1=1 and 
        abi_data:error is null
)
{% endif %}
ORDER BY
    total_interaction_count DESC
LIMIT
    50
), all_contracts AS (
    SELECT
        contract_address
    FROM
        base
),
row_nos AS (
    SELECT
        contract_address,
        ROW_NUMBER() over (
            ORDER BY
                contract_address
        ) AS row_no
    FROM
        all_contracts
),
batched AS ({% for item in range(51) %}
SELECT
    rn.contract_address, 
    live.udf_api('GET', 
        CONCAT('https://openapi.coredao.org/api?module=contract&action=getabi&address=', rn.contract_address, '&apikey=0debd4f48046460aad5142ee2a145661'),
        {'User-Agent': 'FlipsideStreamline'},
        {}
    ) AS abi_data
FROM
    row_nos rn
WHERE
    row_no = {{ item }}

    {% if not loop.last %}
    UNION ALL
    {% endif %}
{% endfor %})
SELECT
    contract_address,
    abi_data,
    SYSDATE() AS _inserted_timestamp
FROM
    batched
