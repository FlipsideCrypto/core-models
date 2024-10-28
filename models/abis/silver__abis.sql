{{ config (
    materialized = "incremental",
    unique_key = "contract_address",
    merge_exclude_columns = ["inserted_timestamp"],
    post_hook = "ALTER TABLE {{ this }} ADD SEARCH OPTIMIZATION ON EQUALITY(contract_address), SUBSTRING(contract_address)",
    tags = ['abis']
) }}

SELECT
    contract_address,
    PARSE_JSON(
        abi_data :data :result
    ) AS DATA,
    _inserted_timestamp,
    SYSDATE() AS inserted_timestamp,
    SYSDATE() AS modified_timestamp
FROM
    {{ ref('bronze_api__contract_abis') }}
WHERE
    abi_data :data :message :: STRING = 'OK'

{% if is_incremental() %}
AND _inserted_timestamp >= (
    SELECT
        COALESCE(MAX(_inserted_timestamp), '1970-01-01'::TIMESTAMP) AS _inserted_timestamp
    FROM
        {{ this }}
)
{% endif %}