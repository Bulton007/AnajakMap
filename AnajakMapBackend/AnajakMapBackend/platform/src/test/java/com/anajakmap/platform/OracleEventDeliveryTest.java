package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

@EnabledIfEnvironmentVariable(named = "EVENT_TEST_PASSWORD", matches = ".+")
class OracleEventDeliveryTest {
  @Test
  void repeatedConfirmedBrokerEventCreatesOneDelivery() throws Exception {
    var factory = new com.rabbitmq.client.ConnectionFactory();
    factory.setHost("rabbitmq");
    factory.setUsername(System.getenv("RABBIT_USER"));
    factory.setPassword(System.getenv("RABBIT_PASSWORD"));
    String id = UUID.randomUUID().toString(), actor = UUID.randomUUID().toString();
    byte[] body =
        ("{\"entityId\":\"" + id + "\",\"actor\":\"" + actor + "\",\"fields\":{}}")
            .getBytes(java.nio.charset.StandardCharsets.UTF_8);
    try (var connection = factory.newConnection();
        var channel = connection.createChannel()) {
      channel.confirmSelect();
      var properties =
          new com.rabbitmq.client.AMQP.BasicProperties.Builder()
              .messageId(id)
              .deliveryMode(2)
              .headers(Map.of("traceId", "integration-test"))
              .build();
      channel.basicPublish("anajak.events", "itinerary.approved", properties, body);
      channel.basicPublish("anajak.events", "itinerary.approved", properties, body);
      channel.waitForConfirmsOrDie(5000);
    }
    try (var c =
        DriverManager.getConnection(
            System.getenv("ORACLE_TEST_URL"),
            "NOTIFICATION_APP",
            System.getenv("EVENT_TEST_PASSWORD"))) {
      c.createStatement().execute("ALTER SESSION SET CURRENT_SCHEMA=NOTIFICATION");
      int count = 0;
      for (int attempt = 0; attempt < 30; attempt++) {
        try (var p = c.prepareStatement("SELECT COUNT(*) FROM deliveries WHERE owner_id=?")) {
          p.setString(1, actor);
          try (var rs = p.executeQuery()) {
            rs.next();
            count = rs.getInt(1);
          }
        }
        if (count > 0) break;
        Thread.sleep(500);
      }
      assertEquals(1, count);
      Thread.sleep(1000);
      try (var p = c.prepareStatement("SELECT COUNT(*) FROM deliveries WHERE owner_id=?")) {
        p.setString(1, actor);
        try (var rs = p.executeQuery()) {
          rs.next();
          assertEquals(1, rs.getInt(1));
        }
      }
    }
  }
}
