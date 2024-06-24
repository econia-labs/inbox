CREATE INDEX inbox_events_transaction_version_event_name
ON inbox_events (
  transaction_version DESC,
  event_name
);

CREATE INDEX inbox_events_chat
ON inbox_events (
  transaction_version DESC, 
  (data->'market_metadata'->>'market_id')
)
WHERE event_name = 'emojicoin_dot_fun::Chat';

CREATE INDEX inbox_events_swap
ON inbox_events (
  transaction_version DESC
)
WHERE event_name = 'emojicoin_dot_fun::Swap'
AND data->>'results_in_state_transition' = 'true';
