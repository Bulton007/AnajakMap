package com.anajakmap.gateway;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.boot.actuate.health.*;
import org.springframework.stereotype.Component;

@Component("downstream")
public class DownstreamHealth implements HealthIndicator {
  public Health health() {
    Map<String, Integer> services =
        Map.of(
            "identity",
            8081,
            "trip",
            8082,
            "ai-guide",
            8083,
            "discovery",
            8084,
            "expense",
            8085,
            "reservation",
            8086,
            "journal",
            8087,
            "notification",
            8088);
    try {
      for (var e : services.entrySet()) {
        String url = System.getenv(e.getKey().toUpperCase().replace('-', '_') + "_URL");
        if (url == null) url = "http://" + e.getKey() + "-service:" + e.getValue();
        HttpClients.client(url)
            .get()
            .uri("/actuator/health/readiness")
            .retrieve()
            .toBodilessEntity();
      }
      return Health.up().build();
    } catch (Exception e) {
      return Health.down().withDetail("reason", "A downstream service is unavailable").build();
    }
  }
}
