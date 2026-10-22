package com.anajakmap.discovery;

import com.anajakmap.platform.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/discovery")
public class DiscoveryApi {
  private final boolean dev;
  private final String url, key;
  private final StringRedisTemplate redis;
  private final Changes json;
  private final RateLimit limit;
  private final PhotonPlaces photon;
  private final PlacePhotos photos;

  public DiscoveryApi(
      Environment e,
      @Value("${anajak.provider-url}") String u,
      @Value("${anajak.provider-key}") String k,
      StringRedisTemplate r,
      Changes c,
      RateLimit l, PhotonPlaces photon, PlacePhotos photos) {
    this.photon = photon;
    this.photos = photos;
    dev =
        Arrays.asList(e.getActiveProfiles()).stream()
            .anyMatch(x -> x.equals("dev") || x.equals("test"));
    url = u;
    key = k;
    redis = r;
    json = c;
    limit = l;
    if (!dev && (url.isBlank() || key.isBlank()))
      throw new IllegalStateException("Discovery provider URL/key required outside dev/test");
  }

  @GetMapping("/photos")
  public Object photos(@AuthenticationPrincipal Jwt jwt, @RequestParam String query,
      @RequestParam(defaultValue="0") int page) {
    if(query.isBlank()||query.length()>200||page<0)throw new IllegalArgumentException();
    limit.check("photos:"+jwt.getSubject(),20,60);
    return photon.enabled()?photos.photos(photon.search(query,page,20)):Map.of();
  }

  @GetMapping("/places")
  public Object places(
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam String query,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size) {
    if (query.isBlank() || query.length() > 200 || page < 0 || size < 1 || size > 100)
      throw new IllegalArgumentException();
    limit.check("discovery:" + jwt.getSubject(), 60, 60);
    if (photon.enabled()) return photon.search(query, page, size);
    if (dev)
      return page > 0 ? List.of() : List.of(
          place("Royal Palace", 11.5638, 104.9315),
          place("National Museum", 11.5658, 104.9288),
          place("Wat Phnom", 11.5760, 104.9231)).stream().filter(p -> query.toLowerCase(Locale.ROOT).contains("phnom penh") || p.get("name").toString().toLowerCase(Locale.ROOT).contains(query.strip().toLowerCase(Locale.ROOT))).limit(size).toList();
    return call("places", Map.of("query", query, "page", page, "size", size), false);
  }

  private Map<String, Object> place(String n, double lat, double lon) {
    return Map.of(
        "id",
        Changes.hash(n).substring(0, 16),
        "name",
        n,
        "latitude",
        lat,
        "longitude",
        lon,
        "source",
        "development Phnom Penh fixture",
        "updatedAt",
        Instant.now(),
        "mock",
        true);
  }

  @GetMapping("/nearby")
  public Object nearby(
      @RequestParam double latitude,
      @RequestParam double longitude,
      @RequestParam(defaultValue = "1000") int radius) {
    coordinates(latitude, longitude);
    if (radius < 1 || radius > 50000) throw new IllegalArgumentException();
    return dev
        ? List.of(place("Demo cafe", latitude, longitude))
        : call(
            "nearby",
            Map.of("latitude", latitude, "longitude", longitude, "radius", radius),
            false);
  }

  @GetMapping("/{operation:weather|food|culture|transport|routes}")
  public Object information(
      @PathVariable String operation, @RequestParam Map<String, String> params) {
    if (params.size() > 15 || params.values().stream().anyMatch(v -> v.length() > 200))
      throw new IllegalArgumentException();
    if (dev)
      return switch (operation) {
        case "weather" ->
            Map.of(
                "condition",
                "sunny",
                "temperatureCelsius",
                30,
                "source",
                "development fixture",
                "updatedAt",
                Instant.now(),
                "mock",
                true);
        case "food" ->
            Map.of(
                "dishes",
                List.of("Fish amok", "Nom banh chok"),
                "dietaryGuidance",
                "Confirm ingredients with the restaurant",
                "mock",
                true);
        case "culture" ->
            Map.of(
                "guidance",
                "Dress respectfully at religious sites",
                "source",
                "development fixture",
                "mock",
                true);
        default ->
            Map.of(
                "durationMinutes",
                25,
                "estimatedCost",
                "8.00",
                "currency",
                "USD",
                "estimate",
                true,
                "source",
                "development fixture",
                "updatedAt",
                Instant.now(),
                "mock",
                true);
      };
    return call(operation, params, false);
  }

  private void coordinates(double lat, double lon) {
    if (!Double.isFinite(lat) || !Double.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180)
      throw new IllegalArgumentException();
  }

  private Object call(String op, Object input, boolean cacheAllowed) {
    String cacheKey = "provider:" + op + ":" + Changes.hash(json.json(input));
    if (cacheAllowed) {
      String cached = redis.opsForValue().get(cacheKey);
      if (cached != null) return parse(cached);
    }
    Object response =
        HttpClients.client(url)
            .post()
            .uri("/" + op)
            .header("Authorization", "Bearer " + key)
            .body(input)
            .retrieve()
            .body(Object.class);
    if (response == null) throw new IllegalArgumentException("Empty provider response");
    if (cacheAllowed)
      redis.opsForValue().set(cacheKey, json.json(response), Duration.ofSeconds(60));
    return response;
  }

  private Object parse(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Object.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }
}
