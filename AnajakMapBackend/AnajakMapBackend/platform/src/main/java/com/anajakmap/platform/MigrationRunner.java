package com.anajakmap.platform;

public final class MigrationRunner {
  private MigrationRunner() {}

  public static boolean runIfRequested() {
    if (!"true".equals(System.getenv("MIGRATE_ONLY"))) return false;
    var configuration = org.flywaydb.core.Flyway.configure()
        .dataSource(
            System.getenv().getOrDefault("DB_URL", "jdbc:oracle:thin:@oracle:1521/FREEPDB1"),
            System.getenv("DB_USER"),
            System.getenv("DB_PASSWORD"))
        .locations(System.getenv().getOrDefault("DB_MIGRATION_LOCATION", "classpath:db/migration"));
    String schema = System.getenv("DB_SCHEMA");
    if (schema != null && !schema.isBlank()) configuration.defaultSchema(schema);
    configuration.load().migrate();
    return true;
  }
}
