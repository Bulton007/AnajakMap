package com.anajakmap.platform;

import static org.mockito.Mockito.*;

import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.jdbc.core.JdbcTemplate;

class OutboxRetryTest {
  @Test
  void failureIsBoundedAndMarksDeadAtEight() {
    var jdbc = mock(JdbcTemplate.class);
    var rabbit = mock(RabbitTemplate.class);
    Map<String, Object> row = new HashMap<>();
    row.put("ID", "event-1");
    row.put("EVENT_TYPE", "test.event");
    row.put("TRACE_ID", "trace");
    row.put("ATTEMPTS", 7);
    when(jdbc.queryForList(anyString())).thenReturn(List.of(row));
    when(jdbc.queryForObject(anyString(), eq(String.class), eq("event-1"))).thenReturn("{}");
    doThrow(new IllegalStateException("unavailable"))
        .when(rabbit)
        .convertAndSend(
            eq("anajak.events"),
            eq("test.event"),
            eq("{}"),
            any(org.springframework.amqp.core.MessagePostProcessor.class),
            any(org.springframework.amqp.rabbit.connection.CorrelationData.class));
    new Events(jdbc, rabbit).publish();
    verify(jdbc).update(contains("attempts=?"), eq(8), eq(1), eq(256), eq("event-1"));
  }
}
