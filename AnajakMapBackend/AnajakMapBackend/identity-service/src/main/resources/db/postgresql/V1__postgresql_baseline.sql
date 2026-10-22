-- PostgreSQL 17 baseline for a NEW schema. Oracle data is not copied.
CREATE VIEW dual AS SELECT 'X'::varchar(1) AS dummy;
CREATE FUNCTION numtodsinterval(amount double precision, unit text)
RETURNS interval LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT CASE upper(unit) WHEN 'SECOND' THEN amount * interval '1 second' END
$$;
-- From V1__technical.sql
CREATE TABLE business_audit (id VARCHAR(36) PRIMARY KEY, actor VARCHAR(128) NOT NULL, action VARCHAR(80) NOT NULL, entity_id VARCHAR(128) NOT NULL, trace_id VARCHAR(64), fields TEXT, created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE FUNCTION audit_immutable_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Audit is append only'; END; $$;
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON business_audit FOR EACH STATEMENT EXECUTE FUNCTION audit_immutable_fn();
CREATE TABLE event_outbox (id VARCHAR(36) PRIMARY KEY, event_type VARCHAR(100) NOT NULL, payload TEXT NOT NULL, trace_id VARCHAR(64), created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL, published_at TIMESTAMP WITH TIME ZONE, attempts INTEGER DEFAULT 0 NOT NULL, next_attempt TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL, dead INTEGER DEFAULT 0 NOT NULL);
CREATE INDEX outbox_due ON event_outbox(dead, published_at, next_attempt);
CREATE TABLE event_inbox (id VARCHAR(36) PRIMARY KEY, received_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE TABLE idempotency_record (actor VARCHAR(128), request_key VARCHAR(128), operation VARCHAR(80), request_hash VARCHAR(64) NOT NULL, response TEXT NOT NULL, created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL, PRIMARY KEY(actor, request_key, operation));

-- From V2__identity.sql
CREATE TABLE accounts(id VARCHAR(36) PRIMARY KEY,email VARCHAR(254) NOT NULL UNIQUE,password_hash VARCHAR(100) NOT NULL,verified INTEGER DEFAULT 0 NOT NULL,preferences OID,created_at TIMESTAMP WITH TIME ZONE NOT NULL,version BIGINT DEFAULT 0 NOT NULL);
CREATE TABLE auth_codes(id VARCHAR(36) PRIMARY KEY,account_id VARCHAR(36) NOT NULL REFERENCES accounts(id),kind VARCHAR(10) NOT NULL CHECK(kind IN ('VERIFY','RESET')),code_hash VARCHAR(64) NOT NULL,expires_at TIMESTAMP WITH TIME ZONE NOT NULL,UNIQUE(account_id,kind));
CREATE TABLE refresh_tokens(token_hash VARCHAR(64) PRIMARY KEY,account_id VARCHAR(36) NOT NULL REFERENCES accounts(id),expires_at TIMESTAMP WITH TIME ZONE NOT NULL,revoked INTEGER DEFAULT 0 NOT NULL);
CREATE INDEX refresh_account ON refresh_tokens(account_id);
CREATE TABLE mail_delivery(id VARCHAR(36) PRIMARY KEY,recipient VARCHAR(254) NOT NULL,kind VARCHAR(10) NOT NULL,secret_value VARCHAR(128) NOT NULL,expires_at TIMESTAMP WITH TIME ZONE NOT NULL,attempts INTEGER DEFAULT 0 NOT NULL,sent INTEGER DEFAULT 0 NOT NULL);

-- From V3__registration_consent.sql
ALTER TABLE accounts ADD COLUMN display_name VARCHAR(120), ADD COLUMN legal_version VARCHAR(120), ADD COLUMN legal_accepted_at TIMESTAMP WITH TIME ZONE;
