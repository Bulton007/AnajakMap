package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.Test;

class ItineraryConstraintsTest {
  Instant time(String clock) { return Instant.parse("2026-10-24T" + clock + ":00Z"); }
  GuideProvider.Stop stop(String start, String end) {
    return new GuideProvider.Stop("Supplied place", time(start), time(end), 11.5, 104.9, "OpenStreetMap");
  }
  Map<String,Object> calendar(String start, String end) {
    return Map.of("events", List.of(Map.of("STARTS_AT", time(start).toString(), "ENDS_AT", time(end).toString())));
  }
  @Test void movesOverlapAndFollowingStopsPreservingDuration() {
    var result = ItineraryConstraints.fit(List.of(stop("09:00", "10:00"), stop("10:15", "11:15")), calendar("09:30", "11:00"), time("20:00"));
    assertEquals(time("11:00"), result.get(0).startsAt());
    assertEquals(time("12:00"), result.get(0).endsAt());
    assertEquals(time("12:00"), result.get(1).startsAt());
    assertEquals(time("13:00"), result.get(1).endsAt());
  }
  @Test void exactBoundariesDoNotOverlap() {
    var proposed = List.of(stop("09:00", "10:00"), stop("11:00", "12:00"));
    assertEquals(proposed, ItineraryConstraints.fit(proposed, calendar("10:00", "11:00"), time("20:00")));
  }
  @Test void overlappingUnsortedCalendarBlocksCannotCreateAConflict() {
    var events = Map.of("events", List.of(
        Map.of("startsAt",time("11:00").toEpochMilli(),"endsAt",time("12:00").toEpochMilli()),
        Map.of("startsAt",time("09:30").toEpochMilli(),"endsAt",time("11:30").toEpochMilli())));
    assertEquals(time("12:00"), ItineraryConstraints.fit(List.of(stop("09:00","10:00")),events,time("20:00")).getFirst().startsAt());
  }
  @Test void doesNotInventAnActivityOutsideTheTripToClaimSuccess() {
    assertThrows(IllegalArgumentException.class, () -> ItineraryConstraints.fit(List.of(stop("09:00","10:00")), calendar("09:00","20:00"), time("20:00")));
    assertThrows(IllegalArgumentException.class, () -> ItineraryConstraints.fit(List.of(stop("09:00","10:00")), Map.of(), time("20:00")));
  }
}
