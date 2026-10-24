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

@Component
public class DestinationWeather {
  private final boolean enabled;
  private final PhotonPlaces places;
  private final RestClient client;
  private final Map<String, Cached> cache = new java.util.concurrent.ConcurrentHashMap<>();
  private record Cached(Instant expires, Map<String,Object> data) {}
  @Autowired public DestinationWeather(Environment env, PhotonPlaces places) {
    this(env.getProperty("WEATHER_PROVIDER", "").equals("open-meteo"), places,
        HttpClients.client("https://api.open-meteo.com"));
  }
  DestinationWeather(boolean enabled, PhotonPlaces places, RestClient client) {
    this.enabled = enabled; this.places = places; this.client = client;
  }
  Map<String,Object> weather(Map<String,String> input) {
    if (!enabled) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Configure a real weather provider");
    double latitude, longitude;
    String query = input.getOrDefault("query", "");
    try {
      if (input.containsKey("latitude") && input.containsKey("longitude")) {
        latitude = Double.parseDouble(input.get("latitude")); longitude = Double.parseDouble(input.get("longitude"));
      } else {
        if (!places.enabled() || query.isBlank()) throw new IllegalArgumentException();
        var found = places.search(query, 0, 1);
        if (found.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Destination not found for weather");
        latitude = ((Number)found.getFirst().get("latitude")).doubleValue();
        longitude = ((Number)found.getFirst().get("longitude")).doubleValue();
      }
      if (!Double.isFinite(latitude) || !Double.isFinite(longitude) || Math.abs(latitude)>90 || Math.abs(longitude)>180) throw new IllegalArgumentException();
    } catch (NumberFormatException invalid) { throw new IllegalArgumentException("Invalid weather coordinates"); }
    String key = latitude + "," + longitude;
    Cached prior = cache.get(key);
    if (prior != null && prior.expires.isAfter(Instant.now())) return prior.data;
    Map<?,?> body;
    try {
      body = client.get().uri(b -> b.path("/v1/forecast").queryParam("latitude",latitude)
          .queryParam("longitude",longitude).queryParam("current","temperature_2m,weather_code")
          .queryParam("timezone","UTC").build()).retrieve().body(Map.class);
    } catch (Exception unavailable) {
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,"Weather provider unavailable; no live conditions available");
    }
    if (body == null || !(body.get("current") instanceof Map<?,?> current) ||
        !(current.get("temperature_2m") instanceof Number temperature) || !Double.isFinite(temperature.doubleValue()) ||
        !(current.get("weather_code") instanceof Number code) || !(current.get("time") instanceof String time))
      throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,"Invalid weather response");
    String timestamp = time.endsWith("Z") ? time : time + "Z";
    try { Instant.parse(timestamp.length() == 17 ? timestamp.replace("Z",":00Z") : timestamp); }
    catch (Exception invalid) { throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,"Invalid weather timestamp"); }
    var result = new HashMap<String,Object>();
    result.put("temperatureCelsius",temperature); result.put("weatherCode",code);
    result.put("latitude",latitude); result.put("longitude",longitude);
    result.put("source","Open-Meteo"); result.put("sourceUrl","https://open-meteo.com/");
    result.put("updatedAt",timestamp); result.put("retrievedAt",Instant.now());
    result.put("cacheMinutes",15); result.put("mock",false);
    // Bound memory and scope cache by resolved coordinates, never by a previous query.
    if (cache.size() >= 256) cache.clear();
    cache.put(key,new Cached(Instant.now().plusSeconds(900),Map.copyOf(result)));
    return result;
  }
}
