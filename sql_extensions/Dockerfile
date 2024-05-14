FROM alpine:20240329

RUN apk --no-cache add postgresql16-client=16.2-r4 bash=5.2.26-r0

WORKDIR /

COPY sql_extensions/ .

CMD ["bash", "./apply-sql-extensions.sh"]
