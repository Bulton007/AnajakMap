package com.anajakmap.trip;

import com.anajakmap.platform.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/trips")
public class TripApi {
  @org.springframework.beans.factory.annotation.Autowired private TripCache cache;
  private final Trips trips;
  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final String serviceToken;

  public TripApi(Trips t, JdbcTemplate j, Changes c, @Value("${anajak.service-token}") String st) {
    trips = t;
    jdbc = j;
    changes = c;
    serviceToken = st;
  }

  public record Create(
      @NotBlank @Size(max = 200) String title,
      @NotBlank @Size(max = 200) String destination,
      @NotBlank String timezone,
      @NotNull LocalDate startDate,
      @NotNull LocalDate endDate) {}

  public record Activity(
      @NotBlank @Size(max = 200) String title,
      @NotNull Instant startsAt,
      @NotNull Instant endsAt,
      @DecimalMin("-90") @DecimalMax("90") double latitude,
      @DecimalMin("-180") @DecimalMax("180") double longitude,
      @NotBlank String source) {}

  public record Draft(
      @NotEmpty @Size(max = 100) List<@Valid Activity> activities, @NotBlank String source) {}

  public record Approve(@NotBlank String itineraryId, long version, Long baseVersion) {}

  public record Invite(
      @NotBlank String accountId, @Pattern(regexp = "EDITOR|VIEWER") String role) {}

  public record Vote(@NotBlank String activityId, @Min(-1) @Max(1) int value) {}

  public record Sync(long baseVersion, @Valid @NotNull Create trip) {}

  public Trip require(String id, String actor, boolean edit) {
    Trip t = trips.findById(id).orElseThrow(Api::missing);
    if (t.ownerId.equals(actor)) return t;
    var roles =
        jdbc.queryForList(
            "SELECT role FROM trip_members WHERE trip_id=? AND account_id=? AND accepted=1",
            String.class,
            id,
            actor);
    if (roles.isEmpty() || (edit && !roles.contains("EDITOR"))) throw Api.denied();
    return t;
  }

  @GetMapping("/{id}/access")
  public Map<String, String> access(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam(defaultValue = "false") boolean edit) {
    require(id, jwt.getSubject(), edit);
    return Map.of("allowed", "true");
  }

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Object create(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Create r) {
    var prior = changes.prior(jwt.getSubject(), key, "trip.create", r);
    if (prior.isPresent()) return parse(prior.get());
    validate(r);
    Trip t = new Trip();
    t.id = UUID.randomUUID().toString();
    t.ownerId = jwt.getSubject();
    apply(t, r);
    trips.saveAndFlush(t);
    changes.record(jwt.getSubject(), "trip.created", t.id, Map.of("version", t.version));
    changes.remember(jwt.getSubject(), key, "trip.create", r, t);
    return t;
  }

  private Object parse(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Map.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  private void validate(Create r) {
    ZoneId.of(r.timezone);
    if (r.endDate.isBefore(r.startDate) || r.endDate.isAfter(r.startDate.plusDays(365)))
      throw new IllegalArgumentException("Invalid dates");
  }

  private void apply(Trip t, Create r) {
    t.title = r.title;
    t.destination = r.destination;
    t.timezone = r.timezone;
    t.startDate = r.startDate;
    t.endDate = r.endDate;
  }

  @GetMapping("/{id}")
  public Trip get(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    return require(id, jwt.getSubject(), false);
  }

  @GetMapping
  public List<Trip> list(
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam(defaultValue = "0") int page,
      @RequestParam(defaultValue = "20") int size) {
    if (page < 0 || size < 1 || size > 100) throw new IllegalArgumentException();
    var ids =
        jdbc.queryForList(
            "SELECT id FROM trips WHERE owner_id=? OR id IN(SELECT trip_id FROM trip_members WHERE"
                + " account_id=? AND accepted=1) ORDER BY created_at DESC OFFSET ? ROWS FETCH NEXT"
                + " ? ROWS ONLY",
            String.class,
            jwt.getSubject(),
            jwt.getSubject(),
            page * size,
            size);
    return trips.findAllById(ids);
  }

  @PutMapping("/{id}/sync")
  @Transactional
  public Trip sync(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Sync r) {
    jdbc.queryForList("SELECT id FROM trips WHERE id=? FOR UPDATE", id);
    var t = require(id, jwt.getSubject(), true);
    if (t.version != r.baseVersion) throw Api.conflict();
    validate(r.trip);
    long previous = t.version;
    apply(t, r.trip);
    trips.flush();
    cache.invalidateAfterCommit(id, previous);
    changes.record(jwt.getSubject(), "trip.synced", id, Map.of("version", t.version));
    return t;
  }

  @PostMapping("/{id}/itineraries")
  @ResponseStatus(HttpStatus.CREATED)
  @Transactional
  public Map<String, Object> draft(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Draft r) {
    Trip t = require(id, jwt.getSubject(), true);
    var prior = changes.prior(jwt.getSubject(), key, "draft:" + id, r);
    if (prior.isPresent()) return (Map<String, Object>) parse(prior.get());
    validateActivities(t, r.activities);
    String itinerary = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO itinerary_versions(id,trip_id,status,source) VALUES(?,?,'DRAFT',?)",
        itinerary,
        id,
        r.source);
    int n = 0;
    for (var a : r.activities)
      jdbc.update(
          "INSERT INTO"
              + " activities(id,itinerary_id,sequence_no,title,starts_at,ends_at,latitude,longitude,source)"
              + " VALUES(?,?,?,?,?,?,?,?,?)",
          UUID.randomUUID().toString(),
          itinerary,
          n++,
          a.title,
          java.sql.Timestamp.from(a.startsAt),
          java.sql.Timestamp.from(a.endsAt),
          a.latitude,
          a.longitude,
          a.source);
    var result = Map.<String, Object>of("itineraryId", itinerary, "status", "DRAFT", "version", 0);
    changes.record(jwt.getSubject(), "itinerary.drafted", itinerary, Map.of("tripId", id));
    changes.remember(jwt.getSubject(), key, "draft:" + id, r, result);
    return result;
  }

  private void validateActivities(Trip t, List<Activity> activities) {
    Instant last = null;
    for (var a : activities) {
      if (!a.endsAt.isAfter(a.startsAt) || (last != null && a.startsAt.isBefore(last)))
        throw new IllegalArgumentException("Overlapping activities");
      LocalDate day = a.startsAt.atZone(ZoneId.of(t.timezone)).toLocalDate();
      if (day.isBefore(t.startDate) || day.isAfter(t.endDate))
        throw new IllegalArgumentException("Activity outside trip");
      last = a.endsAt;
    }
  }

  @PostMapping("/{id}/itineraries/approve")
  @Transactional
  public Map<String, Object> approve(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Approve r) {
    jdbc.queryForList("SELECT id FROM trips WHERE id=? FOR UPDATE", id);
    Trip t = require(id, jwt.getSubject(), true);
    if (r.baseVersion != null && r.baseVersion != t.version) throw Api.conflict();
    int changed =
        jdbc.update(
            "UPDATE itinerary_versions SET status='APPROVED',version=version+1 WHERE id=? AND"
                + " trip_id=? AND status='DRAFT' AND version=?",
            r.itineraryId,
            id,
            r.version);
    if (changed != 1) throw Api.conflict();
    jdbc.update(
        "UPDATE itinerary_versions SET status='SUPERSEDED',version=version+1 WHERE trip_id=? AND"
            + " id<>? AND status='APPROVED'",
        id,
        r.itineraryId);
    cache.invalidateAfterCommit(id, t.version);
    jdbc.update("UPDATE trips SET version=version+1 WHERE id=?", id);
    changes.record(jwt.getSubject(), "itinerary.approved", r.itineraryId, Map.of("tripId", id));
    return Map.of("itineraryId", r.itineraryId, "status", "APPROVED", "version", r.version + 1);
  }

  @GetMapping("/{id}/calendar")
  public Map<String, Object> calendar(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    var t = require(id, jwt.getSubject(), false);
    return cache.calendar(
        id,
        t.version,
        () ->
            Map.of(
                "timezone",
                t.timezone,
                "activities",
                jdbc.queryForList(
                    "SELECT a.id,a.title,a.starts_at,a.ends_at,a.latitude,a.longitude,a.source FROM"
                        + " activities a JOIN itinerary_versions i ON i.id=a.itinerary_id WHERE"
                        + " i.trip_id=? AND i.status='APPROVED' ORDER BY a.starts_at",
                    id),
                "events",
                jdbc.queryForList(
                    "SELECT id,title,starts_at,ends_at,timezone FROM calendar_events WHERE"
                        + " trip_id=? ORDER BY starts_at",
                    id)));
  }

  @GetMapping("/{id}/map")
  public Object map(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), false);
    return jdbc.queryForList(
        "SELECT a.id,a.title,a.latitude,a.longitude,a.source FROM activities a JOIN"
            + " itinerary_versions i ON i.id=a.itinerary_id WHERE i.trip_id=? AND"
            + " i.status='APPROVED' ORDER BY a.sequence_no",
        id);
  }

  @GetMapping("/{id}/offline")
  public Map<String, Object> offline(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    var t = require(id, jwt.getSubject(), false);
    return Map.of(
        "trip",
        t,
        "calendar",
        calendar(id, jwt),
        "map",
        map(id, jwt),
        "version",
        t.version,
        "contacts",
        jdbc.queryForList("SELECT label,phone FROM essential_contacts WHERE trip_id=?", id));
  }

  @PostMapping("/{id}/invitations")
  @Transactional
  public Map<String, String> invite(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Invite r) {
    var t = require(id, jwt.getSubject(), true);
    if (!t.ownerId.equals(jwt.getSubject()) || r.accountId.equals(t.ownerId)) throw Api.denied();
    jdbc.update(
        "INSERT INTO trip_members(trip_id,account_id,role,accepted) VALUES(?,?,?,0)",
        id,
        r.accountId,
        r.role);
    changes.record(
        jwt.getSubject(), "group.invited", id, Map.of("accountId", r.accountId, "role", r.role));
    return Map.of("status", "INVITED");
  }

  @PostMapping("/{id}/invitations/accept")
  @Transactional
  public Map<String, String> accept(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    if (jdbc.update(
            "UPDATE trip_members SET accepted=1 WHERE trip_id=? AND account_id=? AND accepted=0",
            id,
            jwt.getSubject())
        != 1) throw Api.missing();
    changes.record(jwt.getSubject(), "group.joined", id, Map.of());
    return Map.of("status", "JOINED");
  }

  @PostMapping("/{id}/votes")
  @Transactional
  public Map<String, Integer> vote(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Vote r) {
    require(id, jwt.getSubject(), false);
    if (jdbc.queryForObject(
            "SELECT COUNT(*) FROM activities a JOIN itinerary_versions i ON i.id=a.itinerary_id"
                + " WHERE a.id=? AND i.trip_id=?",
            Integer.class,
            r.activityId,
            id)
        == 0) throw Api.missing();
    jdbc.update(
        "DELETE FROM activity_votes WHERE activity_id=? AND account_id=?",
        r.activityId,
        jwt.getSubject());
    jdbc.update(
        "INSERT INTO activity_votes(activity_id,account_id,vote_value) VALUES(?,?,?)",
        r.activityId,
        jwt.getSubject(),
        r.value);
    changes.record(jwt.getSubject(), "activity.voted", r.activityId, Map.of("value", r.value));
    return Map.of("value", r.value);
  }

  public record Event(
      @NotBlank @Size(max = 200) String title,
      @NotNull Instant startsAt,
      @NotNull Instant endsAt,
      @NotBlank String timezone) {}

  @PostMapping("/{id}/calendar/events")
  @Transactional
  public Object event(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Event r) {
    jdbc.queryForList("SELECT id FROM trips WHERE id=? FOR UPDATE", id);
    Trip before = require(id, jwt.getSubject(), true);
    cache.invalidateAfterCommit(id, before.version);
    ZoneId.of(r.timezone);
    if (!r.endsAt.isAfter(r.startsAt)) throw new IllegalArgumentException();
    int conflicts =
        jdbc.queryForObject(
            "SELECT COUNT(*) FROM calendar_events WHERE trip_id=? AND starts_at<? AND ends_at>?",
            Integer.class,
            id,
            java.sql.Timestamp.from(r.endsAt),
            java.sql.Timestamp.from(r.startsAt));
    conflicts +=
        jdbc.queryForObject(
            "SELECT COUNT(*) FROM activities a JOIN itinerary_versions i ON i.id=a.itinerary_id"
                + " WHERE i.trip_id=? AND i.status='APPROVED' AND a.starts_at<? AND a.ends_at>?",
            Integer.class,
            id,
            java.sql.Timestamp.from(r.endsAt),
            java.sql.Timestamp.from(r.startsAt));
    if (conflicts > 0) throw Api.conflict();
    String event = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO calendar_events(id,trip_id,title,starts_at,ends_at,timezone)"
            + " VALUES(?,?,?,?,?,?)",
        event,
        id,
        r.title,
        java.sql.Timestamp.from(r.startsAt),
        java.sql.Timestamp.from(r.endsAt),
        r.timezone);
    jdbc.update("UPDATE trips SET version=version+1 WHERE id=?", id);
    changes.record(jwt.getSubject(), "calendar.event-created", event, Map.of("tripId", id));
    return Map.of("id", event);
  }

  public record Contact(
      @NotBlank @Size(max = 100) String label, @NotBlank @Size(max = 50) String phone) {}

  @PostMapping("/{id}/contacts")
  @Transactional
  public Object contact(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Contact r) {
    require(id, jwt.getSubject(), true);
    String c = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO essential_contacts(id,trip_id,label,phone) VALUES(?,?,?,?)",
        c,
        id,
        r.label,
        r.phone);
    jdbc.update("UPDATE trips SET version=version+1 WHERE id=?", id);
    changes.record(jwt.getSubject(), "contact.created", c, Map.of("tripId", id));
    return Map.of("id", c);
  }

  public record Location(
      boolean enabled,
      @DecimalMin("-90") @DecimalMax("90") double latitude,
      @DecimalMin("-180") @DecimalMax("180") double longitude) {}

  @PutMapping("/{id}/location")
  @Transactional
  public Object location(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Location r) {
    require(id, jwt.getSubject(), false);
    jdbc.update(
        "DELETE FROM shared_locations WHERE trip_id=? AND account_id=?", id, jwt.getSubject());
    if (r.enabled)
      jdbc.update(
          "INSERT INTO shared_locations(trip_id,account_id,latitude,longitude,expires_at)"
              + " VALUES(?,?,?,?,CURRENT_TIMESTAMP+NUMTODSINTERVAL(300,'SECOND'))",
          id,
          jwt.getSubject(),
          r.latitude,
          r.longitude);
    changes.record(jwt.getSubject(), "location.consent-changed", id, Map.of("enabled", r.enabled));
    return Map.of("enabled", r.enabled);
  }

  @GetMapping("/{id}/locations")
  public Object locations(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), false);
    return jdbc.queryForList(
        "SELECT account_id,latitude,longitude,expires_at FROM shared_locations WHERE trip_id=? AND"
            + " expires_at>CURRENT_TIMESTAMP",
        id);
  }

  public record Proposal(
      @NotBlank @Size(max = 500) String reason,
      @Valid @NotNull Draft itinerary,
      long baseVersion) {}

  @PostMapping("/{id}/replanning-proposals")
  @Transactional
  public Object proposal(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Proposal r) {
    jdbc.queryForList("SELECT id FROM trips WHERE id=? FOR UPDATE", id);
    Trip t = require(id, jwt.getSubject(), true);
    var prior = changes.prior(jwt.getSubject(), key, "replan:" + id, r);
    if (prior.isPresent()) return parse(prior.get());
    if (t.version != r.baseVersion) throw Api.conflict();
    var draft = draft(id, jwt, key, r.itinerary);
    String proposal = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO replanning_proposals(id,trip_id,itinerary_id,reason,base_version,status)"
            + " VALUES(?,?,?,?,?,'PROPOSED')",
        proposal,
        id,
        draft.get("itineraryId"),
        r.reason,
        r.baseVersion);
    changes.record(jwt.getSubject(), "replan.proposed", proposal, Map.of("tripId", id));
    var response = Map.of("proposalId", proposal, "status", "PROPOSED");
    changes.remember(jwt.getSubject(), key, "replan:" + id, r, response);
    return response;
  }

  @PostMapping("/{id}/replanning-proposals/{proposalId}/approve")
  @Transactional
  public Object applyProposal(
      @PathVariable String id, @PathVariable String proposalId, @AuthenticationPrincipal Jwt jwt) {
    jdbc.queryForList("SELECT id FROM trips WHERE id=? FOR UPDATE", id);
    Trip t = require(id, jwt.getSubject(), true);
    var rows =
        jdbc.queryForList(
            "SELECT itinerary_id,base_version FROM replanning_proposals WHERE id=? AND trip_id=?"
                + " AND status='PROPOSED' FOR UPDATE",
            proposalId,
            id);
    if (rows.isEmpty()) throw Api.conflict();
    var r = rows.getFirst();
    if (t.version != ((Number) r.get("BASE_VERSION")).longValue()) throw Api.conflict();
    Object result = approve(id, jwt, new Approve(r.get("ITINERARY_ID").toString(), 0, null));
    jdbc.update("UPDATE replanning_proposals SET status='APPLIED' WHERE id=?", proposalId);
    changes.record(jwt.getSubject(), "replan.applied", proposalId, Map.of("tripId", id));
    return result;
  }

  @DeleteMapping("/{id}/members/{member}")
  @Transactional
  public void removeMember(
      @PathVariable String id, @PathVariable String member, @AuthenticationPrincipal Jwt jwt) {
    Trip t = require(id, jwt.getSubject(), true);
    if (!t.ownerId.equals(jwt.getSubject())) throw Api.denied();
    jdbc.update("DELETE FROM trip_members WHERE trip_id=? AND account_id=?", id, member);
    jdbc.update("DELETE FROM shared_locations WHERE trip_id=? AND account_id=?", id, member);
    changes.record(jwt.getSubject(), "group.member-removed", id, Map.of("accountId", member));
  }

  @GetMapping("/{id}/members")
  public Object members(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    Trip t = require(id, jwt.getSubject(), false);
    var rows =
        new ArrayList<Map<String, Object>>(
            jdbc.queryForList(
                "SELECT account_id,role FROM trip_members WHERE trip_id=? AND accepted=1", id));
    rows.add(Map.of("ACCOUNT_ID", t.ownerId, "ROLE", "OWNER"));
    return rows;
  }

  @GetMapping("/{id}/replanning-proposals")
  public Object proposals(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), false);
    return jdbc.queryForList(
        "SELECT id,itinerary_id,reason,base_version,status FROM replanning_proposals WHERE"
            + " trip_id=? ORDER BY created_at",
        id);
  }

  @PostMapping("/{id}/replanning-proposals/{proposalId}/reject")
  @Transactional
  public Object reject(
      @PathVariable String id, @PathVariable String proposalId, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), true);
    if (jdbc.update(
            "UPDATE replanning_proposals SET status='REJECTED' WHERE id=? AND trip_id=? AND"
                + " status='PROPOSED'",
            proposalId,
            id)
        != 1) throw Api.conflict();
    changes.record(jwt.getSubject(), "replan.rejected", proposalId, Map.of("tripId", id));
    return Map.of("status", "REJECTED");
  }

  public record EditDraft(@Valid @NotNull Draft itinerary, long version) {}

  @PutMapping("/{id}/itineraries/{itineraryId}")
  @Transactional
  public Object editItinerary(
      @PathVariable String id,
      @PathVariable String itineraryId,
      @AuthenticationPrincipal Jwt jwt,
      @Valid @RequestBody EditDraft r) {
    Trip t = require(id, jwt.getSubject(), true);
    validateActivities(t, r.itinerary.activities);
    if (jdbc.update(
            "UPDATE itinerary_versions SET source=?,version=version+1 WHERE id=? AND trip_id=? AND"
                + " status='DRAFT' AND version=?",
            r.itinerary.source,
            itineraryId,
            id,
            r.version)
        != 1) throw Api.conflict();
    jdbc.update(
        "DELETE FROM activity_votes WHERE activity_id IN(SELECT id FROM activities WHERE"
            + " itinerary_id=?)",
        itineraryId);
    jdbc.update("DELETE FROM activities WHERE itinerary_id=?", itineraryId);
    int n = 0;
    for (var a : r.itinerary.activities)
      jdbc.update(
          "INSERT INTO"
              + " activities(id,itinerary_id,sequence_no,title,starts_at,ends_at,latitude,longitude,source)"
              + " VALUES(?,?,?,?,?,?,?,?,?)",
          UUID.randomUUID().toString(),
          itineraryId,
          n++,
          a.title,
          java.sql.Timestamp.from(a.startsAt),
          java.sql.Timestamp.from(a.endsAt),
          a.latitude,
          a.longitude,
          a.source);
    changes.record(
        jwt.getSubject(), "itinerary.edited", itineraryId, Map.of("version", r.version + 1));
    return Map.of("itineraryId", itineraryId, "status", "DRAFT", "version", r.version + 1);
  }

  @GetMapping("/{id}/itineraries")
  public Object itineraries(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), false);
    return jdbc.queryForList(
        "SELECT id,status,source,version,created_at FROM itinerary_versions WHERE trip_id=? ORDER"
            + " BY created_at DESC",
        id);
  }

  @GetMapping("/{id}/itineraries/{itineraryId}")
  public Object itinerary(
      @PathVariable String id, @PathVariable String itineraryId, @AuthenticationPrincipal Jwt jwt) {
    require(id, jwt.getSubject(), false);
    var rows =
        jdbc.queryForList(
            "SELECT id,status,source,version FROM itinerary_versions WHERE id=? AND trip_id=?",
            itineraryId,
            id);
    if (rows.isEmpty()) throw Api.missing();
    return Map.of(
        "itinerary",
        rows.getFirst(),
        "activities",
        jdbc.queryForList(
            "SELECT id,title,starts_at,ends_at,latitude,longitude,source FROM activities WHERE"
                + " itinerary_id=? ORDER BY sequence_no",
            itineraryId));
  }
}
