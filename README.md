<!---
cspell:word cafile
cspell:word certbot
cspell:word certfile
cspell:word certonly
cspell:word letsencrypt
cspell:word privkey
cspell:word wscat
-->

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

You can get SSE events by querying the publisher.

See Rust comment doc for SSE details:

```rust
/// Handles a request to `/sse`.
///
/// Takes subscription data as query parameters.
///
/// If a field is left empty, you will be subscribed to all.
///
/// Example of connection paths:
///
/// - `/sse?markets=1&event_types=Chat`: subscribe to chat events on market 1
/// - `/sse?markets=1`: subscribe to all events on market 1
/// - `/sse?event_types=State`: subscribe to all State events
/// - `/sse`: subscribe to all events
/// - `/sse?markets=1&markets=2&event_types=Chat&event_types=Swap`: subscribe to Chat and Swap events on markets 1 and 2
```

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

1. Define a project ID and name:

   ```sh
   PROJECT_ID=<YOUR_PROJECT_ID>
   PROJECT_NAME=<YOUR_PROJECT_NAME>
   ```

   ```sh
   echo $PROJECT_ID
   echo $PROJECT_NAME
   ```

1. Get your organization ID:

   ```sh
   ORGANIZATION_ID=$(gcloud organizations list --format="value(ID)")
   echo $ORGANIZATION_ID
   ```

1. Get your billing account ID:

   ```sh
   BILLING_ACCOUNT_ID=$(
      gcloud billing accounts list --format="value(ACCOUNT_ID)"
   )
   echo $BILLING_ACCOUNT_ID
   ```

1. Create project:

   ```sh
   gcloud projects create $PROJECT_ID \
       --name $PROJECT_NAME \
       --organization $ORGANIZATION_ID
   ```

1. Link billing account to the project:

   ```sh
   gcloud billing projects link $PROJECT_ID \
       --billing-account $BILLING_ACCOUNT_ID
   ```

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

### 6. Running new migrations (optional)

To run new migrations, run:

```
export DB_CONNECTION_NAME="$(terraform -chdir=terraform output -raw db_connection_name)"
export CREDENTIALS_FILE=terraform/creds.json
export DATABASE_URL="$(terraform -chdir=terraform output -raw db_conn_str_auth_proxy)"
bash terraform/modules/migrations/run-migrations.sh
```

Already ran migrations will not be ran again.

### 7. Enable unauthenticated PostgREST invocations (optional)

If you are using a branch that by default requires authentication for PostgREST,
like the `emojicoin-dot-fun` branch, you'll need to select
`Allow unauthenticated invocations` under `Cloud Run > postgrest > security`.

Note that GCP issues ephemeral IP addresses for VMs, which means they only
persist for the lifetime of the resource. So if you need to start over then the
corresponding public IP address will probably change.

### Troubleshooting

The init script runs `gcloud` commands. If it fails, please check the error
messages and GCP documentation.

The deploy step runs `terraform`. If it fails, please check the error messages
and terraform documentation.

Also, you might want to try deploying on a fresh project if deployment fails.

## Example

If you want to take a look at what is possible to do with Inbox, take a look at
the `emojicoin-dot-fun` branch. It shows what an advanced usage of Inbox looks
like. The `emojicoin-dot-fun` branch contains sql extensions specially designed
for the emojico.in website.

[emojicoin dot fun]: https://github.com/econia-labs/emojicoin-dot-fun
