package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;

import jakarta.validation.Validation;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;

class GuideValidationTest {
  @Test
  void rejectsEmptyAndInvalidCoordinates() {
    try (var f = Validation.buildDefaultValidatorFactory()) {
      var v = f.getValidator();
      assertFalse(
          v.validate(new GuideProvider.Result(List.of(), "source", Instant.now(), true)).isEmpty());
      var stop =
          new GuideProvider.Stop(
              "Test", Instant.now(), Instant.now().plusSeconds(10), 100, 0, "provider");
      assertFalse(
          v.validate(new GuideProvider.Result(List.of(stop), "source", Instant.now(), true))
              .isEmpty());
    }
  }

  @Test
  void devAdapterClearlyLabelsUncertainty() {
    var p = new GuideAdapters().mock();
    assertEquals(true, p.perform("vision", Map.of()).get("mock"));
    assertEquals(true, p.perform("reservation", Map.of()).get("requiresConfirmation"));
  }

  @Test
  void productionFailsWithoutCredentials() {
    assertThrows(IllegalStateException.class, () -> new GuideAdapters().live("", ""));
  }

  @Test
  void rejectsInvalidStructuredVisionTranslationAndReceipt() {
    assertThrows(
        IllegalArgumentException.class,
        () -> GuideResponseValidation.validate("translation", Map.of("text", "")));
    assertThrows(
        IllegalArgumentException.class,
        () ->
            GuideResponseValidation.validate(
                "vision",
                Map.of(
                    "possibleLandmarks",
                    List.of(Map.of("name", "Test", "confidence", 2)),
                    "explanation",
                    "Uncertain",
                    "extractedText",
                    "")));
    assertThrows(
        IllegalArgumentException.class,
        () ->
            GuideResponseValidation.validate(
                "receipt", Map.of("amount", "NaN", "currency", "USD")));
  }
}
