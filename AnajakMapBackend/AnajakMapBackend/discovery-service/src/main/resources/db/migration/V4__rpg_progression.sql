ALTER TABLE rpg_monsters ADD (evolution NUMBER(1) DEFAULT 0 NOT NULL CHECK(evolution BETWEEN 0 AND 2));
ALTER TABLE rpg_players ADD (equipped_title VARCHAR2(40) DEFAULT 'traveler' NOT NULL);
ALTER TABLE rpg_destinations ADD (
  recommended_level NUMBER(3) DEFAULT 1 NOT NULL,
  enemy_level_min NUMBER(3) DEFAULT 1 NOT NULL CHECK(enemy_level_min BETWEEN 1 AND 50),
  enemy_level_max NUMBER(3) DEFAULT 3 NOT NULL CHECK(enemy_level_max BETWEEN 1 AND 50),
  boss_level NUMBER(3) DEFAULT 5 NOT NULL CHECK(boss_level BETWEEN 1 AND 50),
  boss_unlock_wins NUMBER(3) DEFAULT 3 NOT NULL CHECK(boss_unlock_wins>=1),
  CHECK(enemy_level_max>=enemy_level_min)
);
ALTER TABLE rpg_sessions ADD (kind VARCHAR2(12) DEFAULT 'wild' NOT NULL CHECK(kind IN ('wild','boss')));
ALTER TABLE rpg_sessions ADD (completed_at TIMESTAMP);
CREATE TABLE rpg_inventory (
  scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  item VARCHAR2(20) NOT NULL CHECK(item IN ('potion','crystal')),
  quantity NUMBER(8) DEFAULT 0 NOT NULL CHECK(quantity BETWEEN 0 AND 9999),
  PRIMARY KEY(scope_id,item)
);
INSERT INTO rpg_inventory SELECT scope_id,'potion',5 FROM rpg_players;
INSERT INTO rpg_inventory SELECT scope_id,'crystal',8 FROM rpg_players;
CREATE TABLE rpg_transactions (
  id VARCHAR2(36) PRIMARY KEY, scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  source_id VARCHAR2(128) NOT NULL, asset VARCHAR2(20) NOT NULL CHECK(asset IN ('gold','potion','crystal')),
  delta NUMBER(10) NOT NULL, created_at TIMESTAMP DEFAULT SYS_EXTRACT_UTC(SYSTIMESTAMP) NOT NULL,
  UNIQUE(scope_id,source_id,asset)
);
CREATE INDEX rpg_transaction_owner ON rpg_transactions(scope_id,created_at);
CREATE OR REPLACE TRIGGER rpg_transaction_immutable BEFORE UPDATE OR DELETE ON rpg_transactions BEGIN RAISE_APPLICATION_ERROR(-20003, 'RPG transactions are append only'); END;
/
CREATE TABLE rpg_party (
  scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  slot NUMBER(1) NOT NULL CHECK(slot BETWEEN 1 AND 3),
  monster_id VARCHAR2(36) NOT NULL REFERENCES rpg_monsters(id),
  PRIMARY KEY(scope_id,slot), UNIQUE(scope_id,monster_id)
);
INSERT INTO rpg_party(scope_id,slot,monster_id)
 SELECT scope_id,1,id FROM (SELECT scope_id,id,ROW_NUMBER() OVER(PARTITION BY scope_id ORDER BY created_at,id) AS rn FROM rpg_monsters) WHERE rn=1;
CREATE TABLE rpg_combatants (
  session_id VARCHAR2(36) NOT NULL REFERENCES rpg_sessions(id),
  monster_id VARCHAR2(36) NOT NULL REFERENCES rpg_monsters(id),
  state CLOB NOT NULL CHECK(state IS JSON), PRIMARY KEY(session_id,monster_id)
);
INSERT INTO rpg_combatants(session_id,monster_id,state) SELECT id,monster_id,JSON_QUERY(state,'$.ally' RETURNING CLOB) FROM rpg_sessions WHERE status='active';
CREATE TABLE rpg_spawn_rules (
  destination_id VARCHAR2(80) NOT NULL REFERENCES rpg_destinations(id),
  species_id VARCHAR2(40) NOT NULL,
  weight NUMBER(5) NOT NULL CHECK(weight BETWEEN 1 AND 10000),
  PRIMARY KEY(destination_id,species_id)
);
INSERT INTO rpg_spawn_rules SELECT id,'mossling',60 FROM rpg_destinations WHERE habitat='temple';
INSERT INTO rpg_spawn_rules SELECT id,'amberhorn',30 FROM rpg_destinations WHERE habitat='temple';
INSERT INTO rpg_spawn_rules SELECT id,'moonwarden',10 FROM rpg_destinations WHERE habitat='temple';
-- Existing fixture destinations stay unapproved. No public coordinates are invented.
UPDATE rpg_destinations SET min_level=2,recommended_level=2,enemy_level_min=2,enemy_level_max=4 WHERE id='c4453433397f42b8';
UPDATE rpg_destinations SET min_level=3,recommended_level=3,enemy_level_min=3,enemy_level_max=5 WHERE id='6213f3be5bcef58e';
