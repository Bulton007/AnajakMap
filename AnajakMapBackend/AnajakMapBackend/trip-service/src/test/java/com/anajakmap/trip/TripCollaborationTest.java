package com.anajakmap.trip;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.anajakmap.platform.Changes;
import com.anajakmap.platform.RateLimit;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.server.ResponseStatusException;

class TripCollaborationTest {
  private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
  private final Trips trips = mock(Trips.class);
  private final TripApi api = new TripApi(trips, jdbc, mock(Changes.class), "service-token");

  @Test
  void inviteInboxIsScopedToRecipientAndChatRequiresAcceptance() {
    Trip trip = new Trip();
    trip.id = "trip";
    trip.ownerId = "owner";
    trip.title = "Test trip";
    when(trips.findById("trip")).thenReturn(Optional.of(trip));
    when(jdbc.queryForList(anyString(), eq("recipient"))).thenReturn(List.of(Map.of("TRIP_ID", "trip")));
    when(jdbc.queryForList(anyString(), eq("other"))).thenReturn(List.of());
    when(jdbc.queryForList(anyString(), eq(String.class), eq("trip"), eq("recipient")))
        .thenReturn(List.of(), List.of("VIEWER"));
    when(jdbc.queryForList(contains("SELECT invitation_status"), eq(String.class), eq("trip"),
        eq("recipient"))).thenReturn(List.of("PENDING"), List.of("ACCEPTED"));

    assertEquals(List.of(Map.of("TRIP_ID", "trip")), api.invitations(jwt("recipient")));
    assertEquals(List.of(), api.invitations(jwt("other")));

    var chat = new TripChatApi(api, jdbc, mock(StringRedisTemplate.class), mock(RateLimit.class));
    assertThrows(ResponseStatusException.class, () -> chat.history("trip", jwt("recipient"), 0));
    assertEquals(Map.of("status", "JOINED"), api.accept("trip", jwt("recipient")));
    assertEquals(Map.of("status", "JOINED"), api.accept("trip", jwt("recipient")));
    verify(jdbc, times(1)).update(contains("SET invitation_status"), eq("ACCEPTED"), eq(1),
        eq("trip"), eq("recipient"));
    assertDoesNotThrow(() -> chat.history("trip", jwt("recipient"), 0));
    assertThrows(ResponseStatusException.class, () -> chat.history("trip", jwt("other"), 0));
  }

  private static Jwt jwt(String subject) {
    return Jwt.withTokenValue("test").header("alg", "none").subject(subject).build();
  }
}
