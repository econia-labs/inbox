#!/bin/bash

sleep 1

if [ -d "migrations" ]; then
    for file in 00000_init.sql $(ls migrations/*.sql);do
        if [ "$(psql $DATABASE_URL --csv -t -c "SELECT COUNT(*) FROM sql_extensions WHERE name = '$file'" 2>/dev/null)" != "1" ];then
            psql $DATABASE_URL --single-transaction -f "$file" -c "INSERT INTO sql_extensions VALUES ('$file');"
        fi
    done
fi
