package com.anajakmap.platform;

import java.util.*;
import java.util.concurrent.TimeUnit;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class Events {
  private final JdbcTemplate jdbc;
  private final RabbitTemplate rabbit;

  public Events(JdbcTemplate j, RabbitTemplate r) {
    jdbc = j;
    rabbit = r;
  }

  @Bean
  TopicExchange businessExchange() {
    return new TopicExchange("anajak.events", true, false);
  }

  @Bean
  DirectExchange deadExchange() {
    return new DirectExchange("anajak.dead", true, false);
  }

  @Bean
  org.springframework.amqp.core.Queue deadQueue(@Value("${spring.application.name}") String s) {
    return QueueBuilder.durable(s + ".dead").quorum().build();
  }

  @Bean
  Binding deadBinding(
      org.springframework.amqp.core.Queue deadQueue,
      DirectExchange deadExchange,
      @Value("${spring.application.name}") String s) {
    return BindingBuilder.bind(deadQueue).to(deadExchange).with(s);
  }

  @Scheduled(fixedDelay = 2000)
  public void publish() {
    var rows =
        jdbc.queryForList(
            "SELECT id,event_type,payload,trace_id,attempts FROM event_outbox WHERE published_at IS"
                + " NULL AND dead=0 AND next_attempt<=CURRENT_TIMESTAMP ORDER BY created_at FETCH FIRST"
                + " 25 ROWS ONLY");
    for (var row : rows) {
      String id = row.get("ID").toString();
      try {
        String payload =
            jdbc.queryForObject("SELECT payload FROM event_outbox WHERE id=?", String.class, id);
        var c = new CorrelationData(id);
        rabbit.convertAndSend(
            "anajak.events",
            row.get("EVENT_TYPE").toString(),
            payload,
            m -> {
              m.getMessageProperties().setMessageId(id);
              m.getMessageProperties().setDeliveryMode(MessageDeliveryMode.PERSISTENT);
              m.getMessageProperties().setHeader("traceId", row.get("TRACE_ID"));
              return m;
            },
            c);
        var confirm = c.getFuture().get(5, TimeUnit.SECONDS);
        if (!confirm.isAck() || c.getReturned() != null)
          throw new IllegalStateException("Not confirmed/routed");
        jdbc.update("UPDATE event_outbox SET published_at=CURRENT_TIMESTAMP WHERE id=?", id);
      } catch (Exception e) {
        int n = ((Number) row.get("ATTEMPTS")).intValue() + 1;
        jdbc.update(
            "UPDATE event_outbox SET"
                + " attempts=?,dead=?,next_attempt=CURRENT_TIMESTAMP+NUMTODSINTERVAL(?,'SECOND') WHERE"
                + " id=?",
            n,
            n >= 8 ? 1 : 0,
            Math.min(300, 1 << n),
            id);
        org.slf4j.LoggerFactory.getLogger(Events.class)
            .warn(
                "event_publish_failed event={} attempt={} type={}",
                id,
                n,
                e.getClass().getSimpleName());
      }
    }
  }
}
