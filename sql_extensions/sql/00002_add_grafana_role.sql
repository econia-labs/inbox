-- noqa: disable=PRS
CREATE ROLE grafana ENCRYPTED PASSWORD 'grafana' LOGIN;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;
