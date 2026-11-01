package com.anajakmap.discovery;

import com.anajakmap.platform.HttpClients;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.net.URI;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.*;
import java.util.function.LongSupplier;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

/** Explicitly configured driving router. No fabricated geometry or live traffic. */
@Component
public class OsrmRoutes {
  private static final double MAX_ROAD_SNAP_METERS = 1000;
  private final RestClient client;
  private final boolean demo;
  private final LongSupplier clock;
  private long nextDemoRequest;
  @Autowired public OsrmRoutes(Environment environment) {
    String url = environment.getProperty("OSRM_URL", "").strip();
    boolean development = Arrays.stream(environment.getActiveProfiles())
        .anyMatch(profile -> profile.equals("dev") || profile.equals("test"));
    if (url.isBlank() && development && environment.getProperty("OSRM_DEMO_ENABLED", Boolean.class, false))
      url = "https://router.project-osrm.org";
    demo = isPublicDemo(url);
    if (demo && !development)
      throw new IllegalStateException("The public OSRM demo is only allowed in dev/test; configure your own OSRM_URL for production");
    // The shared HTTP client retries GETs immediately. The public demo permits at
    // most one request/second, so use a dedicated non-retrying client instead.
    client = url.isBlank() ? null : demo ? demoClient(url) : HttpClients.client(url);
    clock = System::currentTimeMillis;
  }
  OsrmRoutes(RestClient client) { this(client, false, System::currentTimeMillis); }
  OsrmRoutes(RestClient client, boolean demo, LongSupplier clock) {
    this.client = client; this.demo = demo; this.clock = clock;
  }

  private static boolean isPublicDemo(String url) {
    if (url.isBlank()) return false;
    String host = URI.create(url).getHost();
    return "router.project-osrm.org".equalsIgnoreCase(host) || "routing.openstreetmap.de".equalsIgnoreCase(host);
  }

  private static RestClient demoClient(String url) {
    var factory = new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
    factory.setReadTimeout(Duration.ofSeconds(15));
    return RestClient.builder().baseUrl(url).requestFactory(factory)
        .defaultHeader(HttpHeaders.USER_AGENT, "AnajakMap/1.0 non-commercial testing (https://github.com/Bulton007/AnajakMap)").build();
  }

  private synchronized void claimDemoRequest() {
    long now = clock.getAsLong();
    if (now < nextDemoRequest) throw retryLater("Public route demo is busy. Retry shortly.", 1);
    nextDemoRequest = now + 1000;
  }

  private ResponseStatusException retryLater(String message, long seconds) {
    return new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, message) {
      @Override public HttpHeaders getHeaders() {
        var headers = new HttpHeaders();
        headers.set(HttpHeaders.RETRY_AFTER, Long.toString(seconds));
        return headers;
      }
    };
  }

  public Map<String, Object> route(Map<String, String> input) {
    double a = coordinate(input, "originLat", 90), b = coordinate(input, "originLon", 180);
    double c = coordinate(input, "destinationLat", 90), d = coordinate(input, "destinationLon", 180);
    if (!input.getOrDefault("mode", "driving").equals("driving"))
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "This router supports driving only");
    if (client == null) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Driving routes require a configured OSRM_URL");
    if (demo) claimDemoRequest();
    Map<?, ?> body;
    try {
      body = client.get().uri("/route/v1/driving/{points}?overview=full&geometries=geojson&steps=false&radiuses=1000;1000",
          b + "," + a + ";" + d + "," + c).retrieve().body(Map.class);
    } catch (RestClientResponseException response) {
      if (response.getStatusCode().value() == 429) {
        long retry = 1;
        try { retry = Math.max(1, Long.parseLong(response.getResponseHeaders().getFirst(HttpHeaders.RETRY_AFTER))); }
        catch (Exception ignored) { /* Unknown provider timing: ask for a short retry. */ }
        throw retryLater("Routing provider is busy. Retry after the indicated delay.", retry);
      }
      try {
        var document = new ObjectMapper().readTree(response.getResponseBodyAsString());
        String code = document == null ? "" : document.path("code").asText();
        var problem = providerProblem(code);
        if (problem != null) throw problem;
      } catch (com.fasterxml.jackson.core.JsonProcessingException malformed) {
        // HTML errors and unknown provider failures are not a successful route.
      }
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Routing provider unavailable");
    } catch (Exception unavailable) {
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Routing provider unavailable");
    }
    if (body == null) throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing response");
    var problem = providerProblem(Objects.toString(body.get("code"), ""));
    if (problem != null) throw problem;
    if (!"Ok".equals(body.get("code")) || !(body.get("routes") instanceof List<?> routes))
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing response");
    if (routes.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No driving route available");
    if (!(routes.getFirst() instanceof Map<?, ?> route))
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing response");
    if (!(route.get("geometry") instanceof Map<?, ?> geometry) || !"LineString".equals(geometry.get("type")) ||
        !(geometry.get("coordinates") instanceof List<?> points) || points.size() < 2)
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing geometry");
    // Never accept a provider silently snapping a GPS point to another country.
    // Validate independently of the requested radiuses and provider metadata.
    checkSnap(points.getFirst(), a, b);
    checkSnap(points.getLast(), c, d);
    if (points.size() > 50000)
      throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Route geometry exceeds supported size");
    if (body.get("waypoints") instanceof List<?> waypoints && waypoints.size() == 2) {
      if (waypoints.getFirst() instanceof Map<?, ?> first) checkSnap(first.get("location"), a, b);
      if (waypoints.getLast() instanceof Map<?, ?> last) checkSnap(last.get("location"), c, d);
    }
    for (Object item : points) {
      if (!(item instanceof List<?> point) || point.size() < 2 ||
          !(point.get(0) instanceof Number lon) || !(point.get(1) instanceof Number lat) ||
          !Double.isFinite(lat.doubleValue()) || !Double.isFinite(lon.doubleValue()) ||
          Math.abs(lat.doubleValue()) > 90 || Math.abs(lon.doubleValue()) > 180)
        throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing coordinates");
    }
    double distance = measure(route.get("distance")), seconds = measure(route.get("duration"));
    return Map.of("coordinates", points, "distanceMeters", distance, "durationSeconds", seconds,
        "mode", "driving", "source", demo ? "OSRM public demo · © OpenStreetMap contributors" : "OSRM", "demo", demo, "estimate", true, "trafficAware", false,
        "updatedAt", Instant.now());
  }
  private void checkSnap(Object coordinate, double requestedLat, double requestedLon) {
    if (!(coordinate instanceof List<?> point) || point.size() < 2 ||
        !(point.get(0) instanceof Number lon) || !(point.get(1) instanceof Number lat) ||
        !Double.isFinite(lat.doubleValue()) || !Double.isFinite(lon.doubleValue()) ||
        Math.abs(lat.doubleValue()) > 90 || Math.abs(lon.doubleValue()) > 180)
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing waypoint");
    double latitude = Math.toRadians(lat.doubleValue() - requestedLat);
    double longitude = Math.toRadians(lon.doubleValue() - requestedLon);
    double haversine = Math.pow(Math.sin(latitude / 2), 2) +
        Math.cos(Math.toRadians(requestedLat)) * Math.cos(Math.toRadians(lat.doubleValue())) * Math.pow(Math.sin(longitude / 2), 2);
    double distance = 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, haversine))));
    if (distance > MAX_ROAD_SNAP_METERS)
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No road segment within 1 km of the selected location");
  }
  private ResponseStatusException providerProblem(String code) {
    return switch (code) {
      case "NoRoute", "NoSegment" -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No driving route connects these points");
      case "TooBig" -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "This route exceeds the routing provider limits");
      case "InvalidQuery", "InvalidValue", "InvalidOptions", "InvalidUrl" -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "The routing provider rejected these route options");
      default -> null;
    };
  }
  private double coordinate(Map<String, String> input, String name, int bound) {
    try {
      double value = Double.parseDouble(input.getOrDefault(name, ""));
      if (!Double.isFinite(value) || Math.abs(value) > bound) throw new NumberFormatException();
      return value;
    } catch (NumberFormatException invalid) { throw new IllegalArgumentException("Invalid route coordinate"); }
  }
  private double measure(Object value) {
    if (!(value instanceof Number n) || !Double.isFinite(n.doubleValue()) || n.doubleValue() < 0)
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing estimate");
    return n.doubleValue();
  }
}
