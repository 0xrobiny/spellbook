CREATE OR REPLACE FUNCTION dex.insert_kyber(start_ts timestamptz, end_ts timestamptz=now(), start_block numeric=0, end_block numeric=9e18) RETURNS integer
LANGUAGE plpgsql AS $function$
DECLARE r integer;
BEGIN
WITH rows AS (
    INSERT INTO dex.trades (
        block_time,
        token_a_symbol,
        token_b_symbol,
        token_a_amount,
        token_b_amount,
        project,
        version,
        category,
        trader_a,
        trader_b,
        token_a_amount_raw,
        token_b_amount_raw,
        usd_amount,
        token_a_address,
        token_b_address,
        exchange_contract_address,
        tx_hash,
        tx_from,
        tx_to,
        trace_address,
        evt_index,
        trade_id
    )
    SELECT
        dexs.block_time,
        bep20a.symbol AS token_a_symbol,
        bep20b.symbol AS token_b_symbol,
        token_a_amount_raw / 10 ^ bep20a.decimals AS token_a_amount,
        token_b_amount_raw / 10 ^ bep20b.decimals AS token_b_amount,
        project,
        version,
        category,
        coalesce(trader_a, tx."from") as trader_a, -- subqueries rely on this COALESCE to avoid redundant joins with the transactions table
        trader_b,
        token_a_amount_raw,
        token_b_amount_raw,
        coalesce(
            usd_amount,
            token_a_amount_raw / 10 ^ pa.decimals * pa.price,
            token_b_amount_raw / 10 ^ pb.decimals * pb.price
        ) as usd_amount,
        token_a_address,
        token_b_address,
        exchange_contract_address,
        tx_hash,
        tx."from" as tx_from,
        tx."to" as tx_to,
        trace_address,
        evt_index,
        row_number() OVER (PARTITION BY project, tx_hash, evt_index, trace_address ORDER BY version, category) AS trade_id
    FROM (
        SELECT
            t.evt_block_time AS block_time,
            'Kyber' AS project,
            'dmm' AS version,
            'DEX' AS category,
            t."to" AS trader_a,
            NULL::bytea AS trader_b,
            CASE WHEN "amount0Out" = 0 THEN "amount1Out" ELSE "amount0Out" END AS token_a_amount_raw,
            CASE WHEN "amount0In" = 0 OR "amount1Out" = 0 THEN "amount1In" ELSE "amount0In" END AS token_b_amount_raw,
            NULL::numeric AS usd_amount,
            CASE WHEN "amount0Out" = 0 THEN f.token1 ELSE f.token0 END AS token_a_address,
            CASE WHEN "amount0In" = 0 OR "amount1Out" = 0 THEN f.token1 ELSE f.token0 END AS token_b_address,
            t.contract_address AS exchange_contract_address,
            t.evt_tx_hash AS tx_hash,
            NULL::integer[] AS trace_address,
            t.evt_index
        FROM
            kyber."DMMPool_evt_Swap" t
        INNER JOIN kyber."Kyber Swap: Factory_evt_PoolCreated" f ON f.pool = t.contract_address        
        AND t.evt_block_time >= start_ts AND t.evt_block_time < end_ts

        UNION ALL
        
        -- from Aggregator 
        SELECT
            evt_block_time AS block_time,
            'Kyber' AS project,
            'v1' AS version,
            'Aggregator' AS category,
            sender AS trader_a,
            NULL::bytea AS trader_b,
            "spentAmount" token_a_amount_raw,
            "returnAmount" token_b_amount_raw,
            NULL::numeric AS usd_amount,
            (CASE WHEN "srcToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "srcToken" END) AS token_a_address,
            (CASE WHEN "dstToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "dstToken" END) AS token_b_address,
            contract_address AS exchange_contract_address,
            evt_tx_hash AS tx_hash,
            NULL::integer[] AS trace_address,
            evt_index AS evt_index
        FROM kyber."AggregationRouter_evt_Swapped"
        WHERE evt_block_time >= start_ts AND evt_block_time < end_ts

        UNION ALL
        SELECT
            evt_block_time AS block_time,
            'Kyber' AS project,
            'v2' AS version,
            'Aggregator' AS category,
            sender AS trader_a,
            NULL::bytea AS trader_b,
            "spentAmount" token_a_amount_raw,
            "returnAmount" token_b_amount_raw,
            NULL::numeric AS usd_amount,
            (CASE WHEN "srcToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "srcToken" END) AS token_a_address,
            (CASE WHEN "dstToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "dstToken" END) AS token_b_address,
            contract_address AS exchange_contract_address,
            evt_tx_hash AS tx_hash,
            NULL::integer[] AS trace_address,
            evt_index AS evt_index
        FROM kyber."AggregationRouterV2_evt_Swapped"
        WHERE evt_block_time >= start_ts AND evt_block_time < end_ts

        UNION ALL
        SELECT
            evt_block_time AS block_time,
            'Kyber' AS project,
            'v3' AS version,
            'Aggregator' AS category,
            sender AS trader_a,
            NULL::bytea AS trader_b,
            "spentAmount" token_a_amount_raw,
            "returnAmount" token_b_amount_raw,
            NULL::numeric AS usd_amount,
            (CASE WHEN "srcToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "srcToken" END) AS token_a_address,
            (CASE WHEN "dstToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "dstToken" END) AS token_b_address,
            contract_address AS exchange_contract_address,
            evt_tx_hash AS tx_hash,
            NULL::integer[] AS trace_address,
            evt_index AS evt_index
        FROM kyber."AggregationRouterV3_evt_Swapped"
        WHERE evt_block_time >= start_ts AND evt_block_time < end_ts

        UNION ALL
        SELECT
            evt_block_time AS block_time,
            'Kyber' AS project,
            'v4' AS version,
            'Aggregator' AS category,
            sender AS trader_a,
            NULL::bytea AS trader_b,
            "spentAmount" token_a_amount_raw,
            "returnAmount" token_b_amount_raw,
            NULL::numeric AS usd_amount,
            (CASE WHEN "srcToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "srcToken" END) AS token_a_address,
            (CASE WHEN "dstToken" = '\xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' THEN '\xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c' ELSE "dstToken" END) AS token_b_address,
            contract_address AS exchange_contract_address,
            evt_tx_hash AS tx_hash,
            NULL::integer[] AS trace_address,
            evt_index AS evt_index
        FROM kyber."MetaAggregationRouter_evt_Swapped"
        WHERE evt_block_time >= start_ts AND evt_block_time < end_ts
    ) dexs
    INNER JOIN bsc.transactions tx
        ON dexs.tx_hash = tx.hash
        AND tx.block_time >= start_ts
        AND tx.block_time < end_ts
        AND tx.block_number >= start_block
        AND tx.block_number < end_block
    LEFT JOIN bep20.tokens bep20a ON bep20a.contract_address = dexs.token_a_address
    LEFT JOIN bep20.tokens bep20b ON bep20b.contract_address = dexs.token_b_address
    LEFT JOIN prices.usd pa ON pa.minute = date_trunc('minute', dexs.block_time)
        AND pa.contract_address = dexs.token_a_address
        AND pa.minute >= start_ts
        AND pa.minute < end_ts
    LEFT JOIN prices.usd pb ON pb.minute = date_trunc('minute', dexs.block_time)
        AND pb.contract_address = dexs.token_b_address
        AND pb.minute >= start_ts
        AND pb.minute < end_ts
    WHERE dexs.block_time >= start_ts
    AND dexs.block_time < end_ts
    ON CONFLICT DO NOTHING
    RETURNING 1
)
SELECT count(*) INTO r from rows;
RETURN r;
END
$function$;

-- in rebuild, drop data prior to refresh
DELETE FROM dex.trades WHERE project='Kyber'
;

-- fill 2019
SELECT dex.insert_kyber(
    '2019-01-01',
    '2020-01-01',
    (SELECT max(number) FROM bsc.blocks WHERE time < '2019-01-01'),
    (SELECT max(number) FROM bsc.blocks WHERE time <= '2020-01-01')
)
;

-- fill 2020
SELECT dex.insert_kyber(
    '2020-01-01',
    '2021-01-01',
    (SELECT max(number) FROM bsc.blocks WHERE time < '2020-01-01'),
    (SELECT max(number) FROM bsc.blocks WHERE time <= '2021-01-01')
)
;

-- fill 2021
SELECT dex.insert_kyber(
    '2021-01-01',
    '2022-01-01',
    (SELECT max(number) FROM bsc.blocks WHERE time < '2021-01-01'),
    (SELECT max(number) FROM bsc.blocks WHERE time <= '2022-01-01')
)
;

-- fill 2022
SELECT dex.insert_kyber(
    '2022-01-01',
    now(),
    (SELECT max(number) FROM bsc.blocks WHERE time < '2022-01-01'),
    (SELECT MAX(number) FROM bsc.blocks where time < now() - interval '20 minutes')
)
;

-- INSERT INTO cron.job (schedule, command)
-- VALUES ('*/10 * * * *', $$
--     SELECT dex.insert_kyber(
--         (SELECT max(block_time) - interval '1 days' FROM dex.trades WHERE project='Kyber'),
--         (SELECT now() - interval '20 minutes'),
--         (SELECT max(number) FROM bsc.blocks WHERE time < (SELECT max(block_time) - interval '1 days' FROM dex.trades WHERE project='Kyber')),
--         (SELECT MAX(number) FROM bsc.blocks where time < now() - interval '20 minutes'));
-- $$)
-- ON CONFLICT (command) DO UPDATE SET schedule=EXCLUDED.schedule;
