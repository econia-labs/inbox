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

> :warning: THIS PROJECT IS NOT ACTIVELY MAINTAINED :warning:

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

### 8. Issue a TLS certificate (optional)

Note that for local development where `inbox` is running through Docker compose,
browsers like Chrome should be able to connect to the `mqtt` endpoint over an
unsecured `ws` localhost connection. However, when connecting to an endpoint
from a production `mqtt` server, the connection will need to be over a secure
`wss` connection.

Hence for a production Terraform deployment, you'll need to issue a TLS
certificate to the `mqtt` instance:

1. Get the public IP of the `mqtt` VM:

   ```sh
   gcloud compute instances list
   ```

1. Create a new custom DNS record for your preferred domain:

   | Host | Type | Priority | Data                 |
   | ---- | ---- | -------- | -------------------- |
   | `@`  | `A`  | N/A      | `<MQTT_EXTERNAL_IP>` |

1. Verify the domain has resolved to the IP address (there may be a delay):

   ```sh
   npx wscat -c ws://<YOUR_DOMAIN>:21884
   ```

1. Get your IP address:

   ```sh
   MY_IP=$(curl --silent http://checkip.amazonaws.com)
   ```

1. Create a temporary firewall rule that will allow you to SSH into the `mqtt`
   VM:

   ```sh
   gcloud compute firewall-rules create set-cert \
       --allow tcp:22 \
       --direction INGRESS \
       --network sql-network \
       --priority 0 \
       --source-ranges $MY_IP/32
   ```

1. Create a temporary firewall rule that will allow `certbot` to connect:

   ```sh
   gcloud compute firewall-rules create certbot \
       --allow tcp:80 \
       --direction INGRESS \
       --network sql-network \
       --priority 0 \
       --source-ranges 0.0.0.0/0
   ```

1. Optionally verify you can connect via

   ```sh
   curl -I http://<YOUR_DOMAIN>:80
   ```

1. SSH into the `mqtt` VM:

   ```sh
   gcloud compute ssh mqtt
   ```

1. Run:

   ```sh
   docker ps
   ```

1. Enter the container with an interactive `sh` session:

   ```sh
   docker exec -it <CONTAINER_ID> sh
   ```

1. Activate superuser:

   ```sh
   su
   ```

1. Install packages:

   ```sh
   apt update
   apt install certbot vim
   ```

1. Try a dry run:

   ```sh
   certbot certonly --standalone --dry-run
   ```

1. If if succeeds:

   ```sh
   certbot certonly --standalone
   ```

1. Copy files:

   ```sh
   cp /etc/letsencrypt/live/<YOUR_DOMAIN>/chain.pem /cafile
   cp /etc/letsencrypt/live/<YOUR_DOMAIN>/cert.pem /certfile
   cp /etc/letsencrypt/live/<YOUR_DOMAIN>/privkey.pem /keyfile
   ```

1. Vim into the `mosquitto` config file:

   ```sh
   vim /mosquitto/config/mosquitto.conf
   ```

1. Under the `listener 21884` block, add TLS file lookup options and
   `required false` so that your config looks like:

   ```sh
   per_listener_settings true

   listener 21883
   protocol mqtt
   allow_anonymous true
   password_file /password_file
   acl_file /acl_file

   listener 21884
   protocol websockets
   allow_anonymous true
   password_file /password_file
   acl_file /acl_file
   # New contents below
   certfile /certfile
   cafile /cafile
   keyfile /keyfile
   require_certificate false
   ```

1. Update file privileges:

   ```sh
   chmod 755 certfile
   chmod 755 cafile
   chmod 755 keyfile
   chown mosquitto:mosquitto certfile
   chown mosquitto:mosquitto cafile
   chown mosquitto:mosquitto keyfile
   ```

1. Exit the `su` prompt, then the container via `exit`.

1. Get the container via `docker ps`.

1. Restart the container via `docker restart <CONTAINER_ID>`.

1. Run `docker ps` several times to verify the container is up and running.

1. `exit` out of the VM.

1. Verify you can connect to `wss`:

   ```sh
   npx wscat -c wss://<YOUR_DOMAIN>:21884
   ```

1. Delete the temporary firewall rules:

   ```sh
   gcloud compute firewall-rules delete set-cert
   gcloud compute firewall-rules delete certbot
   ```

1. Pro tip: if you perform a step incorrectly, you can always start with a fresh
   `mqtt` instance:

   ```sh
   terraform destroy -target module.mqtt -var-file variables.tfvars
   ```

   ```sh
   terraform apply -target module.mqtt -var-file variables.tfvars
   ```

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
