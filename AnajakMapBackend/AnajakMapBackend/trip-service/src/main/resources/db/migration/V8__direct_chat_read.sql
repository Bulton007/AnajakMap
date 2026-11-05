ALTER TABLE direct_chat_messages ADD read_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE trip_chat_messages MODIFY message VARCHAR2(1000 CHAR);
