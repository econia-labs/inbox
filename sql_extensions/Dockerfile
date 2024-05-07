FROM alpine:latest

RUN apk add postgresql-client bash

COPY sql_extensions/ .

CMD ["bash", "./apply-sql-extensions.sh"]
