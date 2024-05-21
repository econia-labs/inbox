# Inbox - The simplest Aptos backend

Inbox is a simple backend server that automatically creates a REST API for your
contract using your events.

## Dependencies

The only dependency you need is Docker.

## Setting up

### Step 0: Cloning

First, clone this project: `git clone https://github.com/econia-labs/inbox`.

Then, clone git submodules: `git submodule update --init --recursive`.

NOTE: If you are running this command from the [emojicoin dot fun] repository,
you need to specify that you only want to update `src/inbox` if you don't have
access to the private TradingView `charting_library` repository.

```shell
git submodule update --init --recursive src/inbox
```

### Step 1: Configuration

Copy `example.env` to `.env` and update the required fields. Field
documentation can be found in the file.

### Step 2: Run

Simply start Inbox by running `docker compose -p inbox -f compose.yaml up -d`.

## Using

### Querying

All events are available at `/inbox_events`.

The event data is in the `data` field.

The REST API is generated using PostgREST. Visit the [PostgREST
documentation](https://postgrest.org/) for more information about querying.

You can also query using PostgreSQL. The default database URL is
`postgres://inbox:inbox@postgres:5432/inbox`.

### Managing

To temporally stop Inbox, run  `docker compose -p inbox -f compose.yaml stop`.

To resume Inbox, run  `docker compose -p inbox -f compose.yaml start`.

To reset Inbox state, run `docker compose -p inbox -f compose.yaml down && docker volume rm inbox_db`

## SQL extensions

SQL extensions are stored under `sql_extensions/migrations/`.

The files must end with `.sql` and not be `00000_init.sql`.

### Indices

If you have many events, you might need indices. To create some, add an `sql`
file in `sql_extensions/migrations`. Here is an example:

```sql
CREATE INDEX example_index ON events (((data->'column')::text));
```

### Views/functions

You can also add view and functions to extend your API.

These will then be queryable through PostgREST. We highly encourage you to read
the [PostgREST documentation](https://postgrest.org/).

Here is a quick rundown of how to go about it:

```sql
CREATE VIEW nfts_minted_per_user AS
SELECT COUNT(*)
FROM inbox_events
WHERE "type" = '0x...::...::NftMinted'
GROUP BY data->>'user_address';
```

You must also make sure that the SQL user `web_anon` has READ access (and *READ ONLY*) to this table.

### Events

You can also use SQL extensions to create events that will then appear in MQTT. To do so, follow this example:

```sql
CREATE OR REPLACE FUNCTION notify_event()
  RETURNS trigger AS $$
DECLARE
BEGIN
  PERFORM pg_notify(
    'inbox_event',
    (SELECT jsonb_build_object('topic', NEW.type, 'payload', to_jsonb(NEW))::text));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_event
  AFTER INSERT ON inbox_events
  FOR EACH ROW
  EXECUTE PROCEDURE notify_event();
```

This will emit an MQTT event with the topic as your event type for all your contract's events.

## Terraform

You can deploy this repo on GCP using Terraform.

To do so, you first need to create a GCP project and get a credentials file stored at `terraform/creds.json`.

Then, simply run `terraform apply -var-file variables.tfvars`.

[emojicoin dot fun]: https://github.com/econia-labs/emojicoin-dot-fun
