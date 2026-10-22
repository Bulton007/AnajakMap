package com.anajakmap.platform;

import java.util.Locale;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.context.annotation.*;
import org.springframework.jdbc.core.*;

/** Keep JDBC row field names identical to the existing Oracle HTTP contracts. */
@Configuration
@Profile("neon")
public class PostgresJdbcConfiguration {
  @Bean
  public JdbcTemplate jdbcTemplate(DataSource source) {
    return new JdbcTemplate(source) {
      @Override protected RowMapper<Map<String, Object>> getColumnMapRowMapper() {
        return new ColumnMapRowMapper() {
          @Override protected String getColumnKey(String name) {
            return name.toUpperCase(Locale.ROOT);
          }
        };
      }
    };
  }
}
