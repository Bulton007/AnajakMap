package com.anajakmap.discovery;

import com.anajakmap.platform.*;
import jakarta.validation.*;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/discovery/journeys")
public class JourneyApi {
  private final JdbcTemplate jdbc;
  private final TripAccess access;
  private final Changes changes;
  private final TransactionTemplate tx;

  public JourneyApi(JdbcTemplate j, TripAccess a, Changes c, PlatformTransactionManager t) {
    jdbc = j;
    access = a;
    changes = c;
    tx = new TransactionTemplate(t);
  }

  public record Leg(
      @NotBlank String tripId,
      @NotBlank @Size(max = 200) String origin,
      @NotBlank @Size(max = 200) String destination,
      @NotNull Instant departure,
      @NotNull Instant arrival,
      @NotBlank String timezone,
      @NotBlank @Size(max = 1000) String transferDetails,
      @NotBlank @Size(max = 500) String source) {}

  @PostMapping
  public Object save(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @Valid @RequestBody Leg r) {
    access.require(r.tripId, bearer, true);
    ZoneId.of(r.timezone);
    if (!r.arrival.isAfter(r.departure)) throw new IllegalArgumentException();
    return tx.execute(
        s -> {
          String id = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO"
                  + " journey_legs(id,trip_id,origin,destination,departure,arrival,timezone,transfer_details,source)"
                  + " VALUES(?,?,?,?,?,?,?,?,?)",
              id,
              r.tripId,
              r.origin,
              r.destination,
              java.sql.Timestamp.from(r.departure),
              java.sql.Timestamp.from(r.arrival),
              r.timezone,
              r.transferDetails,
              r.source);
          changes.record(jwt.getSubject(), "journey.saved", id, Map.of("tripId", r.tripId));
          return Map.of("id", id);
        });
  }

  @GetMapping
  public Object legs(@RequestHeader("Authorization") String bearer, @RequestParam String tripId) {
    access.require(tripId, bearer, false);
    return jdbc.queryForList(
        "SELECT id,origin,destination,departure,arrival,timezone,transfer_details,source FROM"
            + " journey_legs WHERE trip_id=? ORDER BY departure",
        tripId);
  }
}
