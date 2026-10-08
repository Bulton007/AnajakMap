package com.anajakmap.aiguide;

import com.anajakmap.platform.*;
import jakarta.validation.*;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/guide")
public class GuideApi {
  private final ObjectStore storage;
  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final GuideProvider provider;
  private final TripAccess access;
  private final String tripUrl, discoveryUrl;
  private final Validator validator;

  public GuideApi(
      ObjectStore storage,
      JdbcTemplate j,
      Changes c,
      GuideProvider p,
      TripAccess a,
      Validator v,
      @Value("${anajak.trip-url}") String t,
      @Value("${anajak.discovery-url}") String d) {
    this.storage = storage;
    jdbc = j;
    changes = c;
    provider = p;
    access = a;
    validator = v;
    tripUrl = t;
    discoveryUrl = d;
  }

  public record Request(@NotBlank String tripId, @NotNull Map<String, Object> preferences) {}

  public record Input(@NotNull @Size(max = 30) Map<String, Object> input) {}

  public record Message(@NotBlank @Size(max = 8000) String text) {}

  @PostMapping("/itinerary-jobs")
  @ResponseStatus(HttpStatus.ACCEPTED)
  public Object generate(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Request r) {
    access.require(r.tripId, bearer, true);
    Map tripEnvelope =
        HttpClients.client(tripUrl)
            .get()
            .uri("/api/v1/trips/{id}", r.tripId)
            .header("Authorization", bearer)
            .retrieve()
            .body(Map.class);
    Map trip = (Map) tripEnvelope.get("data");
    Map placesEnvelope =
        HttpClients.client(discoveryUrl)
            .get()
            .uri("/api/v1/discovery/places?query={q}", trip.get("destination"))
            .header("Authorization", bearer)
            .retrieve()
            .body(Map.class);
    List places = (List) placesEnvelope.get("data");
    return queue(
        jwt.getSubject(),
        key,
        r,
        Map.of("trip", trip, "preferences", r.preferences, "places", places));
  }

  private Object queue(String actor, String key, Request req, Map<String, Object> input) {
    return new org.springframework.transaction.support.TransactionTemplate(txManager)
        .execute(
            s -> {
              var prior = changes.prior(actor, key, "ai.itinerary", req);
              if (prior.isPresent()) return parse(prior.get());
              String id = UUID.randomUUID().toString();
              jdbc.update(
                  "INSERT INTO generation_jobs(id,owner_id,trip_id,status,input_json,trace_id)"
                      + " VALUES(?,?,?,'QUEUED',?,?)",
                  id,
                  actor,
                  req.tripId,
                  changes.json(input),
                  org.slf4j.MDC.get("traceId"));
              var response = Map.of("jobId", id, "status", "QUEUED");
              changes.record(actor, "ai.queued", id, Map.of("tripId", req.tripId));
              changes.remember(actor, key, "ai.itinerary", req, response);
              return response;
            });
  }

  @org.springframework.beans.factory.annotation.Autowired
  private org.springframework.transaction.PlatformTransactionManager txManager;

  private Map parse(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Map.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  @GetMapping("/jobs/{id}")
  public Object job(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    var rows =
        jdbc.queryForList(
            "SELECT id,trip_id,status,error_code FROM generation_jobs WHERE id=? AND owner_id=?",
            id,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.missing();
    String result =
        jdbc.queryForObject("SELECT output_json FROM generation_jobs WHERE id=?", String.class, id);
    return Map.of("job", rows.getFirst(), "result", result == null ? Map.of() : parse(result));
  }

  @PostMapping("/jobs/{id}/save-draft")
  @ResponseStatus(HttpStatus.CREATED)
  public Object save(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id FROM generation_jobs WHERE id=? AND owner_id=? AND status='SUCCEEDED'",
            id,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.conflict();
    String trip = rows.getFirst().get("TRIP_ID").toString();
    access.require(trip, bearer, true);
    Map result =
        parse(
            jdbc.queryForObject(
                "SELECT output_json FROM generation_jobs WHERE id=?", String.class, id));
    Map envelope =
        HttpClients.client(tripUrl)
            .post()
            .uri("/api/v1/trips/{id}/itineraries", trip)
            .header("Authorization", bearer)
            .header("Idempotency-Key", key)
            .body(Map.of("activities", result.get("activities"), "source", result.get("source")))
            .retrieve()
            .body(Map.class);
    return envelope.get("data");
  }

  @PostMapping("/{operation:translation|vision|receipt|reservation|recap|voice}")
  public Object perform(
      @PathVariable String operation,
      @AuthenticationPrincipal Jwt jwt,
      @Valid @RequestBody Input r) {
    if (changes.json(r.input).length()
        > (r.input.containsKey("documentBase64") ? 14 * 1024 * 1024 : 16000))
      throw new IllegalArgumentException();
    Map<String, Object> input = new HashMap<>(r.input);
    if (input.containsKey("mediaId")) {
      var media =
          jdbc.queryForList(
              "SELECT object_key,mime_type FROM guide_media WHERE id=? AND owner_id=?",
              input.get("mediaId"),
              jwt.getSubject());
      if (media.isEmpty()) throw Api.denied();
      input.put(
          "imageBase64",
          Base64.getEncoder()
              .encodeToString(storage.download(media.getFirst().get("OBJECT_KEY").toString())));
      input.put("mimeType", media.getFirst().get("MIME_TYPE"));
    }
    Map<String, Object> result = provider.perform(operation, input);
    if (result == null || changes.json(result).length() > 64000)
      throw new IllegalArgumentException("Invalid provider response");
    GuideResponseValidation.validate(operation, result);
    return result;
  }

  @PostMapping("/conversations")
  @Transactional
  @ResponseStatus(HttpStatus.CREATED)
  public Object conversation(@AuthenticationPrincipal Jwt jwt) {
    String id = UUID.randomUUID().toString();
    jdbc.update("INSERT INTO conversations(id,owner_id) VALUES(?,?)", id, jwt.getSubject());
    changes.record(jwt.getSubject(), "conversation.created", id, Map.of());
    return Map.of("id", id);
  }

  @PostMapping("/conversations/{id}/messages")
  public Object message(
      @PathVariable String id, @AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Message r) {
    if (jdbc.queryForObject(
            "SELECT COUNT(*) FROM conversations WHERE id=? AND owner_id=?",
            Integer.class,
            id,
            jwt.getSubject())
        == 0) throw Api.denied();
    Map reply = provider.perform("chat", Map.of("text", r.text));
    GuideResponseValidation.validate("chat", reply);
    return new org.springframework.transaction.support.TransactionTemplate(txManager)
        .execute(
            s -> {
              String message = UUID.randomUUID().toString();
              jdbc.update(
                  "INSERT INTO guide_messages(id,conversation_id,role,content)"
                      + " VALUES(?,?,'USER',?)",
                  message,
                  id,
                  r.text);
              jdbc.update(
                  "INSERT INTO guide_messages(id,conversation_id,role,content)"
                      + " VALUES(?,?,'ASSISTANT',?)",
                  UUID.randomUUID().toString(),
                  id,
                  changes.json(reply));
              changes.record(
                  jwt.getSubject(), "message.saved", message, Map.of("conversationId", id));
              return reply;
            });
  }

  @GetMapping("/conversations/{id}/messages")
  public Object messages(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestParam(defaultValue = "0") int page) {
    if (page < 0) throw new IllegalArgumentException();
    if (jdbc.queryForObject(
            "SELECT COUNT(*) FROM conversations WHERE id=? AND owner_id=?",
            Integer.class,
            id,
            jwt.getSubject())
        == 0) throw Api.denied();
    return jdbc.query(
        "SELECT id,role,content,created_at FROM guide_messages WHERE conversation_id=? ORDER BY"
            + " created_at OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY",
        (rs, n) ->
            Map.of(
                "id",
                rs.getString(1),
                "role",
                rs.getString(2),
                "content",
                rs.getString(3),
                "createdAt",
                rs.getTimestamp(4).toInstant()),
        id,
        page * 50);
  }

  @PostMapping("/phrases")
  @Transactional
  public Object phrase(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody Message r) {
    String id = UUID.randomUUID().toString();
    jdbc.update(
        "INSERT INTO saved_phrases(id,owner_id,content) VALUES(?,?,?)",
        id,
        jwt.getSubject(),
        r.text);
    changes.record(jwt.getSubject(), "phrase.saved", id, Map.of());
    return Map.of("id", id);
  }

  @GetMapping("/phrases")
  public Object phrases(@AuthenticationPrincipal Jwt jwt) {
    return jdbc.query(
        "SELECT id,content FROM saved_phrases WHERE owner_id=?",
        (rs, n) -> Map.of("id", rs.getString(1), "content", rs.getString(2)),
        jwt.getSubject());
  }

  @PostMapping(value = "/media", consumes = "multipart/form-data")
  public Object upload(
      @AuthenticationPrincipal Jwt jwt,
      @RequestPart org.springframework.web.multipart.MultipartFile file)
      throws Exception {
    if (file.isEmpty()
        || file.getSize() > 5 * 1024 * 1024
        || !Set.of("image/jpeg", "image/png", "application/pdf", "audio/mpeg", "audio/wav")
            .contains(file.getContentType()))
      throw new IllegalArgumentException("Unsupported media or size");
    String key = storage.upload(file.getBytes(), file.getContentType());
    return new org.springframework.transaction.support.TransactionTemplate(txManager)
        .execute(
            s -> {
              String id = UUID.randomUUID().toString();
              jdbc.update(
                  "INSERT INTO guide_media(id,owner_id,object_key,mime_type,size_bytes)"
                      + " VALUES(?,?,?,?,?)",
                  id,
                  jwt.getSubject(),
                  key,
                  file.getContentType(),
                  file.getSize());
              changes.record(jwt.getSubject(), "guide.media-uploaded", id, Map.of());
              return Map.of("mediaId", id);
            });
  }

  @PostMapping("/replanning-jobs")
  @ResponseStatus(HttpStatus.ACCEPTED)
  public Object replan(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Request r) {
    access.require(r.tripId, bearer, true);
    Map weather =
        HttpClients.client(discoveryUrl)
            .get()
            .uri("/api/v1/discovery/weather?tripId={id}", r.tripId)
            .header("Authorization", bearer)
            .retrieve()
            .body(Map.class);
    Map calendar =
        HttpClients.client(tripUrl)
            .get()
            .uri("/api/v1/trips/{id}/calendar", r.tripId)
            .header("Authorization", bearer)
            .retrieve()
            .body(Map.class);
    Map<String, Object> preferences = new HashMap<>(r.preferences);
    preferences.put("currentWeather", weather.get("data"));
    preferences.put("approvedCalendar", calendar.get("data"));
    preferences.put("requiresApproval", true);
    return generate(jwt, bearer, key, new Request(r.tripId, preferences));
  }

  @PostMapping("/jobs/{id}/save-proposal")
  @ResponseStatus(HttpStatus.CREATED)
  public Object proposal(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id FROM generation_jobs WHERE id=? AND owner_id=? AND status='SUCCEEDED'",
            id,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.conflict();
    String trip = rows.getFirst().get("TRIP_ID").toString();
    access.require(trip, bearer, true);
    Map input =
        parse(
            jdbc.queryForObject(
                "SELECT input_json FROM generation_jobs WHERE id=?", String.class, id));
    Map original = (Map) input.get("trip");
    Map result =
        parse(
            jdbc.queryForObject(
                "SELECT output_json FROM generation_jobs WHERE id=?", String.class, id));
    Map response =
        HttpClients.client(tripUrl)
            .post()
            .uri("/api/v1/trips/{id}/replanning-proposals", trip)
            .header("Authorization", bearer)
            .header("Idempotency-Key", key)
            .body(
                Map.of(
                    "reason",
                    "Replan from supplied delays, skipped stops, preferences and provider weather",
                    "baseVersion",
                    original.get("version"),
                    "itinerary",
                    Map.of("activities", result.get("activities"), "source", result.get("source"))))
            .retrieve()
            .body(Map.class);
    return response.get("data");
  }
}
