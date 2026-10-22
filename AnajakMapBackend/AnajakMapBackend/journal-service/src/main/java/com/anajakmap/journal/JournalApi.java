package com.anajakmap.journal;

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
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/journal")
public class JournalApi {
  @org.springframework.beans.factory.annotation.Value("${anajak.ai-url}")
  private String aiUrl;

  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final TripAccess access;
  private final ObjectStore storage;
  private final TransactionTemplate tx;

  public JournalApi(
      JdbcTemplate j, Changes c, TripAccess a, ObjectStore o, PlatformTransactionManager t) {
    jdbc = j;
    changes = c;
    access = a;
    storage = o;
    tx = new TransactionTemplate(t);
  }

  public record Entry(
      @NotBlank String tripId,
      @NotBlank @Size(max = 200) String title,
      @NotBlank @Size(max = 16000) String content,
      @Size(max = 16000) String recap,
      long version) {}

  public record Visit(
      @NotBlank String tripId,
      @NotBlank @Size(max = 200) String place,
      @NotNull Instant visitedAt,
      @DecimalMin("-90") @DecimalMax("90") double latitude,
      @DecimalMin("-180") @DecimalMax("180") double longitude) {}

  @PostMapping
  public Object create(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Entry r) {
    access.require(r.tripId, bearer, true);
    return tx.execute(
        s -> {
          var prior = changes.prior(jwt.getSubject(), key, "journal.create", r);
          if (prior.isPresent()) return parse(prior.get());
          String id = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO journal_entries(id,trip_id,owner_id,title,content,recap)"
                  + " VALUES(?,?,?,?,?,?)",
              id,
              r.tripId,
              jwt.getSubject(),
              r.title,
              r.content,
              r.recap);
          changes.record(jwt.getSubject(), "journal.created", id, Map.of("tripId", r.tripId));
          var result = Map.of("id", id, "version", 0);
          changes.remember(jwt.getSubject(), key, "journal.create", r, result);
          return result;
        });
  }

  @PutMapping("/{id}")
  public Object edit(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @Valid @RequestBody Entry r) {
    String trip =
        jdbc.queryForObject("SELECT trip_id FROM journal_entries WHERE id=?", String.class, id);
    if (!trip.equals(r.tripId)) throw Api.conflict();
    access.require(trip, bearer, true);
    return tx.execute(
        s -> {
          if (jdbc.update(
                  "UPDATE journal_entries SET"
                      + " title=?,content=?,recap=?,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE"
                      + " id=? AND owner_id=? AND version=?",
                  r.title,
                  r.content,
                  r.recap,
                  id,
                  jwt.getSubject(),
                  r.version)
              != 1) throw Api.conflict();
          changes.record(jwt.getSubject(), "journal.edited", id, Map.of("version", r.version + 1));
          return Map.of("id", id, "version", r.version + 1);
        });
  }

  @GetMapping
  public Object list(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestParam String tripId,
      @RequestParam(defaultValue = "0") int page) {
    access.require(tripId, bearer, false);
    if (page < 0) throw new IllegalArgumentException();
    return jdbc.query(
        "SELECT id,title,content,recap,version FROM journal_entries WHERE trip_id=? AND owner_id=?"
            + " ORDER BY created_at DESC OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY",
        (rs, n) ->
            Map.of(
                "id",
                rs.getString(1),
                "title",
                rs.getString(2),
                "content",
                rs.getString(3),
                "recap",
                rs.getString(4) == null ? "" : rs.getString(4),
                "version",
                rs.getLong(5)),
        tripId,
        jwt.getSubject(),
        page * 50);
  }

  @PostMapping("/visits")
  public Object visit(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @Valid @RequestBody Visit r) {
    access.require(r.tripId, bearer, true);
    return tx.execute(
        s -> {
          String id = UUID.randomUUID().toString();
          jdbc.update(
              "INSERT INTO visited_places(id,trip_id,owner_id,place,visited_at,latitude,longitude)"
                  + " VALUES(?,?,?,?,?,?,?)",
              id,
              r.tripId,
              jwt.getSubject(),
              r.place,
              java.sql.Timestamp.from(r.visitedAt),
              r.latitude,
              r.longitude);
          changes.record(jwt.getSubject(), "place.visited", id, Map.of("tripId", r.tripId));
          return Map.of("id", id);
        });
  }

  @PostMapping(value = "/{id}/photos", consumes = "multipart/form-data")
  public Object photo(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestPart MultipartFile file)
      throws Exception {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id FROM journal_entries WHERE id=? AND owner_id=?", id, jwt.getSubject());
    if (rows.isEmpty()) throw Api.denied();
    access.require(rows.getFirst().get("TRIP_ID").toString(), bearer, true);
    if (file.isEmpty()
        || file.getSize() > 10 * 1024 * 1024
        || !Set.of("image/jpeg", "image/png").contains(file.getContentType()))
      throw new IllegalArgumentException();
    String key = storage.upload(file.getBytes(), file.getContentType());
    try {
      return tx.execute(
          s -> {
            String media = UUID.randomUUID().toString();
            jdbc.update(
                "INSERT INTO journal_media(id,entry_id,object_key,mime_type) VALUES(?,?,?,?)",
                media,
                id,
                key,
                file.getContentType());
            changes.record(jwt.getSubject(), "journal.photo-added", media, Map.of("entryId", id));
            return Map.of("id", media);
          });
    } catch (RuntimeException failure) {
      storage.discardAfterFailure(key, failure);
      throw failure;
    }
  }

  private Object parse(String s) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readValue(s, Map.class);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  @PostMapping("/{id}/generate-recap")
  public Object recap(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestParam long version) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id,version FROM journal_entries WHERE id=? AND owner_id=?",
            id,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.denied();
    var r = rows.getFirst();
    access.require(r.get("TRIP_ID").toString(), bearer, true);
    if (((Number) r.get("VERSION")).longValue() != version) throw Api.conflict();
    String content =
        jdbc.queryForObject("SELECT content FROM journal_entries WHERE id=?", String.class, id);
    Map response =
        HttpClients.client(aiUrl)
            .post()
            .uri("/api/v1/guide/recap")
            .header("Authorization", bearer)
            .body(Map.of("input", Map.of("text", content)))
            .retrieve()
            .body(Map.class);
    Map result = (Map) response.get("data");
    String recap = Objects.toString(result.get("text"), "");
    if (recap.isBlank() || recap.length() > 16000)
      throw new IllegalArgumentException("Invalid AI recap");
    return tx.execute(
        s -> {
          if (jdbc.update(
                  "UPDATE journal_entries SET recap=?,version=version+1,updated_at=CURRENT_TIMESTAMP"
                      + " WHERE id=? AND version=?",
                  recap,
                  id,
                  version)
              != 1) throw Api.conflict();
          changes.record(
              jwt.getSubject(), "journal.recap-generated", id, Map.of("version", version + 1));
          return Map.of("recap", recap, "version", version + 1, "editable", true);
        });
  }

  @GetMapping("/{id}/photos")
  public Object photos(@PathVariable String id, @AuthenticationPrincipal Jwt jwt) {
    if (jdbc.queryForObject(
            "SELECT COUNT(*) FROM journal_entries WHERE id=? AND owner_id=?",
            Integer.class,
            id,
            jwt.getSubject())
        != 1) throw Api.denied();
    return jdbc.queryForList("SELECT id,mime_type FROM journal_media WHERE entry_id=?", id);
  }

  @GetMapping("/photos/{mediaId}/content")
  public org.springframework.http.ResponseEntity<byte[]> photoContent(
      @PathVariable String mediaId, @AuthenticationPrincipal Jwt jwt) {
    var rows =
        jdbc.queryForList(
            "SELECT m.object_key,m.mime_type FROM journal_media m JOIN journal_entries e ON"
                + " e.id=m.entry_id WHERE m.id=? AND e.owner_id=?",
            mediaId,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.denied();
    var r = rows.getFirst();
    return org.springframework.http.ResponseEntity.ok()
        .header("Cache-Control", "no-store")
        .contentType(
            org.springframework.http.MediaType.parseMediaType(r.get("MIME_TYPE").toString()))
        .body(storage.download(r.get("OBJECT_KEY").toString()));
  }
}
