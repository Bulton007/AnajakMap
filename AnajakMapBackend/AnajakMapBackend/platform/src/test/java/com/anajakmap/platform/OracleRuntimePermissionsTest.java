package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

@EnabledIfEnvironmentVariable(named = "ORACLE_RUNTIME_PASSWORD", matches = ".+")
class OracleRuntimePermissionsTest {
  @Test
  void applicationCannotMutateAuditOrReadAnotherSchema() throws Exception {
    try (var c =
        DriverManager.getConnection(
            System.getenv("ORACLE_TEST_URL"),
            "TRIP_APP",
            System.getenv("ORACLE_RUNTIME_PASSWORD"))) {
      try (var s = c.createStatement()) {
        s.execute("ALTER SESSION SET CURRENT_SCHEMA=TRIP");
        assertThrows(
            SQLException.class,
            () -> s.executeUpdate("UPDATE business_audit SET action='tampered'"));
        assertThrows(SQLException.class, () -> s.executeUpdate("DELETE FROM business_audit"));
        assertThrows(
            SQLException.class, () -> s.execute("ALTER TRIGGER TRIP.audit_immutable DISABLE"));
        assertThrows(SQLException.class, () -> s.executeQuery("SELECT id FROM IDENTITY.accounts"));
        try (var rs = s.executeQuery("SELECT COUNT(*) FROM trips")) {
          assertTrue(rs.next());
        }
      }
    }
  }
}
