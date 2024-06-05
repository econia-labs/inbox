# Run migrations for the first time.
resource "terraform_data" "run_migrations" {
  depends_on = [var.main_database]
  provisioner "local-exec" {
    # Relative to DSS terraform project root.
    command = file("modules/migrations/run-migrations.sh")
    environment = {
      DATABASE_URL       = var.db_conn_str_auth_proxy,
      DB_CONNECTION_NAME = var.db_connection_name,
      CREDENTIALS_FILE   = var.credentials_file
    }
  }
}

# Re-run migrations after database initialization.
#
# Tracked as a separate resource so that followup migrations can be run
# by simply destroying and re-applying this resource. The destroy/re-apply
# approach doesn't work for the initial migrations resource since other
# resources depend on initial migrations and they would have to be deleted
# too if initial migrations were, hence this duplicate.
#
# Upon database creation, migrations will be run twice, but this is not a
# problem because diesel only runs new migrations upon subsequent calls to the
# same database.
resource "terraform_data" "re_run_migrations" {
  depends_on = [terraform_data.run_migrations]
  provisioner "local-exec" {
    command = file("modules/migrations/run-migrations.sh")
    environment = {
      DATABASE_URL       = var.db_conn_str_auth_proxy,
      DB_CONNECTION_NAME = var.db_connection_name,
      CREDENTIALS_FILE   = var.credentials_file
    }
  }
}
