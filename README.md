# Inbox - The simplest Aptos backend

Inbox is a simple backend server that automatically creates a REST API for your
contract using your events.

Please use the `stable` branch, or a specific git tag. `main` is used for
development and may be unstable.

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

To run migrations, run `docker compose -p inbox -f compose.yaml restart sql_extensions`.

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

You must also make sure that the SQL user `web_anon` has READ access (and *READ
ONLY*) to this table.

### Events

You can also use SQL extensions to create events that will then appear in MQTT.
To do so, follow this example:

```sql
CREATE OR REPLACE FUNCTION notify_event()
  RETURNS trigger AS $$
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

This will emit an MQTT event with the topic as your event type for all your
contract's events.

## Terraform

You can deploy this repo on GCP using Terraform.

### 1. Install dependencies

First, make sure you have installed the required dependencies:

- `gcloud` (Google Cloud CLI tool)
- `jq` (JSON parsing CLI tool)
- `cloud-sql-proxy` (Google Cloud tool to connect to a database)

Also make sure to run `gcloud auth login` if this is your first time using the
tool.

### 2. Create GCP Project

To deploy your project on GCP, you first need to create a GCP project.

### 3. Run init script

Once done, run `PROJECT_ID=<YOUR_PROJECT_ID> terraform/init.sh` to enable the
required Google APIs, create a service account, and download the credentials
file.

### 4. Create variables file

You might want to create a `terraform/variables.tfvars` file with the project
variables, to avoid typing them out every time.
`terraform/variables.tfvars.template` contains an example of such a file. Copy
it to `terraform/variables.tfvars`.

### 5. Deploying

Then, simply run `terraform -chdir=terraform init` and `terraform -chdir=terraform apply -var-file variables.tfvars`.

**Make sure your port 5432 is not used. It is needed during the deployment process.**

This will take quite a long time. Once finished, meaningful data will be shown
like the generated URLs and IP addresses for your services. You can always get
them later using the `terraform output` command.

### Running new migrations

To run new migrations, run:

```
export DB_CONNECTION_NAME="$(terraform -chdir=terraform output -raw db_connection_name)"
export CREDENTIALS_FILE=terraform/creds.json
export DATABASE_URL="$(terraform -chdir=terraform output -raw db_conn_str_auth_proxy)"
bash terraform/modules/migrations/run-migrations.sh
```

Already ran migrations will not be ran again.

### Troubleshooting

The init script runs `gcloud` commands. If it fails, please check the error
messages and GCP documentation.

The deploy step runs `terraform`. If it fails, please check the error messages
and terraform documentation.

Also, you might want to try deploying on a fresh project if deployment fails.

[emojicoin dot fun]: https://github.com/econia-labs/emojicoin-dot-fun
