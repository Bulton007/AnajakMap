-- A user may record an existing booking without uploading a document.
ALTER TABLE reservations MODIFY (document_id NULL);
