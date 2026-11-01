package com.anajakmap.aiguide;

import java.time.*;
import java.util.*;

/** Applies private calendar constraints inside our backend, never at an AI provider. */
final class ItineraryConstraints {
  private ItineraryConstraints() {}
  private record Block(Instant start, Instant end) {}

  static List<GuideProvider.Stop> fit(List<GuideProvider.Stop> proposed, Object calendar, Instant latest) {
    if (!(calendar instanceof Map<?,?> data) || !(data.get("events") instanceof List<?> events))
      throw new IllegalArgumentException("Missing calendar constraints");
    if (events.size() > 100) throw new IllegalArgumentException("Too many calendar events");
    var blocks = new ArrayList<Block>();
    for (Object value : events) {
      if (!(value instanceof Map<?,?> event)) throw new IllegalArgumentException("Invalid calendar event");
      var start = instant(event.containsKey("startsAt") ? event.get("startsAt") : event.get("STARTS_AT"));
      var end = instant(event.containsKey("endsAt") ? event.get("endsAt") : event.get("ENDS_AT"));
      if (!end.isAfter(start)) throw new IllegalArgumentException("Invalid calendar timing");
      blocks.add(new Block(start, end));
    }
    blocks.sort(Comparator.comparing(Block::start));
    var result = new ArrayList<GuideProvider.Stop>();
    Instant previousEnd = Instant.MIN;
    for (var stop : proposed) {
      var duration = Duration.between(stop.startsAt(), stop.endsAt());
      Instant start = stop.startsAt().isBefore(previousEnd) ? previousEnd : stop.startsAt();
      Instant end = start.plus(duration);
      for (var block : blocks) {
        if (start.isBefore(block.end()) && end.isAfter(block.start())) {
          start = block.end();
          end = start.plus(duration);
        }
      }
      if (end.isAfter(latest)) continue;
      result.add(new GuideProvider.Stop(stop.title(), start, end, stop.latitude(), stop.longitude(), stop.source()));
      previousEnd = end;
    }
    if (result.isEmpty()) throw new IllegalArgumentException("No activities fit around calendar events within trip dates");
    return result;
  }

  private static Instant instant(Object value) {
    if (value instanceof Number number) return Instant.ofEpochMilli(number.longValue());
    return Instant.parse(Objects.toString(value, ""));
  }
}
