ALTER TABLE inbox_events
ADD COLUMN event_name TEXT GENERATED ALWAYS AS (regexp_replace(indexed_type, '^[^:]*::', '')) STORED;

CREATE INDEX inbox_events_event_name ON inbox_events (event_name);
