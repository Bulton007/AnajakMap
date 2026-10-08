package com.anajakmap.platform;

public final class MigrationRunner {
  private MigrationRunner() {}

  public static boolean runIfRequested() {
    if (!"true".equals(System.getenv("MIGRATE_ONLY"))) return false;
    org.flywaydb.core.Flyway.configure()
        .dataSource(
            System.getenv().getOrDefault("DB_URL", "jdbc:oracle:thin:@oracle:1521/FREEPDB1"),
            System.getenv("DB_USER"),
            System.getenv("DB_PASSWORD"))
        .locations("classpath:db/migration")
        .load()
        .migrate();
    return true;
  }
}
