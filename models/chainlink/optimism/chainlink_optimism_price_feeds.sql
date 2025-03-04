{{ config(
    alias = 'price_feeds',
    partition_by = ['block_date'],
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['blockchain', 'block_time', 'proxy_address', 'oracle_price', 'aggregator_address', 'underlying_token_address'],
    post_hook='{{ expose_spells(\'["optimism"]\',
                                "project",
                                "chainlink",
                                \'["msilb7"]\') }}'
    )
}}
-- OVM1 Launch
{% set project_start_date = '2021-06-23' %}
{% set answer_updated = '0x0559884fd3a460db3073b7fc896cc77986f16e378210ded43186175bf646fc5f' %}


SELECT
    'optimism' as blockchain
    , c.block_time
    , c.block_date
    , c.feed_name
    , c.oracle_price
    , c.proxy_address
    , c.aggregator_address
    , COALESCE(o.underlying_token_address, 'n/a') AS underlying_token_address
    , c.oracle_price / POWER(10 , o.extra_decimals) AS underlying_token_price
FROM
(
    SELECT
        l.block_time
        , DATE_TRUNC('day', l.block_time) AS block_date
	    , cfa.feed_name
	    , AVG(
            conv( --handle for multiple updates in the same block
            substring(l.topic2,3,64) 
            ,16,10)
            / POWER(10, cfa.decimals)
            ) AS oracle_price
	    , cfa.proxy_address
        , cfa.aggregator_address
	FROM {{ source('optimism', 'logs') }} l
	INNER JOIN {{ ref('chainlink_optimism_oracle_addresses') }} cfa
	    ON l.contract_address = cfa.aggregator_address
	WHERE l.topic1 = '{{answer_updated}}'
        {% if not is_incremental() %}
        AND l.block_time >= '{{project_start_date}}'
        {% endif %}
        {% if is_incremental() %}
        AND l.block_time >= date_trunc("day", now() - interval '1 week')
        {% endif %}
    GROUP BY
        l.block_time
        , block_date
        , cfa.feed_name
        , cfa.proxy_address
        , cfa.aggregator_address
) c
LEFT JOIN {{ ref('chainlink_optimism_oracle_token_mapping') }} o
	ON c.proxy_address = o.proxy_address
;