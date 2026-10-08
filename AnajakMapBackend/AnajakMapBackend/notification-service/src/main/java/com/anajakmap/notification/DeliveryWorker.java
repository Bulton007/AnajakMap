package com.anajakmap.notification;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
public class DeliveryWorker {
  private final Changes changes;
  private final SecretVault vault;
  private final JdbcTemplate jdbc;
  private final String url, key;
  private final boolean dev;

  public DeliveryWorker(
      Changes c,
      SecretVault v,
      JdbcTemplate j,
      Environment e,
      @Value("${anajak.provider-url}") String u,
      @Value("${anajak.provider-key}") String k) {
    changes = c;
    vault = v;
    jdbc = j;
    url = u;
    key = k;
    dev =
        Arrays.asList(e.getActiveProfiles()).stream()
            .anyMatch(p -> p.equals("dev") || p.equals("test"));
    if (!dev && (u.isBlank() || k.isBlank()))
      throw new IllegalStateException("Push provider URL/key required");
  }

  @Bean
  org.springframework.amqp.core.Queue notificationQueue() {
    return QueueBuilder.durable("anajak.notification")
        .quorum()
        .deadLetterExchange("anajak.dead")
        .deadLetterRoutingKey("notification-service")
        .build();
  }

  @Bean
  Binding notificationBinding(
      org.springframework.amqp.core.Queue notificationQueue, TopicExchange businessExchange) {
    return BindingBuilder.bind(notificationQueue).to(businessExchange).with("#");
  }

  @RabbitListener(queues = "anajak.notification")
  @Transactional
  public void event(Message m) {
    String id = m.getMessageProperties().getMessageId();
    if (id == null) throw new IllegalArgumentException("Event ID required");
    int inserted =
        jdbc.update(
            "MERGE INTO event_inbox dst USING(SELECT ? id FROM dual) src ON(dst.id=src.id) WHEN NOT"
                + " MATCHED THEN INSERT(id) VALUES(src.id)",
            id);
    if (inserted == 0) return;
    Object trace = m.getMessageProperties().getHeader("traceId");
    org.slf4j.MDC.put("traceId", trace == null ? id : trace.toString());
    try {
      String kind = m.getMessageProperties().getReceivedRoutingKey();
      if (Set.of("itinerary.approved", "group.invited").contains(kind)) {
        Map event =
            new com.fasterxml.jackson.databind.ObjectMapper().readValue(m.getBody(), Map.class);
        Map fields = (Map) event.get("fields");
        String recipient =
            kind.equals("group.invited")
                ? fields.get("accountId").toString()
                : event.get("actor").toString();
        String delivery = UUID.randomUUID().toString();
        jdbc.update(
            "INSERT INTO deliveries(id,owner_id,title,due_at,status,next_attempt)"
                + " VALUES(?,?,?,SYSTIMESTAMP,'PENDING',SYSTIMESTAMP)",
            delivery,
            recipient,
            kind.equals("group.invited")
                ? "You have a trip invitation"
                : "Your itinerary is approved");
        changes.record(recipient, "reminder.event-created", delivery, Map.of("sourceEvent", id));
      }
    } catch (java.io.IOException e) {
      throw new IllegalArgumentException("Invalid event", e);
    } finally {
      org.slf4j.MDC.clear();
    }
  }

  @Scheduled(fixedDelay = 2000)
  public void deliver() {
    jdbc.update(
        "UPDATE deliveries SET status=CASE WHEN attempts>=5 THEN 'DEAD' ELSE 'PENDING'"
            + " END,next_attempt=SYSTIMESTAMP,updated_at=SYSTIMESTAMP WHERE status='SENDING' AND"
            + " updated_at<SYSTIMESTAMP-NUMTODSINTERVAL(120,'SECOND')");
    var rows =
        jdbc.queryForList(
            "SELECT id,owner_id,title,attempts FROM deliveries WHERE status='PENDING' AND"
                + " next_attempt<=SYSTIMESTAMP FETCH FIRST 20 ROWS ONLY");
    for (var r : rows) {
      String id = r.get("ID").toString();
      if (jdbc.update(
              "UPDATE deliveries SET status='SENDING',attempts=attempts+1,updated_at=SYSTIMESTAMP WHERE id=? AND"
                  + " status='PENDING'",
              id)
          != 1) continue;
      try {
        var tokens =
            jdbc.queryForList(
                "SELECT token FROM devices WHERE owner_id=?", String.class, r.get("OWNER_ID"));
        if (!dev) {
          if (tokens.isEmpty()) throw new IllegalStateException("No device");
          HttpClients.client(url)
              .post()
              .uri("/push")
              .header("Authorization", "Bearer " + key)
              .header("Idempotency-Key", id)
              .body(
                  Map.of(
                      "tokens",
                      tokens.stream().map(vault::decrypt).toList(),
                      "title",
                      r.get("TITLE")))
              .retrieve()
              .toBodilessEntity();
        }
        jdbc.update(
            "UPDATE deliveries SET status=?,delivered_at=SYSTIMESTAMP WHERE id=?",
            dev ? "MOCK_DELIVERED" : "DELIVERED",
            id);
      } catch (Exception e) {
        int n = ((Number) r.get("ATTEMPTS")).intValue() + 1;
        jdbc.update(
            "UPDATE deliveries SET"
                + " status=?,attempts=?,next_attempt=SYSTIMESTAMP+NUMTODSINTERVAL(?,'SECOND') WHERE"
                + " id=?",
            n >= 5 ? "DEAD" : "PENDING",
            n,
            Math.min(300, 1 << n),
            id);
      }
    }
  }
}
