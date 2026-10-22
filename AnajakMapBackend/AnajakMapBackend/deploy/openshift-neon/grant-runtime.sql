-- Run AFTER Flyway as the schema owner. psql -v schema=identity -v runtime_role=identity_app
-- Owner/runtime roles must already exist with independently managed credentials.
GRANT USAGE ON SCHEMA :"schema" TO :"runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA :"schema" TO :"runtime_role";
REVOKE ALL ON TABLE :"schema".flyway_schema_history FROM :"runtime_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA :"schema" TO :"runtime_role";
-- Re-run after each migration to cover new tables without granting access to DDL.
