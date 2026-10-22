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

-- From V2__guide.sql
CREATE TABLE generation_jobs(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,trip_id VARCHAR(36) NOT NULL,status VARCHAR(20) NOT NULL CHECK(status IN ('QUEUED','RUNNING','SUCCEEDED','FAILED')),input_json TEXT NOT NULL,output_json TEXT,error_code VARCHAR(80),created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE INDEX jobs_status ON generation_jobs(status,created_at);
CREATE TABLE conversations(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE TABLE guide_messages(id VARCHAR(36) PRIMARY KEY,conversation_id VARCHAR(36) NOT NULL REFERENCES conversations(id),role VARCHAR(20) NOT NULL,content TEXT NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE INDEX messages_conversation ON guide_messages(conversation_id,created_at);
CREATE TABLE saved_phrases(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,content TEXT NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);

-- From V3__media.sql
CREATE TABLE guide_media(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,object_key VARCHAR(100) NOT NULL,mime_type VARCHAR(100) NOT NULL,size_bytes BIGINT NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
CREATE INDEX guide_media_owner ON guide_media(owner_id);

-- From V4__job_retries.sql
ALTER TABLE generation_jobs ADD COLUMN trace_id VARCHAR(64), ADD COLUMN attempts INTEGER DEFAULT 0 NOT NULL, ADD COLUMN next_attempt TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL;
