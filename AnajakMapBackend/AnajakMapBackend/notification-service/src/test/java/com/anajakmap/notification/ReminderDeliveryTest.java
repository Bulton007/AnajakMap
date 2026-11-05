package com.anajakmap.notification;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.anajakmap.platform.Changes;
import com.anajakmap.platform.SecretVault;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;

class ReminderDeliveryTest {
  @Test
  void schedulesAccountReminderAndWorkerRecordsSimulatedDelivery() {
    var jdbc = mock(JdbcTemplate.class);
    var changes = mock(Changes.class);
    var vault = mock(SecretVault.class);
    var api = new NotificationApi(jdbc, changes, vault);
    var account = Jwt.withTokenValue("test").header("alg", "none").subject("owner").build();
    var due = Instant.now().plusSeconds(60);
    var scheduled = (Map<?, ?>) api.reminder(account, new NotificationApi.Reminder("Pack bags", due));
    assertEquals("PENDING", scheduled.get("status"));
    String id = scheduled.get("id").toString();
    verify(jdbc).update(contains("INSERT INTO deliveries"), eq(id), eq("owner"), eq("Pack bags"),
        eq(Timestamp.from(due)), eq(Timestamp.from(due)));

    var env = mock(Environment.class);
    when(env.getActiveProfiles()).thenReturn(new String[]{"test"});
    when(jdbc.queryForList(contains("next_attempt<=CURRENT_TIMESTAMP")))
        .thenReturn(List.of(Map.of("ID", id, "OWNER_ID", "owner", "TITLE", "Pack bags", "ATTEMPTS", 0)));
    when(jdbc.update(contains("SET status='SENDING'"), eq(id))).thenReturn(1);
    new DeliveryWorker(changes, vault, jdbc, env, "", "").deliver();
    verify(jdbc).update(contains("delivered_at=CURRENT_TIMESTAMP"), eq("MOCK_DELIVERED"), eq(id));
  }
}
