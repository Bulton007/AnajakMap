package com.anajakmap.platform;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.slf4j.MDC;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronizationManager;

@Component
public class Changes {
  private final JdbcTemplate jdbc;
  private final ObjectMapper json;

  public Changes(JdbcTemplate j, ObjectMapper o) {
    jdbc = j;
    json = o;
  }

  public String json(Object value) {
    try {
      return json.writeValueAsString(value);
    } catch (Exception e) {
      throw new IllegalArgumentException("Invalid payload", e);
    }
  }

  public static String hash(String s) {
    try {
      return HexFormat.of()
          .formatHex(
              MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  public void record(String actor, String action, String id, Map<String, ?> permittedFields) {
    if (!TransactionSynchronizationManager.isActualTransactionActive())
      throw new IllegalStateException("Audit requires local transaction");
    String trace = MDC.get("traceId");
    jdbc.update(
        "INSERT INTO business_audit(id,actor,action,entity_id,trace_id,fields) VALUES(?,?,?,?,?,?)",
        UUID.randomUUID().toString(),
        actor,
        action,
        id,
        trace,
        json(permittedFields));
    jdbc.update(
        "INSERT INTO event_outbox(id,event_type,payload,trace_id) VALUES(?,?,?,?)",
        UUID.randomUUID().toString(),
        action,
        json(Map.of("entityId", id, "actor", actor, "fields", permittedFields)),
        trace);
  }

  public Optional<String> prior(String actor, String key, String op, Object body) {
    if (key == null || !key.matches("[a-zA-Z0-9_-]{8,128}"))
      throw new IllegalArgumentException("Idempotency-Key required (8-128 characters)");
    var rows =
        jdbc.queryForList(
            "SELECT request_hash,response FROM idempotency_record WHERE actor=? AND request_key=?"
                + " AND operation=?",
            actor,
            key,
            op);
    if (rows.isEmpty()) return Optional.empty();
    if (!rows.getFirst().get("REQUEST_HASH").equals(hash(json(body)))) throw Api.conflict();
    return Optional.of(
        jdbc.queryForObject(
            "SELECT response FROM idempotency_record WHERE actor=? AND request_key=? AND"
                + " operation=?",
            String.class,
            actor,
            key,
            op));
  }

  public void remember(String actor, String key, String op, Object body, Object response) {
    jdbc.update(
        "INSERT INTO idempotency_record(actor,request_key,operation,request_hash,response)"
            + " VALUES(?,?,?,?,?)",
        actor,
        key,
        op,
        hash(json(body)),
        json(response));
  }
}
