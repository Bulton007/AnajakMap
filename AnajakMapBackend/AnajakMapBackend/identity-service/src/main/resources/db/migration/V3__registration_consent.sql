ALTER TABLE accounts ADD (
  display_name VARCHAR2(120 CHAR),
  legal_version VARCHAR2(120 CHAR),
  legal_accepted_at TIMESTAMP WITH TIME ZONE
);
