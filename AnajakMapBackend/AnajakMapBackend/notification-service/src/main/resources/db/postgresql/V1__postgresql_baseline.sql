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

-- From V2__notification.sql
CREATE TABLE devices(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,token VARCHAR(2000) NOT NULL,platform VARCHAR(10) NOT NULL CHECK(platform IN ('ANDROID','IOS')),created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE INDEX device_owner ON devices(owner_id);
CREATE TABLE deliveries(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,title VARCHAR(200) NOT NULL,due_at TIMESTAMP WITH TIME ZONE NOT NULL,status VARCHAR(20) NOT NULL,attempts INTEGER DEFAULT 0 NOT NULL,next_attempt TIMESTAMP WITH TIME ZONE NOT NULL,delivered_at TIMESTAMP WITH TIME ZONE,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE INDEX delivery_due ON deliveries(status,next_attempt);

-- From V3__delivery_lease.sql
ALTER TABLE deliveries ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL;
