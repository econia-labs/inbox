#!/bin/bash

sleep 1

script_dir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")

if [ -d "$script_dir/migrations" ]; then
    for file in "$script_dir/00000_init.sql" $(ls -Q "$script_dir/migrations/*.sql");do
        if [ "$(psql $DATABASE_URL --csv -t -c "SELECT COUNT(*) FROM sql_extensions WHERE name = '($(basename $file))'" 2>/dev/null)" != "1" ];then
            psql $DATABASE_URL --single-transaction -f "$file" -c "INSERT INTO sql_extensions VALUES ('$(basename $file)');"
        fi
    done
fi
