ALTER TABLE trip_members ADD invitation_status VARCHAR2(12) DEFAULT 'PENDING' NOT NULL;
UPDATE trip_members SET invitation_status='ACCEPTED' WHERE accepted=1;
ALTER TABLE trip_members ADD CONSTRAINT trip_invitation_status_ck
  CHECK (invitation_status IN ('PENDING','ACCEPTED','REJECTED','CANCELLED'));
