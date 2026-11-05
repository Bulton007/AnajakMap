-- Personal GPS journeys do not mark public destinations as reviewed.
BEGIN
  FOR c IN (SELECT constraint_name FROM user_constraints
    WHERE table_name='RPG_DESTINATIONS' AND constraint_type='C'
      AND UPPER(search_condition_vc) LIKE '%HABITAT%IN%') LOOP
    EXECUTE IMMEDIATE 'ALTER TABLE rpg_destinations DROP CONSTRAINT ' || c.constraint_name;
  END LOOP;
END;
/
ALTER TABLE rpg_destinations ADD CONSTRAINT rpg_habitat CHECK(habitat IN ('temple','beach','roaming'));
CREATE TABLE rpg_journeys (
  id VARCHAR2(36) PRIMARY KEY,
  scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  started_at TIMESTAMP NOT NULL, ended_at TIMESTAMP,
  distance_m NUMBER DEFAULT 0 NOT NULL CHECK(distance_m>=0)
);
CREATE INDEX rpg_journey_owner ON rpg_journeys(scope_id,started_at);
CREATE TABLE rpg_journey_points (
  journey_id VARCHAR2(36) NOT NULL REFERENCES rpg_journeys(id),
  sequence_no NUMBER(6) NOT NULL,
  latitude NUMBER NOT NULL CHECK(latitude BETWEEN -90 AND 90),
  longitude NUMBER NOT NULL CHECK(longitude BETWEEN -180 AND 180),
  accuracy NUMBER NOT NULL CHECK(accuracy>0 AND accuracy<=50),
  measured_at TIMESTAMP NOT NULL,
  PRIMARY KEY(journey_id,sequence_no)
);
CREATE TABLE rpg_journey_visits (
  destination_id VARCHAR2(80) PRIMARY KEY REFERENCES rpg_destinations(id),
  scope_id VARCHAR2(160) NOT NULL REFERENCES rpg_players(scope_id),
  journey_id VARCHAR2(36) NOT NULL REFERENCES rpg_journeys(id),
  visited_at TIMESTAMP NOT NULL
);
CREATE INDEX rpg_visit_owner ON rpg_journey_visits(scope_id,visited_at);
