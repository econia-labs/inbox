CREATE VIEW inbox_periodic_states AS
SELECT
    (data -> 'market_metadata' ->> 'market_id')::NUMERIC AS market_id,
    (data -> 'periodic_state_metadata' ->> 'period')::NUMERIC AS period,
    (data -> 'periodic_state_metadata' ->> 'start_time')::NUMERIC AS start_time,
    data
FROM inbox_events
WHERE event_name = 'emojicoin_dot_fun::PeriodicState';
