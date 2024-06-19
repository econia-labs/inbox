-- LATEST PERIODIC STATE {{{

-- Create a table containing the latest periodic state for each market and auto
-- update using triggers.

CREATE TABLE inbox_latest_periodic_state AS
TABLE inbox_events
WITH NO DATA;

ALTER TABLE inbox_latest_periodic_state
ADD COLUMN market_id NUMERIC;

ALTER TABLE inbox_latest_periodic_state
ADD PRIMARY KEY (market_id);

INSERT INTO inbox_latest_periodic_state (
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
    event_name = 'emojicoin_dot_fun::PeriodicState'
AND
    data -> 'periodic_state_metadata' ->> 'period' = '86400000000'
ORDER BY
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC,
    (data ->> 'transaction_version')::NUMERIC DESC,
    (data -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC DESC;

CREATE OR REPLACE FUNCTION UPDATE_LATEST_PERIODIC_STATE()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO inbox_latest_periodic_state (
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
    (inbox_latest_periodic_state.data -> 'market_metadata' ->> 'market_id')::NUMERIC = (EXCLUDED.data -> 'market_metadata' ->> 'market_id')::NUMERIC
  AND
    (inbox_latest_periodic_state.data -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC < (EXCLUDED.data -> 'periodic_state_metadata' ->> 'emit_market_nonce')::NUMERIC
  AND
    NEW.data -> 'periodic_state_metadata' ->> 'period' = '86400000000';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_latest_periodic_state
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.event_name = 'emojicoin_dot_fun::PeriodicState')
EXECUTE PROCEDURE UPDATE_LATEST_PERIODIC_STATE();

-- noqa: disable=ST06
CREATE OR REPLACE VIEW market_data AS
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
    DAILY_VOLUME(volume) AS daily_volume, -- noqa: RF02
    (periodic_state.data -> 'tvl_per_lp_coin_growth_q64')::NUMERIC / POW(2::NUMERIC,64::NUMERIC) AS tvl_per_lp_coin_growth_q64
FROM (
    SELECT data FROM inbox_events WHERE event_name = 'emojicoin_dot_fun::MarketRegistration'
) AS registration
LEFT JOIN inbox_latest_state AS state
    ON (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC = state.market_id
LEFT JOIN inbox_volume AS volume
    ON (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC = volume.market_id
LEFT JOIN inbox_latest_periodic_state AS periodic_state
    ON (registration.data -> 'market_metadata' ->> 'market_id')::NUMERIC = periodic_state.market_id;
-- noqa: disable=ST06

CREATE INDEX inbox_latest_periodic_state_by_tvl ON inbox_events (
    ((data ->> 'tvl_per_lp_coin_growth_q64')::NUMERIC / POW(2::NUMERIC,64::NUMERIC)) DESC
) WHERE (data ->> 'ends_in_bonding_curve')::BOOLEAN = true;

-- }}}
