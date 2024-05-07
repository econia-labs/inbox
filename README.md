# Inbox - The simplest Aptos backend

Inbox is a simple backend server that automatically creates a REST API for your
contract using your events.

## Dependencies

The only dependency you need is Docker.

## Setting up

### Step 0: Cloning

First, clone this project: `git clone https://github.com/econia-labs/inbox`.

Then, clone git submodules: `git submodule update --init --recursive`.

### Step 1: Configuration

Copy `example.env` to `.env` and update the required fields. Field
documentation can be found in the file.

### Step 2: Run

Simply start Inbox by running `docker compose -p inbox -f compose.yaml up -d`.

## Using

### Querying

All events are available at `/events`.

The event data is in the `data` field.

The REST API is generated using PostgREST. Visit the [PostgREST
documentation](https://postgrest.org/) for more information about querying.

### Managing

To temporally stop Inbox, run  `docker compose -p inbox -f compose.yaml stop`.

To resume Inbox, run  `docker compose -p inbox -f compose.yaml start`.

To reset Inbox state, run `docker compose -p inbox -f compose.yaml down && docker volume rm inbox_db`

## SQL extensions

If you have many events, you might need indices. To create some, add an `sql`
file in `sql_extensions/migrations`. Here is an example:

```sql
CREATE INDEX example_index ON events (((data->'column')::text));
```

You can also add view and functions to extend your API.
