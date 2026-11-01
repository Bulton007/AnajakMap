package com.anajakmap.trip;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Validation;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.List;
import org.junit.jupiter.api.Test;

class TripUnicodeValidationTest {
  private final Instant start = Instant.parse("2026-10-27T02:00:00Z");

  @Test void khmerAndEmojiWithinDeclaredLimitsAreAcceptedWithoutByteLengthRestrictions() {
    try (var factory = Validation.buildDefaultValidatorFactory()) {
      var validator = factory.getValidator();
      String khmer = "ក".repeat(200);
      String emoji = "🌴".repeat(100); // 200 UTF-16 code units, 400 UTF-8 bytes.
      assertTrue(khmer.getBytes(StandardCharsets.UTF_8).length > 200);
      assertTrue(emoji.getBytes(StandardCharsets.UTF_8).length > 200);
      var trip = new TripApi.Create(khmer, emoji, "Asia/Phnom_Penh", LocalDate.of(2026,10,27), LocalDate.of(2026,10,28));
      var activity = new TripApi.Activity(emoji, start, start.plusSeconds(3600), 11.56, 104.92, "ខ".repeat(500));
      assertTrue(validator.validate(trip).isEmpty());
      assertTrue(validator.validate(new TripApi.Draft(List.of(activity), "គ".repeat(500))).isEmpty());
    }
  }

  @Test void overlongSourcesAndTitlesFailValidationBeforeDatabaseWrites() {
    try (var factory = Validation.buildDefaultValidatorFactory()) {
      var validator = factory.getValidator();
      var activity = new TripApi.Activity("ក".repeat(201), start, start.plusSeconds(3600), 11.56, 104.92, "ខ".repeat(501));
      var violations = validator.validate(activity);
      assertTrue(violations.stream().anyMatch(v -> v.getPropertyPath().toString().equals("title")));
      assertTrue(violations.stream().anyMatch(v -> v.getPropertyPath().toString().equals("source")));
      var validActivity = new TripApi.Activity("Temple 🌴", start, start.plusSeconds(3600), 11.56, 104.92, "Manual edit");
      assertFalse(validator.validate(new TripApi.Draft(List.of(validActivity), "🌴".repeat(251))).isEmpty());
    }
  }

  @Test void jsonPreservesKhmerEmojiVariationSelectorsAndJoinedCharacters() throws Exception {
    var mapper = new ObjectMapper();
    String title = "ប្រាសាទ 🏯 🗺️ 👨‍👩‍👧‍👦";
    var decoded = mapper.readValue(mapper.writeValueAsString(java.util.Map.of("title",title)), java.util.Map.class);
    assertEquals(title, decoded.get("title"));
  }
}
