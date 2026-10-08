package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

@EnabledIfEnvironmentVariable(named = "ORACLE_TEST_URL", matches = ".+")
class OraclePersistenceTest {
  @Test
  void migrationsRollbackAppendOnlyOutboxAndOptimisticLock() throws Exception {
    String url = System.getenv("ORACLE_TEST_URL"),
        user = System.getenv("ORACLE_TEST_USER"),
        password = System.getenv("ORACLE_TEST_PASSWORD");
    Flyway.configure()
        .dataSource(url, user, password)
        .locations("filesystem:../trip-service/src/main/resources/db/migration")
        .load()
        .migrate();
    try (var c = DriverManager.getConnection(url, user, password)) {
      String id = UUID.randomUUID().toString();
      c.setAutoCommit(false);
      try (var p =
          c.prepareStatement(
              "INSERT INTO business_audit(id,actor,action,entity_id)"
                  + " VALUES(?,'test','test','test')")) {
        p.setString(1, id);
        p.executeUpdate();
      }
      c.rollback();
      try (var p = c.prepareStatement("SELECT COUNT(*) FROM business_audit WHERE id=?")) {
        p.setString(1, id);
        try (var rs = p.executeQuery()) {
          rs.next();
          assertEquals(0, rs.getInt(1));
        }
      }
      try (var p =
          c.prepareStatement(
              "INSERT INTO business_audit(id,actor,action,entity_id)"
                  + " VALUES(?,'test','test','test')")) {
        p.setString(1, id);
        p.executeUpdate();
      }
      c.commit();
      assertThrows(
          SQLException.class,
          () -> {
            try (var p = c.prepareStatement("DELETE FROM business_audit WHERE id=?")) {
              p.setString(1, id);
              p.executeUpdate();
            }
          });
      c.rollback();
      String trip = UUID.randomUUID().toString();
      try (var p =
          c.prepareStatement(
              "INSERT INTO"
                  + " trips(id,owner_id,title,destination,timezone,start_date,end_date,created_at)"
                  + " VALUES(?,'test','Test','Phnom Penh','Asia/Phnom_Penh',DATE '2026-09-13',DATE"
                  + " '2026-09-14',SYSTIMESTAMP)")) {
        p.setString(1, trip);
        p.executeUpdate();
      }
      c.commit();
      try (var p =
          c.prepareStatement("UPDATE trips SET version=version+1 WHERE id=? AND version=0")) {
        p.setString(1, trip);
        assertEquals(1, p.executeUpdate());
        assertEquals(0, p.executeUpdate());
      }
      c.rollback();
    }
  }
}
