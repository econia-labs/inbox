-- LATEST EVENTS {{{

-- Create a table containing the latest state for each market and auto update
-- using triggers.

CREATE TABLE inbox_latest_state AS
TABLE inbox_events
WITH NO DATA;

ALTER TABLE inbox_latest_state
ADD COLUMN market_id NUMERIC;

ALTER TABLE inbox_latest_state
ADD PRIMARY KEY (market_id);

INSERT INTO inbox_latest_state
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
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id
FROM
    inbox_events
WHERE
    REVERSE(indexed_type) LIKE REVERSE('%::emojicoin_dot_fun::State')
ORDER BY
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC,
    (data ->> 'transaction_version')::NUMERIC DESC,
    (data ->> 'event_index')::NUMERIC DESC;

CREATE OR REPLACE FUNCTION UPDATE_LATEST_STATE()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM inbox_latest_state
  WHERE (inbox_latest_state.data->'market_metadata'->>'market_id')::numeric = (NEW.data->'market_metadata'->>'market_id')::numeric
  AND (inbox_latest_state.data->'state_metadata'->>'bump_time')::numeric <= (NEW.data->'state_metadata'->>'bump_time')::numeric;
  INSERT INTO inbox_latest_state SELECT NEW.*;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_latest_state
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.type LIKE '%::emojicoin_dot_fun::State')
EXECUTE PROCEDURE UPDATE_LATEST_STATE();

CREATE INDEX inbox_latest_state_by_market_cap ON inbox_events (
    ((data -> 'instantaneous_stats' ->> 'market_cap')::NUMERIC) DESC
);

CREATE INDEX inbox_latest_state_by_bump_time ON inbox_events (
    ((data -> 'state_metadata' ->> 'bump_time')::NUMERIC) DESC
);

-- }}}

-- VOLUME {{{

-- Create a table containing the daily and all time volume for each market and
-- auto update using triggers.

CREATE TABLE inbox_volume (
    market_id NUMERIC PRIMARY KEY,
    all_time_volume NUMERIC NOT NULL,
    daily_volume NUMERIC NOT NULL
);

INSERT INTO inbox_volume
SELECT
    (data #>> '{market_metadata,market_id}')::NUMERIC AS market_id,
    0::NUMERIC AS all_time_volume,
    SUM((data ->> 'volume_quote')::NUMERIC) AS daily_volume
FROM
    inbox_events
WHERE
    REVERSE(indexed_type) LIKE REVERSE('%::emojicoin_dot_fun::PeriodicState')
    AND
    TO_TIMESTAMP((data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC / 1000)
    > CURRENT_TIMESTAMP - INTERVAL '1 day'
    AND
    data -> 'periodic_state_metadata' ->> 'period' = '60000000'
GROUP BY
    data #>> '{market_metadata,market_id}';

UPDATE inbox_volume SET all_time_volume = tmp.volume
FROM (
    SELECT
        (data #>> '{market_metadata,market_id}')::NUMERIC AS market_id,
        SUM((data ->> 'volume_quote')::NUMERIC) AS volume
    FROM
        inbox_events
    WHERE
        REVERSE(indexed_type) LIKE REVERSE('%::emojicoin_dot_fun::PeriodicState')
        AND
        data -> 'periodic_state_metadata' ->> 'period' = '900000000'
    GROUP BY
        data #>> '{market_metadata,market_id}'
) AS tmp
WHERE tmp.market_id = inbox_volume.market_id;

CREATE OR REPLACE FUNCTION UPDATE_VOLUME()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (SELECT * FROM inbox_volume WHERE market_id = (NEW.data->'market_metadata'->>'market_id')::numeric) THEN
    INSERT INTO inbox_volume VALUES ((NEW.data->'market_metadata'->>'market_id')::numeric, 0::numeric, 0::numeric);
  END IF;
  UPDATE inbox_volume
  SET
    daily_volume = (
      SELECT SUM((e.data->>'volume_quote')::numeric) FROM inbox_events e
      WHERE REVERSE(e.indexed_type) LIKE REVERSE('%::emojicoin_dot_fun::PeriodicState')
      AND to_timestamp((e.data->'periodic_state_metadata'->>'start_time')::numeric / 1000) > CURRENT_TIMESTAMP - interval '1 day'
      AND e.data->'periodic_state_metadata'->>'period' = '60000000'
      AND (e.data->'market_metadata'->>'market_id')::numeric = (NEW.data->'market_metadata'->>'market_id')::numeric
    ),
    all_time_volume = inbox_volume.all_time_volume + (NEW.data->>'volume_quote')::numeric
  WHERE
    inbox_volume.market_id = (NEW.data->'market_metadata'->'market_id')::numeric;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_volume
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (
    new.type LIKE '%::emojicoin_dot_fun::PeriodicState'
    AND new.data -> 'periodic_state_metadata' ->> 'period' = '60000000'
)
EXECUTE PROCEDURE UPDATE_VOLUME();

CREATE INDEX inbox_latest_state_by_all_time_volume ON inbox_volume (
    all_time_volume DESC
);
CREATE INDEX inbox_latest_state_by_daily_volume ON inbox_volume (
    daily_volume DESC
);

-- }}}

CREATE VIEW market_data AS
SELECT
    state.market_id,
    state.transaction_version,
    (state.data -> 'instantaneous_stats' ->> 'market_cap')::NUMERIC AS market_cap,
    (state.data -> 'state_metadata' ->> 'bump_time')::NUMERIC AS bump_time,
    (state.data -> 'cumulative_stats' ->> 'n_swaps')::NUMERIC AS n_swaps,
    (state.data -> 'cumulative_stats' ->> 'n_chat_messages')::NUMERIC AS n_chat_messages,
    state.data -> 'clamm_virtual_reserves' AS clamm_virtual_reserves,
    state.data -> 'cpamm_real_reserves' AS cpamm_real_reserves,
    volume.all_time_volume,
    volume.daily_volume
FROM inbox_latest_state AS state, inbox_volume AS volume
WHERE state.market_id = volume.market_id;

CREATE INDEX inbox_indexed_type ON inbox_events (REVERSE(indexed_type));
CREATE INDEX inbox_indexed_type ON inbox_events (indexed_type);

CREATE INDEX inbox_periodic_state ON inbox_events (
    ((data -> 'market_metadata' ->> 'market_id')::NUMERIC),
    ((data -> 'periodic_state_metadata' ->> 'period')::NUMERIC),
    ((data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC)
) WHERE REVERSE(indexed_type) LIKE REVERSE('%::emojicoin_dot_fun::PeriodicState');

-- vim: foldmethod=marker foldenable
