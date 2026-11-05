package com.anajakmap.notification;

import com.anajakmap.platform.*;
import jakarta.validation.*;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationApi {
  private final SecretVault vault;
  private final JdbcTemplate jdbc;
  private final Changes changes;

  public NotificationApi(JdbcTemplate j, Changes c, SecretVault v) {
    jdbc = j;
    changes = c;
    vault = v;
  }

  public record Device(
      @NotBlank @Size(max = 2000) String token, @Pattern(regexp = "ANDROID|IOS") String platform) {}

  public record Reminder(@NotBlank @Size(max = 200) String title, @Future @NotNull Instant dueAt) {}

  @PostMapping("/devices")
  @Transactional
  public Object device(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Device r) {
    String id = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO devices(id,owner_id,token,platform) VALUES(?,?,?,?)",
        id,
        jwt.getSubject(),
        vault.encrypt(r.token),
        r.platform);
    changes.record(jwt.getSubject(), "device.registered", id, Map.of("platform", r.platform));
    return Map.of("id", id);
  }

  @DeleteMapping("/devices/{id}")
  @Transactional
  public void delete(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    if (jdbc.update("DELETE FROM devices WHERE id=? AND owner_id=?", id, jwt.getSubject()) != 1)
      throw Api.missing();
    changes.record(jwt.getSubject(), "device.deleted", id, Map.of());
  }

  @PostMapping("/reminders")
  @Transactional
  public Object reminder(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Reminder r) {
    String id = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO deliveries(id,owner_id,title,due_at,status,next_attempt)"
            + " VALUES(?,?,?,?,'PENDING',?)",
        id,
        jwt.getSubject(),
        r.title,
        java.sql.Timestamp.from(r.dueAt),
        java.sql.Timestamp.from(r.dueAt));
    changes.record(jwt.getSubject(), "reminder.created", id, Map.of("dueAt", r.dueAt));
    return Map.of("id", id, "status", "PENDING");
  }

  @GetMapping("/deliveries")
  public Object deliveries(
      @AuthenticationPrincipal Jwt jwt, @RequestParam(defaultValue = "0") int page) {
    if (page < 0) throw new IllegalArgumentException();
    return jdbc.queryForList(
        "SELECT id,title,due_at,status,attempts,kind,trip_id,actor_id,detail,read_at"
            + " FROM deliveries WHERE owner_id=? ORDER BY due_at DESC,id"
            + " OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY",
        jwt.getSubject(),
        page * 50);
  }

  @PutMapping("/reminders/{id}")
  @Transactional
  public Object reschedule(@PathVariable String id, @AuthenticationPrincipal Jwt jwt,
      @Valid @RequestBody Reminder r) {
    var due = java.sql.Timestamp.from(r.dueAt);
    if (jdbc.update("UPDATE deliveries SET title=?,due_at=?,next_attempt=?,attempts=0"
        + " WHERE id=? AND owner_id=? AND kind='REMINDER' AND status='PENDING'",
        r.title, due, due, id, jwt.getSubject()) != 1) throw Api.conflict();
    changes.record(jwt.getSubject(), "reminder.rescheduled", id, Map.of("dueAt", r.dueAt));
    return Map.of("id", id, "status", "PENDING");
  }

  @DeleteMapping("/reminders/{id}")
  @Transactional
  public void cancelReminder(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    if (jdbc.update("UPDATE deliveries SET status='CANCELLED' WHERE id=? AND owner_id=?"
        + " AND kind='REMINDER' AND status='PENDING'", id, jwt.getSubject()) == 1) {
      changes.record(jwt.getSubject(), "reminder.cancelled", id, Map.of());
      return;
    }
    if (jdbc.queryForObject("SELECT COUNT(*) FROM deliveries WHERE id=? AND owner_id=?"
        + " AND kind='REMINDER' AND status='CANCELLED'", Integer.class, id, jwt.getSubject()) == 0)
      throw Api.conflict();
  }

  @GetMapping("/unread")
  public Map<String, Integer> unread(@AuthenticationPrincipal Jwt jwt) {
    return Map.of("count", jdbc.queryForObject(
        "SELECT COUNT(*) FROM deliveries WHERE owner_id=? AND read_at IS NULL"
            + " AND status<>'CANCELLED' AND due_at<=CURRENT_TIMESTAMP",
        Integer.class, jwt.getSubject()));
  }

  @PutMapping("/deliveries/{id}/read")
  public void read(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    jdbc.update("UPDATE deliveries SET read_at=CURRENT_TIMESTAMP WHERE id=? AND owner_id=?"
        + " AND read_at IS NULL AND status<>'CANCELLED' AND due_at<=CURRENT_TIMESTAMP",
        id, jwt.getSubject());
  }

  @PutMapping("/deliveries/read")
  public void readAll(@AuthenticationPrincipal Jwt jwt) {
    jdbc.update("UPDATE deliveries SET read_at=CURRENT_TIMESTAMP WHERE owner_id=?"
        + " AND read_at IS NULL AND status<>'CANCELLED' AND due_at<=CURRENT_TIMESTAMP",
        jwt.getSubject());
  }
}
