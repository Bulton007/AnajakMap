CREATE TABLE trip_chat_messages (
  id VARCHAR(36) PRIMARY KEY,
  trip_id VARCHAR(36) NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_id VARCHAR(36) NOT NULL,
  message VARCHAR(1000) NOT NULL,
  sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX trip_chat_recent ON trip_chat_messages(trip_id, sent_at, id);
