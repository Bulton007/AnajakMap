package com.anajakmap.aiguide;

import com.anajakmap.platform.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.web.client.RestClient;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

@Configuration
public class GuideAdapters {
  @Bean
  @ConditionalOnProperty(name = "AI_PROVIDER", havingValue = "gemini")
  GuideProvider gemini(@Value("${GEMINI_API_KEY:}") String key,
      @Value("${GEMINI_MODEL:gemini-3.8-flash}") String model) {
    return new GeminiGuideProvider(key, model,
        HttpClients.client("https://generativelanguage.googleapis.com", Duration.ofSeconds(45)));
  }

  @Bean
  @Profile({"dev", "test"})
  @ConditionalOnProperty(name = "AI_PROVIDER", havingValue = "fixture", matchIfMissing = true)
  GuideProvider mock() {
    return new GuideProvider() {
      public Result itinerary(
          Map<String, Object> t, Map<String, Object> p, List<Map<String, Object>> places) {
        if (places.isEmpty()) throw new IllegalArgumentException("No grounded places");
        Instant start =
            LocalDate.parse(t.get("startDate").toString())
                .atTime(9, 0)
                .atZone(ZoneId.of(t.get("timezone").toString()))
                .toInstant();
        var stops = new ArrayList<Stop>();
        for (int i = 0; i < Math.min(3, places.size()); i++) {
          var x = places.get(i);
          stops.add(
              new Stop(
                  x.get("name").toString(),
                  start.plusSeconds(i * 7200),
                  start.plusSeconds(i * 7200 + 3600),
                  ((Number) x.get("latitude")).doubleValue(),
                  ((Number) x.get("longitude")).doubleValue(),
                  x.get("source").toString()));
        }
        return new Result(stops, "development deterministic AI", Instant.now(), true);
      }

      public Map<String, Object> perform(String op, Map<String, Object> in) {
        return switch (op) {
          case "translation" ->
              Map.of(
                  "text",
                  "[development translation] " + in.get("text"),
                  "targetLanguage",
                  in.getOrDefault("targetLanguage", "en"),
                  "mock",
                  true);
          case "vision" ->
              Map.of(
                  "possibleLandmarks",
                  List.of(Map.of("name", "Unidentified landmark", "confidence", 0.1)),
                  "explanation",
                  "Development fixture; recognition is uncertain",
                  "extractedText",
                  "",
                  "mock",
                  true);
          case "receipt" ->
              Map.of(
                  "amount",
                  "12.50",
                  "currency",
                  "USD",
                  "merchant",
                  "Demo cafe",
                  "requiresConfirmation",
                  true,
                  "mock",
                  true);
          case "reservation" ->
              Map.of(
                  "provider",
                  "Demo reservation",
                  "reference",
                  "DEMO-001",
                  "requiresConfirmation",
                  true,
                  "mock",
                  true);
          case "recap" ->
              Map.of(
                  "text",
                  "Development recap: " + in.getOrDefault("text", "Travel memories"),
                  "editable",
                  true,
                  "mock",
                  true);
          case "voice" ->
              Map.of(
                  "status",
                  "MOCK",
                  "transcript",
                  in.getOrDefault("text", "Development voice transcript"),
                  "mock",
                  true);
          default ->
              Map.of(
                  "text",
                  "Development travel guide: " + in.getOrDefault("text", "How can I help?"),
                  "mock",
                  true);
        };
      }
    };
  }

  @Bean
  @Profile("!dev & !test")
  @ConditionalOnProperty(name = "AI_PROVIDER", havingValue = "adapter", matchIfMissing = true)
  GuideProvider live(
      @Value("${anajak.provider-url}") String url, @Value("${anajak.provider-key}") String key) {
    if (url.isBlank() || key.isBlank())
      throw new IllegalStateException("AI provider URL/key required outside dev/test");
    RestClient c = HttpClients.client(url);
    return new GuideProvider() {
      public Result itinerary(
          Map<String, Object> t, Map<String, Object> p, List<Map<String, Object>> places) {
        return c.post()
            .uri("/itinerary")
            .header("Authorization", "Bearer " + key)
            .body(Map.of("trip", t, "preferences", p, "places", places))
            .retrieve()
            .body(Result.class);
      }

      public Map<String, Object> perform(String op, Map<String, Object> in) {
        return c.post()
            .uri("/" + op)
            .header("Authorization", "Bearer " + key)
            .body(in)
            .retrieve()
            .body(Map.class);
      }
    };
  }
}
