package com.anajakmap.identity;

import static org.junit.jupiter.api.Assertions.*;
import java.util.Map;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.hibernate.boot.MetadataSources;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

@EnabledIfEnvironmentVariable(named = "POSTGRES_TEST_URL", matches = ".+")
class PostgresAccountTest {
  @Test void accountSchemaValidationAndLargeObjectPreferencesRoundTrip() {
    String url = System.getenv("POSTGRES_TEST_URL");
    String user = System.getenv().getOrDefault("POSTGRES_TEST_USER", "postgres");
    String password = System.getenv().getOrDefault("POSTGRES_TEST_PASSWORD", "");
    String schema = "verify_account_" + UUID.randomUUID().toString().substring(0, 8);
    Flyway.configure().dataSource(url, user, password).defaultSchema(schema)
        .locations("filesystem:src/main/resources/db/postgresql").load().migrate();
    var registry = new StandardServiceRegistryBuilder().applySettings(Map.of(
        "hibernate.connection.url", url, "hibernate.connection.username", user,
        "hibernate.connection.password", password, "hibernate.default_schema", schema,
        "hibernate.hbm2ddl.auto", "validate",
        "hibernate.physical_naming_strategy",
        "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy")).build();
    try (var factory = new MetadataSources(registry).addAnnotatedClass(Account.class)
        .buildMetadata().buildSessionFactory()) {
      var account = new Account();
      account.id = UUID.randomUUID().toString(); account.email = account.id + "@example.test";
      account.passwordHash = "test-hash"; account.displayName = "Fictional traveler";
      account.preferences = "{\"language\":\"km\"}"; account.verified = true;
      try (var session = factory.openSession()) {
        var transaction = session.beginTransaction(); session.persist(account); transaction.commit();
      }
      try (var session = factory.openSession()) {
        var transaction = session.beginTransaction();
        var restored = session.find(Account.class, account.id);
        assertTrue(restored.verified); assertEquals(account.preferences, restored.preferences);
        transaction.commit();
      }
    } finally { StandardServiceRegistryBuilder.destroy(registry); }
  }
}
