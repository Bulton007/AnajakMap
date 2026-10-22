package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;
import java.sql.*;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

@EnabledIfEnvironmentVariable(named = "POSTGRES_TEST_URL", matches = ".+")
class PostgresPersistenceTest {
  @Test void allServiceMigrationsAndRuntimeSql() throws Exception {
    String url = System.getenv("POSTGRES_TEST_URL");
    String user = System.getenv().getOrDefault("POSTGRES_TEST_USER", "postgres");
    String password = System.getenv().getOrDefault("POSTGRES_TEST_PASSWORD", "");
    for (String service : new String[] {"identity", "trip", "ai-guide", "discovery",
        "expense", "reservation", "journal", "notification", "gateway"}) {
      String schema = "verify_" + service.replace('-', '_') + "_" + UUID.randomUUID().toString().substring(0, 8);
      var flyway = Flyway.configure().dataSource(url, user, password).defaultSchema(schema)
          .locations("filesystem:../" + service + "-service/src/main/resources/db/postgresql")
          .load();
      assertEquals(1, flyway.migrate().migrationsExecuted, service);
      assertEquals(0, flyway.migrate().migrationsExecuted, "repeat migration must be safe");
      try (var connection = DriverManager.getConnection(url, user, password)) {
        connection.setSchema(schema);
        try (var interval = connection.prepareStatement(
            "SELECT CURRENT_TIMESTAMP + NUMTODSINTERVAL(?,'SECOND') > CURRENT_TIMESTAMP")) {
          interval.setInt(1, 10);
          try (var result = interval.executeQuery()) { assertTrue(result.next()); assertTrue(result.getBoolean(1)); }
        }
        try (var inbox = connection.prepareStatement(
            "MERGE INTO event_inbox dst USING(SELECT ? id FROM dual) src ON(dst.id=src.id)"
            + " WHEN NOT MATCHED THEN INSERT(id) VALUES(src.id)")) {
          inbox.setString(1, UUID.randomUUID().toString());
          assertEquals(1, inbox.executeUpdate());
          assertEquals(0, inbox.executeUpdate());
        }
        try (var statement = connection.createStatement()) {
          statement.executeUpdate("INSERT INTO business_audit(id,actor,action,entity_id) VALUES('test','test','test','test')");
          assertThrows(SQLException.class, () -> statement.executeUpdate("DELETE FROM business_audit WHERE id='test'"));
        }
      }
    }
  }
}
