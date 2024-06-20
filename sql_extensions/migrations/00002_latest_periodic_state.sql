-- LATEST ONE DAY PERIODIC STATE {{{

-- Create a table containing the latest one day periodic state for each market
-- and auto update using triggers.

CREATE TABLE inbox_latest_one_day_periodic_state AS
TABLE inbox_events
WITH NO DATA;

ALTER TABLE inbox_latest_one_day_periodic_state
ADD COLUMN market_id NUMERIC;

ALTER TABLE inbox_latest_one_day_periodic_state
ADD PRIMARY KEY (market_id);

-- Add latest 1-day periodic state event for each market into table
INSERT INTO inbox_latest_one_day_periodic_state (
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    "type",
    "data",
    inserted_at,
    event_index,
    indexed_type,
    market_id,
    event_name
)
SELECT DISTINCT ON (("data" -> 'market_metadata' ->> 'market_id')::NUMERIC)
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    "type",
    "data",
    inserted_at,
    event_index,
    indexed_type,
    ("data" -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id,
    event_name
FROM
    inbox_events
WHERE
    event_name = 'emojicoin_dot_fun::PeriodicState'
    AND "data" -> 'periodic_state_metadata' ->> 'period' = '86400000000'
ORDER BY
    ("data" -> 'market_metadata' ->> 'market_id')::NUMERIC,
    ("data" ->> 'transaction_version')::NUMERIC DESC,
    ("data" -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC DESC;

-- Update the latest 1-day periodic state event for a market
CREATE OR REPLACE FUNCTION UPDATE_LATEST_ONE_DAY_PERIODIC_STATE()
RETURNS TRIGGER AS $$
BEGIN
  -- Lock this operation using an arbitrary common ID for other potentially
  -- conflicting operations
  PERFORM pg_advisory_xact_lock(42);
  INSERT INTO inbox_latest_one_day_periodic_state (
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    "type",
    "data",
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
    NEW."type",
    NEW."data",
    NEW.inserted_at,
    NEW.event_index,
    NEW.indexed_type,
    NEW.event_name,
    (NEW."data" -> 'market_metadata' ->> 'market_id')::NUMERIC
  ON CONFLICT (market_id) DO UPDATE SET
    transaction_version = EXCLUDED.transaction_version,
    transaction_block_height = EXCLUDED.transaction_block_height,
    "data" = EXCLUDED."data",
    inserted_at = EXCLUDED.inserted_at,
    event_index = EXCLUDED.event_index
  WHERE
    (inbox_latest_one_day_periodic_state."data" -> 'market_metadata' ->> 'market_id')::NUMERIC = (EXCLUDED."data" -> 'market_metadata' ->> 'market_id')::NUMERIC
  AND
    (inbox_latest_one_day_periodic_state."data" -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC < (EXCLUDED."data" -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC
  AND
    NEW."data" -> 'periodic_state_metadata' ->> 'period' = '86400000000';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update the latest one day periodic state event for each market whenever a
-- new periodic state event is logged
CREATE TRIGGER update_latest_one_day_periodic_state
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.event_name = 'emojicoin_dot_fun::PeriodicState')
EXECUTE PROCEDURE UPDATE_LATEST_ONE_DAY_PERIODIC_STATE();

DROP VIEW market_data;
-- noqa: disable=ST06
CREATE VIEW market_data AS
SELECT
    -- General data
    (registration."data" -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id,
    (registration."data" -> 'market_metadata' ->> 'emoji_bytes') AS emoji_bytes,
    (registration."data" -> 'market_metadata' ->> 'market_address') AS market_address,
    -- Latest state data
    state.transaction_version,
    (state."data" -> 'instantaneous_stats' ->> 'market_cap')::NUMERIC AS market_cap,
    (state."data" -> 'state_metadata' ->> 'bump_time')::NUMERIC AS bump_time,
    (state."data" -> 'cumulative_stats' ->> 'n_swaps')::NUMERIC AS n_swaps,
    (state."data" -> 'cumulative_stats' ->> 'n_chat_messages')::NUMERIC AS n_chat_messages,
    (state."data" -> 'last_swap' ->> 'avg_execution_price_q64')::NUMERIC AS last_swap_avg_execution_price_q64,
    (state."data" ->> 'lp_coin_supply')::NUMERIC AS lp_coin_supply,
    (state."data" -> 'clamm_virtual_reserves' ->> 'base')::NUMERIC AS clamm_virtual_reserves_base,
    (state."data" -> 'clamm_virtual_reserves' ->> 'quote')::NUMERIC AS clamm_virtual_reserves_quote,
    (state."data" -> 'cpamm_real_reserves' ->> 'base')::NUMERIC AS cpamm_real_reserves_base,
    (state."data" -> 'cpamm_real_reserves' ->> 'quote')::NUMERIC AS cpamm_real_reserves_quote,
    (state."data" -> 'cumulative_stats' ->> 'quote_volume')::NUMERIC AS all_time_volume,
    -- Volume data
    DAILY_VOLUME(volume) AS daily_volume, -- noqa: RF02
    (periodic_state."data" ->> 'tvl_per_lp_coin_growth_q64')::NUMERIC AS one_day_tvl_per_lp_coin_growth_q64
FROM (
    SELECT "data" FROM inbox_events WHERE event_name = 'emojicoin_dot_fun::MarketRegistration'
) AS registration
LEFT JOIN inbox_latest_state AS state
    ON (registration."data" -> 'market_metadata' ->> 'market_id')::NUMERIC = state.market_id
LEFT JOIN inbox_volume AS volume
    ON (registration."data" -> 'market_metadata' ->> 'market_id')::NUMERIC = volume.market_id
LEFT JOIN inbox_latest_one_day_periodic_state AS periodic_state
    ON (registration."data" -> 'market_metadata' ->> 'market_id')::NUMERIC = periodic_state.market_id;
-- noqa: disable=ST06

CREATE INDEX inbox_latest_periodic_state_by_tvl ON inbox_events (
    (("data" ->> 'tvl_per_lp_coin_growth_q64')::NUMERIC) DESC
) WHERE ("data" ->> 'ends_in_bonding_curve')::BOOLEAN = true;

-- }}}

-- ADD LOCK TO PREVIOUS TRIGGERS {{{

-- Modify latest state update function to include a lock
CREATE OR REPLACE FUNCTION UPDATE_LATEST_STATE()
RETURNS TRIGGER AS $$
BEGIN
  -- Lock this operation using an arbitrary common ID for
  -- other potentially conflicting operations
  PERFORM pg_advisory_xact_lock(42);
  INSERT INTO inbox_latest_state (
    sequence_number,
    creation_number,
    account_address,
    transaction_version,
    transaction_block_height,
    "type",
    "data",
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
    NEW."type",
    NEW."data",
    NEW.inserted_at,
    NEW.event_index,
    NEW.indexed_type,
    NEW.event_name,
    (NEW."data" -> 'market_metadata' ->> 'market_id')::NUMERIC
  ON CONFLICT (market_id) DO UPDATE SET
    transaction_version = EXCLUDED.transaction_version,
    transaction_block_height = EXCLUDED.transaction_block_height,
    "data" = EXCLUDED."data",
    inserted_at = EXCLUDED.inserted_at,
    event_index = EXCLUDED.event_index
  WHERE
    (inbox_latest_state."data" -> 'market_metadata' ->> 'market_id')::NUMERIC = (EXCLUDED."data" -> 'market_metadata' ->> 'market_id')::NUMERIC
  AND
    (inbox_latest_state."data" -> 'state_metadata' ->> 'market_nonce')::NUMERIC < (EXCLUDED."data" -> 'state_metadata' ->> 'market_nonce')::NUMERIC;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Modify volume update function to include a lock
-- Also remove all time volume as it is not needed anymore
CREATE OR REPLACE FUNCTION UPDATE_VOLUME()
RETURNS TRIGGER AS $$
BEGIN
  -- Lock this operation using an arbitrary common ID for
  -- other potentially conflicting operations
  PERFORM pg_advisory_xact_lock(42);
  INSERT INTO inbox_volume (market_id, volume_events)
  VALUES (
    (NEW."data"->'market_metadata'->>'market_id')::numeric,
    '[]'::jsonb
  )
    ON CONFLICT (market_id) DO NOTHING;
  UPDATE inbox_volume
  SET
    volume_events = (
      SELECT COALESCE(
        jsonb_agg(jsonb_build_object('time', (e."data"->'periodic_state_metadata'->>'start_time')::numeric, 'volume_quote', (e."data"->>'volume_quote')::numeric)),
        '[]'::jsonb
      )
      FROM inbox_events e
      WHERE e.event_name = 'emojicoin_dot_fun::PeriodicState'
        AND (e."data"->'periodic_state_metadata'->>'start_time')::numeric / 1000000 > extract(epoch from (now() - interval '1 day'))
        AND e."data"->'periodic_state_metadata'->>'period' = '60000000'
        AND (e."data"->'market_metadata'->>'market_id')::numeric = (NEW."data"->'market_metadata'->>'market_id')::numeric
    )
  WHERE
    inbox_volume.market_id = (NEW."data"->'market_metadata'->>'market_id')::numeric;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE inbox_volume DROP COLUMN all_time_volume;

CREATE INDEX inbox_latest_state_by_all_time_volume ON inbox_latest_state (
    (("data" -> 'cumulative_stats' ->> 'quote_volume')::NUMERIC) DESC
);


-- }}}

-- FIX VACUUM ERROR {{{
CREATE OR REPLACE FUNCTION DAILY_VOLUME(INBOX_VOLUME)
RETURNS NUMERIC AS $$
  SELECT public.GET_DAILY_VOLUME($1.volume_events::jsonb);
$$ IMMUTABLE LANGUAGE sql;
-- }}}

-- vim: foldmethod=marker foldenable
