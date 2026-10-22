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

-- From V2__journeys.sql
CREATE TABLE journey_legs(id VARCHAR(36) PRIMARY KEY,trip_id VARCHAR(36) NOT NULL,origin VARCHAR(200) NOT NULL,destination VARCHAR(200) NOT NULL,departure TIMESTAMP WITH TIME ZONE NOT NULL,arrival TIMESTAMP WITH TIME ZONE NOT NULL,timezone VARCHAR(80) NOT NULL,transfer_details VARCHAR(1000) NOT NULL,source VARCHAR(500) NOT NULL,created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,version BIGINT DEFAULT 0 NOT NULL,CHECK(arrival>departure));
CREATE INDEX journey_trip ON journey_legs(trip_id,departure);

-- From V3__rpg.sql
CREATE TABLE rpg_players (
  scope_id VARCHAR(160) PRIMARY KEY, actor VARCHAR(100) NOT NULL,
  realm VARCHAR(12) NOT NULL CHECK(realm IN ('practice','field')),
  xp BIGINT DEFAULT 0 NOT NULL CHECK(xp>=0), gold BIGINT DEFAULT 0 NOT NULL CHECK(gold>=0),
  wins BIGINT DEFAULT 0 NOT NULL, captures BIGINT DEFAULT 0 NOT NULL,
  next_encounter TIMESTAMP DEFAULT TIMESTAMP '2000-01-01 00:00:00' NOT NULL,
  daily_date VARCHAR(10) DEFAULT '2000-01-01' NOT NULL, daily_count INTEGER DEFAULT 0 NOT NULL,
  UNIQUE(actor,realm)
);
CREATE TABLE rpg_destinations (
  id VARCHAR(80) PRIMARY KEY, name VARCHAR(200) NOT NULL,
  latitude NUMERIC NOT NULL CHECK(latitude BETWEEN -90 AND 90),
  longitude NUMERIC NOT NULL CHECK(longitude BETWEEN -180 AND 180),
  radius_m INTEGER NOT NULL CHECK(radius_m BETWEEN 20 AND 500),
  habitat VARCHAR(20) NOT NULL CHECK(habitat IN ('temple','beach')),
  approved INTEGER DEFAULT 0 NOT NULL CHECK(approved IN (0,1)),
  accessible INTEGER DEFAULT 0 NOT NULL CHECK(accessible IN (0,1)),
  min_level INTEGER DEFAULT 1 NOT NULL CHECK(min_level>=1),
  cooldown_seconds INTEGER DEFAULT 300 NOT NULL CHECK(cooldown_seconds>=60),
  daily_limit INTEGER DEFAULT 10 NOT NULL CHECK(daily_limit BETWEEN 1 AND 100),
  source VARCHAR(500) NOT NULL
);
CREATE TABLE rpg_monsters (
  id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  species_id VARCHAR(40) NOT NULL, xp BIGINT DEFAULT 0 NOT NULL CHECK(xp>=0),
  variation INTEGER NOT NULL CHECK(variation BETWEEN 0 AND 5),
  destination_id VARCHAR(80), created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') NOT NULL
);
CREATE INDEX rpg_monster_owner ON rpg_monsters(scope_id,created_at);
CREATE TABLE rpg_sessions (
  id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  destination_id VARCHAR(80) NOT NULL REFERENCES rpg_destinations(id),
  monster_id VARCHAR(36) NOT NULL REFERENCES rpg_monsters(id),
  state TEXT NOT NULL CHECK(state IS JSON), revision BIGINT DEFAULT 0 NOT NULL,
  status VARCHAR(20) NOT NULL, expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') NOT NULL
);
CREATE INDEX rpg_session_owner ON rpg_sessions(scope_id,status);
CREATE TABLE rpg_ledger (
  id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  source_id VARCHAR(100) NOT NULL, xp BIGINT NOT NULL CHECK(xp>=0),
  gold BIGINT NOT NULL CHECK(gold>=0), kind VARCHAR(40) NOT NULL,
  created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') NOT NULL,
  UNIQUE(scope_id,source_id)
);
CREATE INDEX rpg_ledger_owner ON rpg_ledger(scope_id,created_at);

CREATE FUNCTION rpg_ledger_immutable_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'RPG ledger is append only'; END; $$;
CREATE TRIGGER rpg_ledger_immutable BEFORE UPDATE OR DELETE ON rpg_ledger FOR EACH STATEMENT EXECUTE FUNCTION rpg_ledger_immutable_fn();

-- Matches discovery-service development fixtures. Not reviewed for field gameplay.
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('4b9f991fa8c7bb8f','Royal Palace',11.5638,104.9315,100,'temple','Discovery development fixture; safety review required');
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('c4453433397f42b8','National Museum',11.5658,104.9288,100,'temple','Discovery development fixture; safety review required');
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('6213f3be5bcef58e','Wat Phnom',11.5760,104.9231,100,'temple','Discovery development fixture; safety review required');

-- From V4__rpg_progression.sql
ALTER TABLE rpg_monsters ADD COLUMN evolution INTEGER DEFAULT 0 NOT NULL CHECK(evolution BETWEEN 0 AND 2);
ALTER TABLE rpg_players ADD COLUMN equipped_title VARCHAR(40) DEFAULT 'traveler' NOT NULL;
ALTER TABLE rpg_destinations ADD COLUMN recommended_level INTEGER DEFAULT 1 NOT NULL, ADD COLUMN enemy_level_min INTEGER DEFAULT 1 NOT NULL CHECK(enemy_level_min BETWEEN 1 AND 50), ADD COLUMN enemy_level_max INTEGER DEFAULT 3 NOT NULL CHECK(enemy_level_max BETWEEN 1 AND 50), ADD COLUMN boss_level INTEGER DEFAULT 5 NOT NULL CHECK(boss_level BETWEEN 1 AND 50), ADD COLUMN boss_unlock_wins INTEGER DEFAULT 3 NOT NULL CHECK(boss_unlock_wins>=1), ADD CHECK(enemy_level_max>=enemy_level_min);
ALTER TABLE rpg_sessions ADD COLUMN kind VARCHAR(12) DEFAULT 'wild' NOT NULL CHECK(kind IN ('wild','boss'));
ALTER TABLE rpg_sessions ADD COLUMN completed_at TIMESTAMP;
CREATE TABLE rpg_inventory (
  scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  item VARCHAR(20) NOT NULL CHECK(item IN ('potion','crystal')),
  quantity INTEGER DEFAULT 0 NOT NULL CHECK(quantity BETWEEN 0 AND 9999),
  PRIMARY KEY(scope_id,item)
);
INSERT INTO rpg_inventory SELECT scope_id,'potion',5 FROM rpg_players;
INSERT INTO rpg_inventory SELECT scope_id,'crystal',8 FROM rpg_players;
CREATE TABLE rpg_transactions (
  id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  source_id VARCHAR(128) NOT NULL, asset VARCHAR(20) NOT NULL CHECK(asset IN ('gold','potion','crystal')),
  delta BIGINT NOT NULL, created_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') NOT NULL,
  UNIQUE(scope_id,source_id,asset)
);
CREATE INDEX rpg_transaction_owner ON rpg_transactions(scope_id,created_at);
CREATE FUNCTION rpg_transaction_immutable_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'RPG transactions are append only'; END; $$;
CREATE TRIGGER rpg_transaction_immutable BEFORE UPDATE OR DELETE ON rpg_transactions FOR EACH STATEMENT EXECUTE FUNCTION rpg_transaction_immutable_fn();
CREATE TABLE rpg_party (
  scope_id VARCHAR(160) NOT NULL REFERENCES rpg_players(scope_id),
  slot INTEGER NOT NULL CHECK(slot BETWEEN 1 AND 3),
  monster_id VARCHAR(36) NOT NULL REFERENCES rpg_monsters(id),
  PRIMARY KEY(scope_id,slot), UNIQUE(scope_id,monster_id)
);
INSERT INTO rpg_party(scope_id,slot,monster_id)
 SELECT scope_id,1,id FROM (SELECT scope_id,id,ROW_NUMBER() OVER(PARTITION BY scope_id ORDER BY created_at,id) AS rn FROM rpg_monsters) WHERE rn=1;
CREATE TABLE rpg_combatants (
  session_id VARCHAR(36) NOT NULL REFERENCES rpg_sessions(id),
  monster_id VARCHAR(36) NOT NULL REFERENCES rpg_monsters(id),
  state TEXT NOT NULL CHECK(state IS JSON), PRIMARY KEY(session_id,monster_id)
);
INSERT INTO rpg_combatants(session_id,monster_id,state) SELECT id,monster_id,(state::jsonb->'ally')::text FROM rpg_sessions WHERE status='active';
CREATE TABLE rpg_spawn_rules (
  destination_id VARCHAR(80) NOT NULL REFERENCES rpg_destinations(id),
  species_id VARCHAR(40) NOT NULL,
  weight INTEGER NOT NULL CHECK(weight BETWEEN 1 AND 10000),
  PRIMARY KEY(destination_id,species_id)
);
INSERT INTO rpg_spawn_rules SELECT id,'mossling',60 FROM rpg_destinations WHERE habitat='temple';
INSERT INTO rpg_spawn_rules SELECT id,'amberhorn',30 FROM rpg_destinations WHERE habitat='temple';
INSERT INTO rpg_spawn_rules SELECT id,'moonwarden',10 FROM rpg_destinations WHERE habitat='temple';
-- Existing fixture destinations stay unapproved. No public coordinates are invented.
UPDATE rpg_destinations SET min_level=2,recommended_level=2,enemy_level_min=2,enemy_level_max=4 WHERE id='c4453433397f42b8';
UPDATE rpg_destinations SET min_level=3,recommended_level=3,enemy_level_min=3,enemy_level_max=5 WHERE id='6213f3be5bcef58e';
