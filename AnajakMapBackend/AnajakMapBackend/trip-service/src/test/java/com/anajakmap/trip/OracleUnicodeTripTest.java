package com.anajakmap.trip;

import static org.junit.jupiter.api.Assertions.*;

import java.sql.*;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

/** Opt in only with a disposable Oracle test schema, never production credentials. */
@EnabledIfEnvironmentVariable(named = "ORACLE_TEST_URL", matches = ".+")
class OracleUnicodeTripTest {
  @Test void migratedOracleRoundTripsLongKhmerAndEmojiAcrossTripAndItineraryFields() throws Exception {
    String url=System.getenv("ORACLE_TEST_URL"), user=System.getenv("ORACLE_TEST_USER"), password=System.getenv("ORACLE_TEST_PASSWORD");
    Flyway.configure().dataSource(url,user,password).locations("classpath:db/migration").load().migrate();
    try (var connection=DriverManager.getConnection(url,user,password)) {
      connection.setAutoCommit(false);
      try {
        String trip=UUID.randomUUID().toString(), itinerary=UUID.randomUUID().toString();
        String title="ក".repeat(190)+" 🏯 🌴", destination="ខ".repeat(200), source="គ".repeat(490)+" 🗺️";
        execute(connection,"INSERT INTO trips(id,owner_id,title,destination,timezone,start_date,end_date,created_at) VALUES(?,'unicode-test',?,?,'Asia/Phnom_Penh',DATE '2026-10-27',DATE '2026-10-28',SYSTIMESTAMP)",trip,title,destination);
        execute(connection,"INSERT INTO itinerary_versions(id,trip_id,status,source) VALUES(?,?,'DRAFT',?)",itinerary,trip,source);
        execute(connection,"INSERT INTO activities(id,itinerary_id,sequence_no,title,starts_at,ends_at,latitude,longitude,source) VALUES(?,?,0,?,SYSTIMESTAMP,SYSTIMESTAMP+INTERVAL '1' HOUR,11.56,104.92,?)",UUID.randomUUID().toString(),itinerary,title,source);
        execute(connection,"INSERT INTO calendar_events(id,trip_id,title,starts_at,ends_at,timezone) VALUES(?,?,?,SYSTIMESTAMP,SYSTIMESTAMP+INTERVAL '1' HOUR,'Asia/Phnom_Penh')",UUID.randomUUID().toString(),trip,title);
        try (var query=connection.prepareStatement("SELECT t.title,t.destination,i.source,a.title,a.source,e.title FROM trips t JOIN itinerary_versions i ON i.trip_id=t.id JOIN activities a ON a.itinerary_id=i.id JOIN calendar_events e ON e.trip_id=t.id WHERE t.id=?")) {
          query.setString(1,trip);
          try (var result=query.executeQuery()) {
            assertTrue(result.next());
            assertEquals(title,result.getString(1)); assertEquals(destination,result.getString(2));
            assertEquals(source,result.getString(3)); assertEquals(title,result.getString(4));
            assertEquals(source,result.getString(5)); assertEquals(title,result.getString(6));
          }
        }
      } finally { connection.rollback(); }
    }
  }

  private static void execute(Connection connection,String sql,String... values) throws SQLException {
    try (var statement=connection.prepareStatement(sql)) {
      for (int i=0;i<values.length;i++) statement.setString(i+1,values[i]);
      assertEquals(1,statement.executeUpdate());
    }
  }
}
