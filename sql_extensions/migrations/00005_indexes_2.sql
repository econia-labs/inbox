CREATE INDEX inbox_events_swap_2
ON inbox_events (
    (data ->> 'market_id'),
    transaction_version DESC
)
WHERE event_name = 'emojicoin_dot_fun::Swap';
