CREATE TABLE sql_extensions(
    name TEXT PRIMARY KEY
);

CREATE USER web_anon NOLOGIN;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO web_anon;
GRANT USAGE ON SCHEMA public to web_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public to web_anon;