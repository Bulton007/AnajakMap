CREATE TABLE trip_chat_messages (
  id VARCHAR2(36) PRIMARY KEY,
  trip_id VARCHAR2(36) NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_id VARCHAR2(36) NOT NULL,
  message VARCHAR2(1000) NOT NULL,
  sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX trip_chat_recent ON trip_chat_messages(trip_id, sent_at, id);
