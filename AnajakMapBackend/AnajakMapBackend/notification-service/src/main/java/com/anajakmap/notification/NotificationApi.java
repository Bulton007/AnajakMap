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
        "SELECT id,title,due_at,status,attempts FROM deliveries WHERE owner_id=? ORDER BY due_at"
            + " DESC OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY",
        jwt.getSubject(),
        page * 50);
  }
}
