ALTER TABLE deliveries ADD kind VARCHAR(32) DEFAULT 'REMINDER' NOT NULL;
ALTER TABLE deliveries ADD trip_id VARCHAR(36);
ALTER TABLE deliveries ADD actor_id VARCHAR(36);
ALTER TABLE deliveries ADD detail VARCHAR(200);
ALTER TABLE deliveries ADD read_at TIMESTAMP WITH TIME ZONE;
UPDATE deliveries SET kind='LEGACY_EVENT'
 WHERE title IN ('You have a trip invitation','Your itinerary is approved');
CREATE INDEX deliveries_inbox_idx ON deliveries(owner_id, read_at, due_at);
