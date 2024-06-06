CREATE OR REPLACE FUNCTION notify_periodic_event()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'inbox_event',
    (SELECT jsonb_build_object('topic', (NEW.type || '/' || (((NEW.data::jsonb)->('market_metadata'::text))::jsonb->>('market_id'::text)) || '/' || ((NEW.data::jsonb->('periodic_state_metadata'::text))::jsonb->>('period'::text))), 'payload', to_jsonb(NEW))::text));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_periodic_event
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.data ? 'market_metadata' AND new.data ? 'periodic_state_metadata')
EXECUTE PROCEDURE notify_periodic_event();

CREATE OR REPLACE FUNCTION notify_metadata_event()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'inbox_event',
    (SELECT jsonb_build_object('topic', (NEW.type || '/' || (((NEW.data::jsonb)->('market_metadata'::text))::jsonb->>('market_id'::text))), 'payload', to_jsonb(NEW))::text));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_metadata_event
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.data ? 'market_metadata' AND NOT new.data ? 'periodic_state_metadata')
EXECUTE PROCEDURE notify_metadata_event();

CREATE OR REPLACE FUNCTION notify_flat_event()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'inbox_event',
    (SELECT jsonb_build_object('topic', (NEW.type || '/' || ((NEW.data::jsonb)->>('market_id'::text))), 'payload', to_jsonb(NEW))::text));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_flat_event
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.data ? 'market_id' AND NOT new.data ? 'results_in_state_transition')
EXECUTE PROCEDURE notify_flat_event();

CREATE OR REPLACE FUNCTION notify_swap_event()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'inbox_event',
    (SELECT jsonb_build_object('topic', (NEW.type || '/' || ((NEW.data::jsonb)->>('market_id'::text)) || '/' || ((NEW.data::jsonb)->>('results_in_state_transition'::text))), 'payload', to_jsonb(NEW))::text));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_swap_event
AFTER INSERT ON inbox_events
FOR EACH ROW
WHEN (new.data ? 'market_id' AND new.data ? 'results_in_state_transition')
EXECUTE PROCEDURE notify_swap_event();
