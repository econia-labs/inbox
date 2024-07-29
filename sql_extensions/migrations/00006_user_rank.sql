CREATE TABLE inbox_user_balance (
    user_address TEXT NOT NULL,
    market_id NUMERIC,
    balance_as_fraction_of_circulating_supply NUMERIC,
    PRIMARY KEY (user_address, market_id)
);

INSERT INTO inbox_user_balance
SELECT DISTINCT ON (data ->> 'user', data -> 'market_metadata' ->> 'market_id')
    data ->> 'user',
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC,
    (data ->> 'balance_as_fraction_of_circulating_supply_q64')::NUMERIC / POW(2::NUMERIC, 64::NUMERIC)
FROM
    inbox_events
WHERE
    event_name = 'emojicoin_dot_fun::Chat'
ORDER BY
    data ->> 'user',
    data -> 'market_metadata' ->> 'market_id',
    transaction_version DESC,
    event_index DESC;

CREATE OR REPLACE FUNCTION UPDATE_USER_BALANCE()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO inbox_user_balance
    SELECT
        NEW.data ->> 'user',
        (NEW.data -> 'market_metadata' ->> 'market_id')::NUMERIC,
        (NEW.data ->> 'balance_as_fraction_of_circulating_supply_q64')::NUMERIC / POW(2::NUMERIC, 64::NUMERIC)
    ON CONFLICT (user_address, market_id) DO UPDATE SET
        balance_as_fraction_of_circulating_supply = (NEW.data ->> 'balance_as_fraction_of_circulating_supply_q64')::NUMERIC / POW(2::NUMERIC, 64::NUMERIC);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_balance
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.event_name = 'emojicoin_dot_fun::Chat')
EXECUTE PROCEDURE UPDATE_USER_BALANCE();

CREATE OR REPLACE VIEW inbox_swaps AS
SELECT
    swaps.sequence_number,
    swaps.creation_number,
    swaps.account_address,
    swaps.transaction_version,
    swaps.transaction_block_height,
    swaps."type",
    swaps."data",
    swaps.inserted_at,
    swaps.event_index,
    swaps.indexed_type,
    swaps.event_name,
    (swaps."data"->>'market_id')::NUMERIC AS market_id,
    inbox_user_balance.balance_as_fraction_of_circulating_supply
FROM inbox_events AS swaps
LEFT JOIN inbox_user_balance ON swaps.data ->> 'swapper' = inbox_user_balance.user_address AND (swaps."data" ->> 'market_id')::NUMERIC = inbox_user_balance.market_id
WHERE swaps.event_name = 'emojicoin_dot_fun::Swap';
