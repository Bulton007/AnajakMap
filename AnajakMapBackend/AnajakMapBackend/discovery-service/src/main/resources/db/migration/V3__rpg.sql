CREATE TABLE rpg_players (
  scope_id VARCHAR2(160) PRIMARY KEY, actor VARCHAR2(100) NOT NULL,
  realm VARCHAR2(12) NOT NULL CHECK(realm IN ('practice','field')),
  xp NUMBER(10) DEFAULT 0 NOT NULL CHECK(xp>=0), gold NUMBER(10) DEFAULT 0 NOT NULL CHECK(gold>=0),
  wins NUMBER(10) DEFAULT 0 NOT NULL, captures NUMBER(10) DEFAULT 0 NOT NULL,
  next_encounter TIMESTAMP DEFAULT TIMESTAMP '2000-01-01 00:00:00' NOT NULL,
  daily_date VARCHAR2(10) DEFAULT '2000-01-01' NOT NULL, daily_count NUMBER(5) DEFAULT 0 NOT NULL,
  UNIQUE(actor,realm)
);
CREATE TABLE rpg_destinations (
  id VARCHAR2(80) PRIMARY KEY, name VARCHAR2(200) NOT NULL,
  latitude NUMBER NOT NULL CHECK(latitude BETWEEN -90 AND 90),
  longitude NUMBER NOT NULL CHECK(longitude BETWEEN -180 AND 180),
  radius_m NUMBER(8) NOT NULL CHECK(radius_m BETWEEN 20 AND 500),
  habitat VARCHAR2(20) NOT NULL CHECK(habitat IN ('temple','beach')),
  approved NUMBER(1) DEFAULT 0 NOT NULL CHECK(approved IN (0,1)),
  accessible NUMBER(1) DEFAULT 0 NOT NULL CHECK(accessible IN (0,1)),
  min_level NUMBER(5) DEFAULT 1 NOT NULL CHECK(min_level>=1),
  cooldown_seconds NUMBER(8) DEFAULT 300 NOT NULL CHECK(cooldown_seconds>=60),
  daily_limit NUMBER(5) DEFAULT 10 NOT NULL CHECK(daily_limit BETWEEN 1 AND 100),
  source VARCHAR2(500) NOT NULL
);
CREATE TABLE rpg_monsters (
  id VARCHAR2(36) PRIMARY KEY, scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  species_id VARCHAR2(40) NOT NULL, xp NUMBER(10) DEFAULT 0 NOT NULL CHECK(xp>=0),
  variation NUMBER(2) NOT NULL CHECK(variation BETWEEN 0 AND 5),
  destination_id VARCHAR2(80), created_at TIMESTAMP DEFAULT SYS_EXTRACT_UTC(SYSTIMESTAMP) NOT NULL
);
CREATE INDEX rpg_monster_owner ON rpg_monsters(scope_id,created_at);
CREATE TABLE rpg_sessions (
  id VARCHAR2(36) PRIMARY KEY, scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  destination_id VARCHAR2(80) NOT NULL REFERENCES rpg_destinations(id),
  monster_id VARCHAR2(36) NOT NULL REFERENCES rpg_monsters(id),
  state CLOB NOT NULL CHECK(state IS JSON), revision NUMBER(10) DEFAULT 0 NOT NULL,
  status VARCHAR2(20) NOT NULL, expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT SYS_EXTRACT_UTC(SYSTIMESTAMP) NOT NULL
);
CREATE INDEX rpg_session_owner ON rpg_sessions(scope_id,status);
CREATE TABLE rpg_ledger (
  id VARCHAR2(36) PRIMARY KEY, scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  source_id VARCHAR2(100) NOT NULL, xp NUMBER(10) NOT NULL CHECK(xp>=0),
  gold NUMBER(10) NOT NULL CHECK(gold>=0), kind VARCHAR2(40) NOT NULL,
  created_at TIMESTAMP DEFAULT SYS_EXTRACT_UTC(SYSTIMESTAMP) NOT NULL,
  UNIQUE(scope_id,source_id)
);
CREATE INDEX rpg_ledger_owner ON rpg_ledger(scope_id,created_at);

CREATE OR REPLACE TRIGGER rpg_ledger_immutable BEFORE UPDATE OR DELETE ON rpg_ledger BEGIN RAISE_APPLICATION_ERROR(-20002, 'RPG ledger is append only'); END;
/

-- Matches discovery-service development fixtures. Not reviewed for field gameplay.
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('4b9f991fa8c7bb8f','Royal Palace',11.5638,104.9315,100,'temple','Discovery development fixture; safety review required');
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('c4453433397f42b8','National Museum',11.5658,104.9288,100,'temple','Discovery development fixture; safety review required');
INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,source) VALUES('6213f3be5bcef58e','Wat Phnom',11.5760,104.9231,100,'temple','Discovery development fixture; safety review required');
