{{ config(
    materialized = 'view',
    tags = ['observability']
) }}

SELECT
    column1 AS block_number
FROM
    (
        VALUES
            (0),
            (1)
    ) AS block_number(column1)
