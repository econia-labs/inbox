FROM alpine:3.19.1

RUN apk --no-cache add postgresql16-client=16.3-r0 bash=5.2.21-r0

WORKDIR /

COPY sql_extensions/apply-sql-extensions.sh .

CMD ["bash", "./apply-sql-extensions.sh"]
