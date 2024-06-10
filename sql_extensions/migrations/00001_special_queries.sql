-- LATEST STATE {{{

-- Create a table containing the latest state for each market and auto update
-- using triggers.

CREATE TABLE inbox_latest_state AS
TABLE inbox_events
WITH NO DATA;

ALTER TABLE inbox_latest_state
ADD COLUMN market_id NUMERIC;

ALTER TABLE inbox_latest_state
ADD PRIMARY KEY (market_id);

INSERT INTO inbox_latest_state (
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    type,
    data,
    inserted_at,
    event_index,
    indexed_type,
    market_id,
    event_name
)
SELECT DISTINCT ON ((data -> 'market_metadata' ->> 'market_id')::NUMERIC)
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    type,
    data,
    inserted_at,
    event_index,
    indexed_type,
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id,
    event_name
FROM
    inbox_events
WHERE
    event_name = 'emojicoin_dot_fun::State'
ORDER BY
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC,
    (data ->> 'transaction_version')::NUMERIC DESC,
    (data -> 'state_metadata' ->> 'market_nonce')::NUMERIC DESC;

CREATE OR REPLACE FUNCTION UPDATE_LATEST_STATE()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO inbox_latest_state (
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    type,
    data,
    inserted_at,
    event_index,
    indexed_type,
    event_name,
    market_id
  )
  SELECT
    NEW.sequence_number,
    NEW.creation_number,
    NEW.account_address,
    NEW.transaction_version,
    NEW.transaction_block_height,
    NEW.type,
    NEW.data,
    NEW.inserted_at,
    NEW.event_index,
    NEW.indexed_type,
    NEW.event_name,
    (NEW.data -> 'market_metadata' ->> 'market_id')::NUMERIC
  ON CONFLICT (market_id) DO UPDATE SET
    transaction_version = EXCLUDED.transaction_version,
    transaction_block_height = EXCLUDED.transaction_block_height,
    data = EXCLUDED.data,
    inserted_at = EXCLUDED.inserted_at,
    event_index = EXCLUDED.event_index
  WHERE
    (inbox_latest_state.data -> 'market_metadata' ->> 'market_id')::NUMERIC = (EXCLUDED.data -> 'market_metadata' ->> 'market_id')::NUMERIC
  AND
    (inbox_latest_state.data -> 'state_metadata' ->> 'market_nonce')::NUMERIC < (EXCLUDED.data -> 'state_metadata' ->> 'market_nonce')::NUMERIC;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_latest_state
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.event_name = 'emojicoin_dot_fun::State')
EXECUTE PROCEDURE UPDATE_LATEST_STATE();

CREATE INDEX inbox_latest_state_by_market_cap ON inbox_events (
    ((data -> 'instantaneous_stats' ->> 'market_cap')::NUMERIC) DESC
);

CREATE INDEX inbox_latest_state_by_nonce ON inbox_events (
    ((data -> 'state_metadata' ->> 'market_nonce')::NUMERIC) DESC
);

-- }}}

-- VOLUME {{{

-- Create a table containing the daily and all time volume for each market and
-- auto update using triggers.

CREATE OR REPLACE FUNCTION GET_DAILY_VOLUME(JSONB)
RETURNS NUMERIC AS $$
DECLARE
    res NUMERIC;
BEGIN
    WITH raw AS (
        SELECT * FROM jsonb_to_recordset($1) AS x(time numeric, volume_quote numeric)
    ),
    less_raw AS (
        SELECT time / 1000000 AS time, volume_quote AS volume_quote FROM raw
    )
    SELECT COALESCE(SUM(volume_quote), 0) INTO res FROM less_raw WHERE time > extract(epoch from (now() - interval '1 day'));
    RETURN res;
END;
$$ IMMUTABLE LANGUAGE plpgsql;

CREATE TABLE inbox_volume (
    market_id NUMERIC PRIMARY KEY,
    all_time_volume NUMERIC NOT NULL,
    volume_events JSONB NOT NULL
);

CREATE FUNCTION DAILY_VOLUME(INBOX_VOLUME)
RETURNS NUMERIC AS $$
  SELECT GET_DAILY_VOLUME($1.volume_events);
$$ IMMUTABLE LANGUAGE sql;

INSERT INTO inbox_volume
SELECT
    (data #>> '{market_metadata,market_id}')::NUMERIC AS market_id,
    0::NUMERIC AS all_time_volume,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'time',
            (data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC,
            'volume_quote',
            (data ->> 'volume_quote')::NUMERIC
        )
    ) AS volume_events
FROM
    inbox_events
WHERE
    event_name = 'emojicoin_dot_fun::PeriodicState'
    AND
    (data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC / 1000000
    > EXTRACT(EPOCH FROM (NOW() - INTERVAL '1 day'))
    AND
    data -> 'periodic_state_metadata' ->> 'period' = '60000000'
GROUP BY
    data #>> '{market_metadata,market_id}';

UPDATE inbox_volume SET all_time_volume = COALESCE(tmp.volume, 0)
FROM (
    SELECT
        (data #>> '{market_metadata,market_id}')::NUMERIC AS market_id,
        SUM((data ->> 'volume_quote')::NUMERIC) AS volume
    FROM
        inbox_events
    WHERE
        event_name = 'emojicoin_dot_fun::PeriodicState'
        AND
        data -> 'periodic_state_metadata' ->> 'period' = '60000000'
    GROUP BY
        data #>> '{market_metadata,market_id}'
) AS tmp
WHERE tmp.market_id = inbox_volume.market_id;

CREATE OR REPLACE FUNCTION UPDATE_VOLUME()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (SELECT * FROM inbox_volume WHERE market_id = (NEW.data->'market_metadata'->>'market_id')::numeric) THEN
    INSERT INTO inbox_volume VALUES ((NEW.data->'market_metadata'->>'market_id')::numeric, 0::numeric, '[]'::jsonb);
  END IF;
  UPDATE inbox_volume
  SET
    volume_events = (
      SELECT COALESCE(
        json_agg(json_build_object('time', (e.data->'periodic_state_metadata'->>'start_time')::numeric, 'volume_quote', (e.data->>'volume_quote')::numeric)),
        '[]'::jsonb
      )
      FROM inbox_events e
      WHERE e.event_name = 'emojicoin_dot_fun::PeriodicState'
      AND (e.data->'periodic_state_metadata'->>'start_time')::numeric / 1000000 > extract(epoch from (now() - interval '1 day'))
      AND e.data->'periodic_state_metadata'->>'period' = '60000000'
      AND (e.data->'market_metadata'->>'market_id')::numeric = (NEW.data->'market_metadata'->>'market_id')::numeric
    ),
    all_time_volume = inbox_volume.all_time_volume + (NEW.data->>'volume_quote')::numeric
  WHERE
    inbox_volume.market_id = (NEW.data->'market_metadata'->>'market_id')::numeric;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_volume
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (
    new.event_name = 'emojicoin_dot_fun::PeriodicState'
    AND new.data -> 'periodic_state_metadata' ->> 'period' = '60000000'
)
EXECUTE PROCEDURE UPDATE_VOLUME();

CREATE INDEX inbox_latest_state_by_all_time_volume ON inbox_volume (
    all_time_volume DESC
);
CREATE INDEX inbox_latest_state_by_daily_volume ON inbox_volume (
    DAILY_VOLUME(inbox_volume) DESC
);

-- }}}

-- noqa: disable=ST06
CREATE VIEW market_data AS
SELECT
    -- General data
    (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id,
    (registration.data -> 'market_metadata' ->> 'emoji_bytes') AS emoji_bytes,
    (registration.data -> 'market_metadata' ->> 'market_address') AS market_address,
    -- Latest state data
    state.transaction_version,
    (state.data -> 'instantaneous_stats' ->> 'market_cap')::NUMERIC AS market_cap,
    (state.data -> 'state_metadata' ->> 'bump_time')::NUMERIC AS bump_time,
    (state.data -> 'cumulative_stats' ->> 'n_swaps')::NUMERIC AS n_swaps,
    (state.data -> 'cumulative_stats' ->> 'n_chat_messages')::NUMERIC AS n_chat_messages,
    (state.data -> 'last_swap' ->> 'avg_execution_price_q64')::NUMERIC AS avg_execution_price_q64,
    (state.data ->> 'lp_coin_supply')::NUMERIC AS lp_coin_supply,
    state.data -> 'clamm_virtual_reserves' AS clamm_virtual_reserves,
    state.data -> 'cpamm_real_reserves' AS cpamm_real_reserves,
    -- Volume data
    COALESCE(volume.all_time_volume, 0) AS all_time_volume,
    DAILY_VOLUME(volume) AS daily_volume -- noqa: RF02
FROM (
    SELECT data FROM inbox_events WHERE event_name = 'emojicoin_dot_fun::MarketRegistration'
) AS registration
LEFT JOIN inbox_latest_state AS state
    ON (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC = state.market_id
LEFT JOIN inbox_volume AS volume
    ON (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC = volume.market_id;
-- noqa: disable=ST06

CREATE INDEX inbox_periodic_state ON inbox_events (
    ((data -> 'market_metadata' ->> 'market_id')::NUMERIC),
    ((data -> 'periodic_state_metadata' ->> 'period')::NUMERIC),
    ((data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC)
) WHERE event_name = 'emojicoin_dot_fun::PeriodicState';

-- vim: foldmethod=marker foldenable
