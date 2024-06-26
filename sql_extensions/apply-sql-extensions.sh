#!/bin/bash

set -e

sleep 1

script_dir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

if [ -d "$script_dir/migrations" ]; then
    for file in $(ls "$script_dir"/sql/*.sql) $(ls "$script_dir"/migrations/*.sql);do
        if [ "$(psql $DATABASE_URL --csv -t -c "SELECT COUNT(*) FROM sql_extensions WHERE name = '$(basename $file)'" 2>/dev/null)" != "1" ];then
            echo "Applying $(basename $file)."
            psql $DATABASE_URL --single-transaction -f "$file" -c "INSERT INTO sql_extensions VALUES ('$(basename $file)');"
        else
            echo "$(basename $file) already applied, skipping..."
        fi
    done
fi

echo "Migrations successfully applied."
