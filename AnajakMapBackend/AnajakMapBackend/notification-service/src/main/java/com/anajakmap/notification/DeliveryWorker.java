package com.anajakmap.notification;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
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
  @org.springframework.beans.factory.annotation.Autowired private StringRedisTemplate redis;

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
      String title = switch (kind) {
        case "itinerary.approved" -> "Your itinerary is approved";
        case "group.invited" -> "You have a trip invitation";
        case "group.joined" -> "Trip invitation accepted";
        case "group.invitation-rejected" -> "Trip invitation declined";
        case "group.invitation-cancelled" -> "Trip invitation cancelled";
        case "chat.trip-message" -> "New trip chat message";
        case "chat.direct-message" -> "New private message";
        default -> null;
      };
      if (title != null) {
        Map event =
            new com.fasterxml.jackson.databind.ObjectMapper().readValue(m.getBody(), Map.class);
        Map fields = (Map) event.get("fields");
        boolean itinerary = kind.equals("itinerary.approved");
        Object recipientValue = itinerary ? event.get("actor") : fields.get("accountId");
        List<String> recipients = fields.get("recipients") instanceof List<?> list
            ? list.stream().map(Object::toString).distinct().toList()
            : recipientValue == null ? List.of() : List.of(recipientValue.toString());
        for (String recipient : recipients) {
          String delivery = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO deliveries(id,owner_id,title,due_at,status,next_attempt,kind,trip_id,actor_id,detail)"
                  + " VALUES(?,?,?,CURRENT_TIMESTAMP,'PENDING',CURRENT_TIMESTAMP,?,?,?,?)",
              delivery, recipient, title, kind,
              kind.equals("chat.direct-message") ? null : event.get("entityId"),
              event.get("actor"), fields.get("tripTitle"));
          changes.record(recipient, "reminder.event-created", delivery, Map.of("sourceEvent", id));
        }
        org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(
            new org.springframework.transaction.support.TransactionSynchronization() {
              @Override public void afterCommit() { recipients.forEach(DeliveryWorker.this::signal); }
            });
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
            + " END,next_attempt=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE status='SENDING' AND"
            + " updated_at<CURRENT_TIMESTAMP-NUMTODSINTERVAL(120,'SECOND')");
    var rows =
        jdbc.queryForList(
            "SELECT id,owner_id,attempts FROM deliveries WHERE status='PENDING' AND"
                + " next_attempt<=CURRENT_TIMESTAMP FETCH FIRST 20 ROWS ONLY");
    for (var r : rows) {
      String id = r.get("ID").toString();
      if (jdbc.update(
              "UPDATE deliveries SET status='SENDING',attempts=attempts+1,updated_at=CURRENT_TIMESTAMP WHERE id=? AND"
                  + " status='PENDING' AND next_attempt<=CURRENT_TIMESTAMP",
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
                      jdbc.queryForObject("SELECT title FROM deliveries WHERE id=?", String.class, id)))
              .retrieve()
              .toBodilessEntity();
        }
        jdbc.update(
            "UPDATE deliveries SET status=?,delivered_at=CURRENT_TIMESTAMP WHERE id=?",
            dev ? "MOCK_DELIVERED" : "DELIVERED",
            id);
        signal(r.get("OWNER_ID").toString());
      } catch (Exception e) {
        int n = ((Number) r.get("ATTEMPTS")).intValue() + 1;
        jdbc.update(
            "UPDATE deliveries SET"
                + " status=?,attempts=?,next_attempt=CURRENT_TIMESTAMP+NUMTODSINTERVAL(?,'SECOND') WHERE"
                + " id=?",
            n >= 5 ? "DEAD" : "PENDING",
            n,
            Math.min(300, 1 << n),
            id);
      }
    }
  }

  private void signal(String account) {
    if (redis == null) return;
    try {
      redis.convertAndSend("anajak.notifications", account);
    } catch (org.springframework.dao.DataAccessException ex) {
      org.slf4j.LoggerFactory.getLogger(DeliveryWorker.class).warn("Notification live signal unavailable");
    }
  }
}
