CREATE TABLE direct_chat_messages (
  id VARCHAR(36) PRIMARY KEY,
  conversation_id VARCHAR(64) NOT NULL,
  sender_id VARCHAR(36) NOT NULL,
  recipient_id VARCHAR(36) NOT NULL,
  message VARCHAR(1000) NOT NULL,
  sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX direct_chat_recent ON direct_chat_messages(conversation_id,sent_at,id);
