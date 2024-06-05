# Run Cloud SQL Auth Proxy in background, run migrations, kill proxy.
cloud-sql-proxy $DB_CONNECTION_NAME --credentials-file $CREDENTIALS_FILE &
ls
sleep 5 # Give proxy time to start up.
echo "Running..."
bash ../sql_extensions/apply-sql-extensions.sh
psql "$DATABASE_URL" -c 'GRANT web_anon TO postgres'
# https://unix.stackexchange.com/a/104825
kill $(pgrep cloud-sql-proxy)
