-- Explicit character limits preserve Khmer and supplementary Unicode (emoji).
-- Widening byte semantics is additive; existing text and constraints are retained.
ALTER TABLE trips MODIFY (title VARCHAR2(200 CHAR), destination VARCHAR2(200 CHAR));
ALTER TABLE itinerary_versions MODIFY (source VARCHAR2(500 CHAR));
ALTER TABLE activities MODIFY (title VARCHAR2(200 CHAR), source VARCHAR2(500 CHAR));
ALTER TABLE calendar_events MODIFY (title VARCHAR2(200 CHAR));
