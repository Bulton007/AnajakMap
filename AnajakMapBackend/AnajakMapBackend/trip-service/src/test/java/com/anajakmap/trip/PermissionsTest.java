package com.anajakmap.trip;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.anajakmap.platform.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

class PermissionsTest {
  @Test
  void viewerCannotEditAndOwnerCan() {
    Trips repo = mock(Trips.class);
    JdbcTemplate jdbc = mock(JdbcTemplate.class);
    Trip t = new Trip();
    t.id = "trip";
    t.ownerId = "owner";
    when(repo.findById("trip")).thenReturn(Optional.of(t));
    when(jdbc.queryForList(anyString(), eq(String.class), eq("trip"), eq("viewer")))
        .thenReturn(List.of("VIEWER"));
    var api = new TripApi(repo, jdbc, mock(Changes.class), "test-service-secret");
    assertSame(t, api.require("trip", "owner", true));
    assertSame(t, api.require("trip", "viewer", false));
    assertThrows(
        org.springframework.web.server.ResponseStatusException.class,
        () -> api.require("trip", "viewer", true));
  }
}
