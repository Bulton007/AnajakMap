CREATE TABLE direct_chat_messages (
  id VARCHAR2(36) PRIMARY KEY,
  conversation_id VARCHAR2(64) NOT NULL,
  sender_id VARCHAR2(36) NOT NULL,
  recipient_id VARCHAR2(36) NOT NULL,
  message VARCHAR2(1000 CHAR) NOT NULL,
  sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);
CREATE INDEX direct_chat_recent ON direct_chat_messages(conversation_id,sent_at,id);
