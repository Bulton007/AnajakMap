package com.anajakmap.gateway;

import java.util.Arrays;
import java.util.Map;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class RuntimeApi {
  private final Environment environment;
  public RuntimeApi(Environment environment) { this.environment = environment; }
  @GetMapping("/api/v1/runtime")
  public Map<String, Object> runtime() {
    boolean development = Arrays.stream(environment.getActiveProfiles())
        .anyMatch(p -> p.equals("dev") || p.equals("test"));
    return Map.of("apiVersion", "v1", "developmentProviders", development,
        "storage", "Oracle", "manualReservations", true);
  }
}
