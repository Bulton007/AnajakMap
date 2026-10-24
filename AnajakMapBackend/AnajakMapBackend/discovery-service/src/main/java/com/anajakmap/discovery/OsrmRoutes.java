package com.anajakmap.discovery;

import com.anajakmap.platform.HttpClients;
import java.time.Instant;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

/** Explicitly configured driving router. No fabricated geometry or live traffic. */
@Component
public class OsrmRoutes {
  private final RestClient client;
  @Autowired public OsrmRoutes(Environment environment) {
    String url = environment.getProperty("OSRM_URL", "");
    client = url.isBlank() ? null : HttpClients.client(url);
  }
  OsrmRoutes(RestClient client) { this.client = client; }

  public Map<String, Object> route(Map<String, String> input) {
    double a = coordinate(input, "originLat", 90), b = coordinate(input, "originLon", 180);
    double c = coordinate(input, "destinationLat", 90), d = coordinate(input, "destinationLon", 180);
    if (!input.getOrDefault("mode", "driving").equals("driving"))
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "This router supports driving only");
    if (client == null) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Driving routes require a configured OSRM_URL");
    Map<?, ?> body;
    try {
      body = client.get().uri("/route/v1/driving/{points}?overview=full&geometries=geojson&steps=false",
          b + "," + a + ";" + d + "," + c).retrieve().body(Map.class);
    } catch (Exception unavailable) {
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Routing provider unavailable");
    }
    if (body == null || !"Ok".equals(body.get("code")) || !(body.get("routes") instanceof List<?> routes) || routes.isEmpty())
      throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No driving route available");
    if (!(routes.getFirst() instanceof Map<?, ?> route))
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing response");
    if (!(route.get("geometry") instanceof Map<?, ?> geometry) || !"LineString".equals(geometry.get("type")) ||
        !(geometry.get("coordinates") instanceof List<?> points) || points.size() < 2 || points.size() > 50000)
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing geometry");
    for (Object item : points) {
      if (!(item instanceof List<?> point) || point.size() < 2 ||
          !(point.get(0) instanceof Number lon) || !(point.get(1) instanceof Number lat) ||
          !Double.isFinite(lat.doubleValue()) || !Double.isFinite(lon.doubleValue()) ||
          Math.abs(lat.doubleValue()) > 90 || Math.abs(lon.doubleValue()) > 180)
        throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Invalid routing coordinates");
    }
    double distance = measure(route.get("distance")), seconds = measure(route.get("duration"));
    return Map.of("coordinates", points, "distanceMeters", distance, "durationSeconds", seconds,
        "mode", "driving", "source", "OSRM", "estimate", true, "trafficAware", false,
        "updatedAt", Instant.now());
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
