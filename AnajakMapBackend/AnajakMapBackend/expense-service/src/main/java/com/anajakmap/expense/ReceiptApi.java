package com.anajakmap.expense;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/expenses/receipts")
public class ReceiptApi {
  private final JdbcTemplate jdbc;
  private final Changes changes;
  private final ObjectStore storage;
  private final TripAccess access;
  private final TransactionTemplate tx;
  private final String aiUrl;

  public ReceiptApi(
      JdbcTemplate j,
      Changes c,
      ObjectStore s,
      TripAccess a,
      PlatformTransactionManager t,
      @Value("${anajak.ai-url}") String ai) {
    jdbc = j;
    changes = c;
    storage = s;
    access = a;
    tx = new TransactionTemplate(t);
    aiUrl = ai;
  }

  @PostMapping(consumes = "multipart/form-data")
  public Object upload(
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer,
      @RequestParam String tripId,
      @RequestPart MultipartFile file)
      throws Exception {
    access.require(tripId, bearer, true);
    if (file.isEmpty()
        || file.getSize() > 5 * 1024 * 1024
        || !Set.of("image/jpeg", "image/png", "application/pdf").contains(file.getContentType()))
      throw new IllegalArgumentException();
    String key = storage.upload(file.getBytes(), file.getContentType());
    try {
      return tx.execute(
          s -> {
            String id = UUID.randomUUID().toString();
            jdbc.update(
                "INSERT INTO receipts(id,trip_id,owner_id,object_key,mime_type,status)"
                    + " VALUES(?,?,?,?,?,'UPLOADED')",
                id,
                tripId,
                jwt.getSubject(),
                key,
                file.getContentType());
            changes.record(jwt.getSubject(), "receipt.uploaded", id, Map.of("tripId", tripId));
            return Map.of("id", id, "version", 0);
          });
    } catch (RuntimeException failure) {
      storage.discardAfterFailure(key, failure);
      throw failure;
    }
  }

  @PostMapping("/{id}/extract")
  public Object extract(
      @PathVariable String id,
      @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer) {
    var rows =
        jdbc.queryForList(
            "SELECT trip_id,object_key,mime_type,version FROM receipts WHERE id=? AND owner_id=?",
            id,
            jwt.getSubject());
    if (rows.isEmpty()) throw Api.denied();
    var r = rows.getFirst();
    access.require(r.get("TRIP_ID").toString(), bearer, true);
    Map response =
        HttpClients.client(aiUrl)
            .post()
            .uri("/api/v1/guide/receipt")
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
    Map result = (Map) response.get("data");
    if (result == null || !result.containsKey("amount") || !result.containsKey("currency"))
      throw new IllegalArgumentException("Invalid receipt extraction");
    new java.math.BigDecimal(result.get("amount").toString());
    Currency.getInstance(result.get("currency").toString());
    return tx.execute(
        s -> {
          if (jdbc.update(
                  "UPDATE receipts SET extraction=?,status='EXTRACTED',version=version+1 WHERE id=?"
                      + " AND version=?",
                  changes.json(result),
                  id,
                  r.get("VERSION"))
              != 1) throw Api.conflict();
          changes.record(
              jwt.getSubject(), "receipt.extracted", id, Map.of("requiresConfirmation", true));
          return Map.of(
              "id",
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
