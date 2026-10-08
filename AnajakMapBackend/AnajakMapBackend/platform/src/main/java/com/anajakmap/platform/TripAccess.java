package com.anajakmap.platform;

import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class TripAccess {
  private final RestClient client;

  public TripAccess(@Value("${anajak.trip-url}") String url) {
    client = HttpClients.client(url);
  }

  public void require(String trip, String bearer, boolean edit) {
    client
        .get()
        .uri("/api/v1/trips/{id}/access?edit={edit}", trip, edit)
        .header("Authorization", bearer)
        .header("X-Trace-ID", MDC.get("traceId") == null ? "" : MDC.get("traceId"))
        .retrieve()
        .toBodilessEntity();
  }

  public java.util.Set<String> members(String trip, String bearer) {
    java.util.Map response =
        client
            .get()
            .uri("/api/v1/trips/{id}/members", trip)
            .header("Authorization", bearer)
            .retrieve()
            .body(java.util.Map.class);
    java.util.List<java.util.Map> rows = (java.util.List<java.util.Map>) response.get("data");
    return rows.stream()
        .map(r -> r.get("ACCOUNT_ID").toString())
        .collect(java.util.stream.Collectors.toSet());
  }
}
