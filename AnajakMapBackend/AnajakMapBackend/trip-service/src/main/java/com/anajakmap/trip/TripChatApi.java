package com.anajakmap.trip;

import com.anajakmap.platform.RateLimit;
import com.anajakmap.platform.Api;
import com.anajakmap.platform.Changes;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.Map;
import java.util.UUID;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/trips")
public class TripChatApi {
  private final TripApi trips;
  private final JdbcTemplate jdbc;
  private final StringRedisTemplate redis;
  private final RateLimit limits;
  @org.springframework.beans.factory.annotation.Autowired private Changes changes;

  public TripChatApi(TripApi trips, JdbcTemplate jdbc, StringRedisTemplate redis, RateLimit limits) {
    this.trips = trips;
    this.jdbc = jdbc;
    this.redis = redis;
    this.limits = limits;
  }

  public record Message(@NotBlank @Size(max = 1000) String text) {}

  @GetMapping("/{tripId}/chat")
  public Object history(@PathVariable String tripId, @AuthenticationPrincipal Jwt jwt,
      @RequestParam(defaultValue = "0") int page) {
    trips.require(tripId, jwt.getSubject(), false);
    return history("trip_chat_messages", "trip_id", tripId, page, false);
  }

  @GetMapping("/direct-chat/{peerId}")
  public Object directHistory(@PathVariable UUID peerId, @AuthenticationPrincipal Jwt jwt,
      @RequestParam(defaultValue = "0") int page) {
    return history("direct_chat_messages", "conversation_id", directScope(jwt.getSubject(), peerId), page, true);
  }

  @GetMapping("/direct-chat")
  public Object directConversations(@AuthenticationPrincipal Jwt jwt) {
    String account = jwt.getSubject();
    return jdbc.queryForList(
        "SELECT peer_id,message,sent_at,unread_count FROM (SELECT CASE WHEN sender_id=? THEN recipient_id"
            + " ELSE sender_id END AS peer_id,message,sent_at,id,"
            + " SUM(CASE WHEN recipient_id=? AND read_at IS NULL THEN 1 ELSE 0 END)"
            + " OVER(PARTITION BY conversation_id) AS unread_count,"
            + " ROW_NUMBER() OVER(PARTITION BY conversation_id ORDER BY sent_at DESC,id DESC) AS rank_no"
            + " FROM direct_chat_messages WHERE sender_id=? OR recipient_id=?)"
            + " WHERE rank_no=1 ORDER BY sent_at DESC,id DESC FETCH FIRST 50 ROWS ONLY",
        account, account, account, account);
  }

  private Object history(String table, String scopeColumn, String scope, int page, boolean receipts) {
    if (page < 0 || page > 1000) throw new IllegalArgumentException();
    return jdbc.queryForList(
        "SELECT id,sender_id,message,sent_at" + (receipts ? ",read_at" : "")
            + " FROM " + table + " WHERE " + scopeColumn + "=?"
            + " ORDER BY sent_at DESC,id DESC OFFSET ? ROWS FETCH NEXT 50 ROWS ONLY", scope, page * 50);
  }

  @PutMapping("/direct-chat/{peerId}/read/{messageId}")
  @Transactional
  public Object readDirect(@PathVariable UUID peerId, @PathVariable UUID messageId,
      @AuthenticationPrincipal Jwt jwt) {
    String account = jwt.getSubject();
    String scope = directScope(account, peerId);
    int changed = jdbc.update("UPDATE direct_chat_messages SET read_at=CURRENT_TIMESTAMP"
        + " WHERE conversation_id=? AND recipient_id=? AND read_at IS NULL AND sent_at<="
        + " (SELECT sent_at FROM direct_chat_messages WHERE id=? AND conversation_id=?)",
        scope, account, messageId.toString(), scope);
    if (changed > 0) signalAfterCommit(scope);
    return Map.of("updated", changed);
  }

  @GetMapping("/direct-chat/{peerId}/access")
  public Object directAccess(@PathVariable UUID peerId, @AuthenticationPrincipal Jwt jwt) {
    return Map.of("scope", directScope(jwt.getSubject(), peerId));
  }

  @PostMapping("/{tripId}/chat/typing")
  public Object tripTyping(@PathVariable String tripId, @AuthenticationPrincipal Jwt jwt) {
    trips.require(tripId, jwt.getSubject(), false);
    return typing(tripId, jwt.getSubject());
  }

  @PostMapping("/direct-chat/{peerId}/typing")
  public Object directTyping(@PathVariable UUID peerId, @AuthenticationPrincipal Jwt jwt) {
    return typing(directScope(jwt.getSubject(), peerId), jwt.getSubject());
  }

  private Object typing(String scope, String account) {
    limits.check("chat-typing:" + Changes.hash(account), 20, 60);
    redis.convertAndSend("anajak.chat-typing", scope + "|" + account);
    return Map.of("status", "SIGNALLED");
  }

  @PostMapping("/{tripId}/chat")
  @Transactional
  public Object send(@PathVariable String tripId, @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Message input) {
    String sender = jwt.getSubject();
    Trip trip = trips.require(tripId, sender, false);
    var request = Map.of("scope", tripId, "text", input.text());
    var prior = changes.prior(sender, key, "chat.send", request);
    if (prior.isPresent()) return parse(prior.get());
    limits.check("trip-chat:" + sender, 30, 60);
    String id = UUID.randomUUID().toString();
    jdbc.update("INSERT INTO trip_chat_messages(id,trip_id,sender_id,message) VALUES(?,?,?,?)",
        id, tripId, sender, input.text().strip());
    var recipients = new java.util.HashSet<>(jdbc.queryForList(
        "SELECT account_id FROM trip_members WHERE trip_id=? AND accepted=1", String.class, tripId));
    recipients.add(trip.ownerId);
    recipients.remove(sender);
    changes.record(sender, "chat.trip-message", tripId,
        Map.of("recipients", recipients, "tripTitle", trip.title));
    return finish(sender, key, request, id, tripId);
  }

  @PostMapping("/direct-chat/{peerId}")
  @Transactional
  public Object sendDirect(@PathVariable UUID peerId, @AuthenticationPrincipal Jwt jwt,
      @RequestHeader("Authorization") String bearer, @RequestHeader("Idempotency-Key") String key,
      @Valid @RequestBody Message input) {
    String sender = jwt.getSubject();
    String scope = directScope(sender, peerId);
    var request = Map.of("scope", scope, "text", input.text());
    var prior = changes.prior(sender, key, "chat.send", request);
    if (prior.isPresent()) return parse(prior.get());
    limits.check("trip-chat:" + sender, 30, 60);
    trips.requireTraveler(peerId.toString(), bearer);
    String id = UUID.randomUUID().toString();
    jdbc.update("INSERT INTO direct_chat_messages(id,conversation_id,sender_id,recipient_id,message)"
        + " VALUES(?,?,?,?,?)", id, scope, sender, peerId.toString(), input.text().strip());
    changes.record(sender, "chat.direct-message", id, Map.of("accountId", peerId.toString()));
    return finish(sender, key, request, id, scope);
  }

  private Object finish(String sender, String key, Object request, String id, String scope) {
    var result = Map.of("id", id);
    changes.remember(sender, key, "chat.send", request, result);
    signalAfterCommit(scope);
    return result;
  }

  private void signalAfterCommit(String scope) {
    TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
      @Override public void afterCommit() {
        try {
          redis.convertAndSend("anajak.trip-chat", scope);
        } catch (org.springframework.dao.DataAccessException ex) {
          org.slf4j.LoggerFactory.getLogger(TripChatApi.class).warn("Chat live signal unavailable");
        }
      }
    });
  }

  private Object parse(String json) {
    try {
      return new com.fasterxml.jackson.databind.ObjectMapper().readTree(json);
    } catch (com.fasterxml.jackson.core.JsonProcessingException ex) {
      throw new IllegalStateException(ex);
    }
  }

  private String directScope(String sender, UUID peerId) {
    String peer = peerId.toString();
    if (peer.equals(sender)) throw Api.denied();
    return Changes.hash(sender.compareTo(peer) < 0 ? sender + ":" + peer : peer + ":" + sender);
  }
}
