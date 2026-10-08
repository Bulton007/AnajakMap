package com.anajakmap.reservation;

import com.anajakmap.platform.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/reservations")
public class ReservationApi {
  @org.springframework.beans.factory.annotation.Value("${anajak.ai-url}")
  private String aiUrl;

  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final TripAccess access;
  private final ObjectStore storage;
  private final TransactionTemplate tx;

  public ReservationApi(
      JdbcTemplate j, Changes c, TripAccess a, ObjectStore o, PlatformTransactionManager t) {
    jdbc = j;
    changes = c;
    access = a;
    storage = o;
    tx = new TransactionTemplate(t);
  }

  public record Confirm(
      @NotBlank @Size(max = 200) String provider,
      @NotBlank @Size(max = 100) String reference,
      @NotBlank String timezone,
      @NotNull Instant startsAt,
      @NotNull Instant endsAt,
      long version) {}

  public record Manual(
      @NotBlank String tripId,
      @NotBlank @Size(max = 200) String provider,
      @NotBlank @Size(max = 100) String reference,
      @NotBlank String timezone,
      @NotNull Instant startsAt,
      @NotNull Instant endsAt) {}

  @PostMapping
  public Object manual(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Manual r) {
    access.require(r.tripId, bearer, true);
    ZoneId.of(r.timezone);
    if (!r.endsAt.isAfter(r.startsAt)) throw new IllegalArgumentException("Invalid reservation dates");
    return tx.execute(s -> {
      var prior = changes.prior(jwt.getSubject(), key, "reservation.manual", r);
      if (prior.isPresent()) {
        try { return new com.fasterxml.jackson.databind.ObjectMapper().readValue(prior.get(), Map.class); }
        catch (com.fasterxml.jackson.core.JsonProcessingException e) { throw new IllegalStateException(e); }
      }
      String id = UUID.randomUUID().toString();
      jdbc.update("INSERT INTO reservations(id,trip_id,provider,reference,timezone,starts_at,ends_at) VALUES(?,?,?,?,?,?,?)",
          id, r.tripId, r.provider, r.reference, r.timezone,
          java.sql.Timestamp.from(r.startsAt), java.sql.Timestamp.from(r.endsAt));
      var result = Map.of("id", id, "status", "CONFIRMED", "version", 0);
      changes.record(jwt.getSubject(), "reservation.confirmed", id, Map.of("tripId", r.tripId));
      changes.remember(jwt.getSubject(), key, "reservation.manual", r, result);
      return result;
    });
  }

  @PostMapping(value = "/documents", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public Object upload(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestParam String tripId,
      @RequestPart MultipartFile file)
      throws Exception {
    access.require(tripId, bearer, true);
    if (file.isEmpty()
        || file.getSize() > 10 * 1024 * 1024
        || !Set.of("image/jpeg", "image/png", "application/pdf").contains(file.getContentType()))
      throw new IllegalArgumentException("JPEG, PNG or PDF up to 10 MB required");
    String key = storage.upload(file.getBytes(), file.getContentType());
    try {
      return tx.execute(
          s -> {
            String id = UUID.randomUUID().toString();
            jdbc.update(
                "INSERT INTO"
                    + " reservation_documents(id,trip_id,owner_id,object_key,mime_type,size_bytes,status)"
                    + " VALUES(?,?,?,?,?,?,'UPLOADED')",
                id,
                tripId,
                jwt.getSubject(),
                key,
                file.getContentType(),
                file.getSize());
            changes.record(jwt.getSubject(), "reservation.uploaded", id, Map.of("tripId", tripId));
            return Map.of("documentId", id, "status", "UPLOADED", "version", 0);
          });
    } catch (RuntimeException failure) {
      storage.discardAfterFailure(key, failure);
      throw failure;
    }
  }

  @GetMapping("/documents/{id}/content")
  public ResponseEntity<byte[]> content(
      @PathVariable String id, @RequestHeader("Authorization") String bearer) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id,object_key,mime_type FROM reservation_documents WHERE id=?", id);
    if (rows.isEmpty()) throw Api.missing();
    var r = rows.getFirst();
    access.require(r.get("TRIP_ID").toString(), bearer, false);
    return ResponseEntity.ok()
        .header("Cache-Control", "no-store")
        .contentType(MediaType.parseMediaType(r.get("MIME_TYPE").toString()))
        .body(storage.download(r.get("OBJECT_KEY").toString()));
  }

  @PostMapping("/documents/{id}/confirm")
  public Object confirm(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @Valid @RequestBody Confirm r) {
    String trip =
        jdbc.queryForObject(
            "SELECT trip_id FROM reservation_documents WHERE id=?", String.class, id);
    access.require(trip, bearer, true);
    ZoneId.of(r.timezone);
    if (!r.endsAt.isAfter(r.startsAt)) throw new IllegalArgumentException();
    return tx.execute(
        s -> {
          if (jdbc.update(
                  "UPDATE reservation_documents SET status='CONFIRMED',version=version+1 WHERE id=?"
                      + " AND version=? AND status<>'CONFIRMED'",
                  id,
                  r.version)
              != 1) throw Api.conflict();
          String record = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO"
                  + " reservations(id,document_id,trip_id,provider,reference,timezone,starts_at,ends_at)"
                  + " VALUES(?,?,?,?,?,?,?,?)",
              record,
              id,
              trip,
              r.provider,
              r.reference,
              r.timezone,
              java.sql.Timestamp.from(r.startsAt),
              java.sql.Timestamp.from(r.endsAt));
          changes.record(jwt.getSubject(), "reservation.confirmed", record, Map.of("tripId", trip));
          return Map.of("id", record, "status", "CONFIRMED");
        });
  }

  @GetMapping
  public Object list(
      @RequestHeader("Authorization") String bearer,
      @RequestParam String tripId,
      @RequestParam(defaultValue = "0") int page) {
    access.require(tripId, bearer, false);
    if (page < 0) throw new IllegalArgumentException();
    return jdbc.queryForList(
        "SELECT id,provider,reference,timezone,starts_at,ends_at,version FROM reservations WHERE"
            + " trip_id=? ORDER BY starts_at OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY",
        tripId,
        page * 50);
  }

  @PostMapping("/documents/{id}/extract")
  public Object extract(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id,object_key,mime_type,version FROM reservation_documents WHERE id=?",
            id);
    if (rows.isEmpty()) throw Api.missing();
    var r = rows.getFirst();
    access.require(r.get("TRIP_ID").toString(), bearer, true);
    Map envelope =
        HttpClients.client(aiUrl)
            .post()
            .uri("/api/v1/guide/reservation")
            .header("Authorization", bearer)
            .body(
                Map.of(
                    "input",
                    Map.of(
                        "documentBase64",
                        Base64.getEncoder()
                            .encodeToString(storage.download(r.get("OBJECT_KEY").toString())),
                        "mimeType",
                        r.get("MIME_TYPE"))))
            .retrieve()
            .body(Map.class);
    Map result = (Map) envelope.get("data");
    return tx.execute(
        s -> {
          if (jdbc.update(
                  "UPDATE reservation_documents SET"
                      + " status='EXTRACTED',extraction=?,version=version+1 WHERE id=? AND"
                      + " version=? AND status<>'CONFIRMED'",
                  changes.json(result),
                  id,
                  r.get("VERSION"))
              != 1) throw Api.conflict();
          changes.record(
              jwt.getSubject(), "reservation.extracted", id, Map.of("requiresConfirmation", true));
          return Map.of(
              "documentId",
              id,
              "extraction",
              result,
              "version",
              ((Number) r.get("VERSION")).longValue() + 1,
              "requiresConfirmation",
              true);
        });
  }
}
