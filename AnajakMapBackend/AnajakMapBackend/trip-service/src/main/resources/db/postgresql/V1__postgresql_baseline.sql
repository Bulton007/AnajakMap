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

-- From V2__trip.sql
CREATE TABLE trips(id VARCHAR(36) PRIMARY KEY,owner_id VARCHAR(36) NOT NULL,title VARCHAR(200) NOT NULL,destination VARCHAR(200) NOT NULL,timezone VARCHAR(80) NOT NULL,start_date DATE NOT NULL,end_date DATE NOT NULL,created_at TIMESTAMP WITH TIME ZONE NOT NULL,version BIGINT DEFAULT 0 NOT NULL,CHECK(end_date>=start_date));
CREATE INDEX trips_owner ON trips(owner_id);
CREATE TABLE trip_members(trip_id VARCHAR(36) REFERENCES trips(id),account_id VARCHAR(36),role VARCHAR(10) NOT NULL CHECK(role IN ('EDITOR','VIEWER')),accepted INTEGER DEFAULT 0 NOT NULL,PRIMARY KEY(trip_id,account_id));
CREATE TABLE itinerary_versions(id VARCHAR(36) PRIMARY KEY,trip_id VARCHAR(36) NOT NULL REFERENCES trips(id),status VARCHAR(20) NOT NULL CHECK(status IN ('DRAFT','APPROVED','SUPERSEDED')),source VARCHAR(500) NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,version BIGINT DEFAULT 0 NOT NULL);
CREATE INDEX itinerary_trip ON itinerary_versions(trip_id,status);
CREATE TABLE activities(id VARCHAR(36) PRIMARY KEY,itinerary_id VARCHAR(36) NOT NULL REFERENCES itinerary_versions(id),sequence_no INTEGER NOT NULL,title VARCHAR(200) NOT NULL,starts_at TIMESTAMP WITH TIME ZONE NOT NULL,ends_at TIMESTAMP WITH TIME ZONE NOT NULL,latitude NUMERIC(10,7) NOT NULL CHECK(latitude BETWEEN -90 AND 90),longitude NUMERIC(10,7) NOT NULL CHECK(longitude BETWEEN -180 AND 180),source VARCHAR(500) NOT NULL,CHECK(ends_at>starts_at),UNIQUE(itinerary_id,sequence_no));
CREATE TABLE activity_votes(activity_id VARCHAR(36) REFERENCES activities(id),account_id VARCHAR(36),vote_value INTEGER NOT NULL CHECK(vote_value BETWEEN -1 AND 1),PRIMARY KEY(activity_id,account_id));
CREATE TABLE calendar_events(id VARCHAR(36) PRIMARY KEY,trip_id VARCHAR(36) NOT NULL REFERENCES trips(id),title VARCHAR(200) NOT NULL,starts_at TIMESTAMP WITH TIME ZONE NOT NULL,ends_at TIMESTAMP WITH TIME ZONE NOT NULL,timezone VARCHAR(80) NOT NULL,version BIGINT DEFAULT 0 NOT NULL,CHECK(ends_at>starts_at));
CREATE TABLE essential_contacts(id VARCHAR(36) PRIMARY KEY,trip_id VARCHAR(36) NOT NULL REFERENCES trips(id),label VARCHAR(100) NOT NULL,phone VARCHAR(50) NOT NULL);

-- From V3__replan_location.sql
CREATE TABLE shared_locations(trip_id VARCHAR(36) REFERENCES trips(id),account_id VARCHAR(36),latitude NUMERIC(10,7) NOT NULL,longitude NUMERIC(10,7) NOT NULL,expires_at TIMESTAMP WITH TIME ZONE NOT NULL,PRIMARY KEY(trip_id,account_id));
CREATE TABLE replanning_proposals(id VARCHAR(36) PRIMARY KEY,trip_id VARCHAR(36) NOT NULL REFERENCES trips(id),itinerary_id VARCHAR(36) NOT NULL REFERENCES itinerary_versions(id),reason VARCHAR(500) NOT NULL,base_version BIGINT NOT NULL,status VARCHAR(20) NOT NULL CHECK(status IN ('PROPOSED','APPLIED','REJECTED')),created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL);
