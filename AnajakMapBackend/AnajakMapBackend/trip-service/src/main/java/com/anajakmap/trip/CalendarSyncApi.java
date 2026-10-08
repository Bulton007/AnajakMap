package com.anajakmap.trip;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/trips")
public class CalendarSyncApi {
  private final TripApi trips;
  private final boolean dev;
  private final String url, key;

  public CalendarSyncApi(
      TripApi t,
      Environment e,
      @Value("${CALENDAR_PROVIDER_URL:}") String u,
      @Value("${CALENDAR_PROVIDER_KEY:}") String k) {
    trips = t;
    url = u;
    key = k;
    dev =
        Arrays.asList(e.getActiveProfiles()).stream()
            .anyMatch(p -> p.equals("dev") || p.equals("test"));
  }

  @PostMapping("/{id}/calendar/sync")
  public Object sync(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Idempotency-Key") String requestKey) {
    trips.require(id, jwt.getSubject(), true);
    Object calendar = trips.calendar(id, jwt);
    if (dev) return Map.of("status", "MOCK_SYNCED", "mock", true, "calendar", calendar);
    if (url.isBlank() || key.isBlank())
      throw new ResponseStatusException(
          HttpStatus.SERVICE_UNAVAILABLE, "Optional calendar provider is not configured");
    return HttpClients.client(url)
        .post()
        .uri("/calendar/sync")
        .header("Authorization", "Bearer " + key)
        .header("Idempotency-Key", requestKey)
        .body(Map.of("tripId", id, "calendar", calendar))
        .retrieve()
        .body(Map.class);
  }
}
