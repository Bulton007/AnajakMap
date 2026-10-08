package com.anajakmap.aiguide;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;

public interface GuideProvider {
  record Stop(
      @NotBlank String title,
      @NotNull Instant startsAt,
      @NotNull Instant endsAt,
      @DecimalMin("-90") @DecimalMax("90") double latitude,
      @DecimalMin("-180") @DecimalMax("180") double longitude,
      @NotBlank String source) {}

  record Result(
      @NotEmpty List<@Valid Stop> activities,
      @NotBlank String source,
      @NotNull Instant updatedAt,
      boolean estimate) {}

  Result itinerary(
      Map<String, Object> trip, Map<String, Object> preferences, List<Map<String, Object>> places);

  Map<String, Object> perform(String operation, Map<String, Object> input);
}
