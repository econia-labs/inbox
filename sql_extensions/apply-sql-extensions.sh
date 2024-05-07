#!/bin/bash

for file in $(ls migrations/*.sql);do
    if [ "$(psql $DATABASE_URL --csv -t -c "SELECT COUNT(*) FROM sql_extensions WHERE name = '$file'" 2>/dev/null)" != "1" ];then
        psql $DATABASE_URL -c "\i $file"
        psql $DATABASE_URL -c "INSERT INTO sql_extensions VALUES ('$file')"
    fi
done
