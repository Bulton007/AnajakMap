package com.anajakmap.gateway;

import com.anajakmap.platform.Api;
import com.anajakmap.platform.Changes;
import com.anajakmap.platform.RateLimit;
import com.anajakmap.platform.TripAccess;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.websocket.*;
import jakarta.websocket.server.ServerContainer;
import jakarta.websocket.server.ServerEndpointConfig;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.context.annotation.Bean;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.listener.ChannelTopic;
import org.springframework.data.redis.listener.RedisMessageListenerContainer;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.HttpClientErrorException;

@RestController
public class TripChatSocket {
  private record Subscription(String trip, String account, String bearer, Instant expires) {}
  private final Map<Session, Subscription> sessions = new ConcurrentHashMap<>();
  private final TripAccess access;
  private final RateLimit limits;

  public TripChatSocket(TripAccess access, RateLimit limits) {
    this.access = access;
    this.limits = limits;
  }

  @Bean
  RedisMessageListenerContainer tripChatEvents(RedisConnectionFactory factory) {
    var listener = new RedisMessageListenerContainer();
    listener.setConnectionFactory(factory);
    listener.addMessageListener((event, pattern) ->
        publish(new String(event.getBody(), StandardCharsets.UTF_8)),
        ChannelTopic.of("anajak.trip-chat"));
    listener.addMessageListener((event, pattern) -> notifyAccount(
        new String(event.getBody(), StandardCharsets.UTF_8)),
        ChannelTopic.of("anajak.notifications"));
    listener.addMessageListener((event, pattern) -> {
      String payload = new String(event.getBody(), StandardCharsets.UTF_8);
      int separator = payload.indexOf('|');
      if (separator <= 0) return;
      String account = payload.substring(separator + 1);
      publish(payload.substring(0, separator), "typing:" + account, account);
    }, ChannelTopic.of("anajak.chat-typing"));
    return listener;
  }

  @GetMapping("/api/v1/trips/{tripId}/chat/live")
  public void connect(@PathVariable String tripId, @AuthenticationPrincipal Jwt jwt,
      HttpServletRequest request, HttpServletResponse response) throws Exception {
    if (!"websocket".equalsIgnoreCase(request.getHeader("Upgrade"))) {
      response.sendError(426);
      return;
    }
    limits.check("trip-chat-live:" + Changes.hash(jwt.getSubject()), 12, 60);
    var bearer = request.getHeader("Authorization");
    try {
      access.require(tripId, bearer, false);
    } catch (HttpClientErrorException ex) {
      throw Api.denied();
    }
    upgrade(request, response, new Subscription(tripId, jwt.getSubject(), bearer, jwt.getExpiresAt()));
  }

  @GetMapping("/api/v1/notifications/live")
  public void notifications(@AuthenticationPrincipal Jwt jwt,
      HttpServletRequest request, HttpServletResponse response) throws Exception {
    if (!"websocket".equalsIgnoreCase(request.getHeader("Upgrade"))) {
      response.sendError(426);
      return;
    }
    limits.check("notifications-live:" + Changes.hash(jwt.getSubject()), 12, 60);
    upgrade(request, response, new Subscription(null, jwt.getSubject(), null, jwt.getExpiresAt()));
  }

  @GetMapping("/api/v1/trips/direct-chat/{peerId}/live")
  public void directChat(@PathVariable String peerId, @AuthenticationPrincipal Jwt jwt,
      HttpServletRequest request, HttpServletResponse response) throws Exception {
    if (!"websocket".equalsIgnoreCase(request.getHeader("Upgrade"))) {
      response.sendError(426);
      return;
    }
    limits.check("direct-chat-live:" + Changes.hash(jwt.getSubject()), 12, 60);
    String scope = access.directChatScope(peerId, request.getHeader("Authorization"));
    upgrade(request, response, new Subscription(scope, jwt.getSubject(), null, jwt.getExpiresAt()));
  }

  private void upgrade(HttpServletRequest request, HttpServletResponse response,
      Subscription subscription) throws Exception {
    var endpoint = new ChatEndpoint(subscription);
    var config = ServerEndpointConfig.Builder.create(ChatEndpoint.class, request.getRequestURI())
        .configurator(new ServerEndpointConfig.Configurator() {
          @Override public <T> T getEndpointInstance(Class<T> type) {
            return type.cast(endpoint);
          }
        }).build();
    var container = (ServerContainer) request.getServletContext()
        .getAttribute(ServerContainer.class.getName());
    container.upgradeHttpToWebSocket(request, response, config, Map.of());
  }

  void publish(String trip) {
    publish(trip, "changed", null);
  }

  private void publish(String trip, String frame, String excludedAccount) {
    sessions.forEach((session, subscription) -> {
      if (!trip.equals(subscription.trip()) || subscription.account().equals(excludedAccount)
          || !valid(session, subscription)) return;
      try {
        if (subscription.bearer() != null) access.require(trip, subscription.bearer(), false);
        send(session, frame);
      } catch (RuntimeException ex) {
        close(session);
      }
    });
  }

  private void notifyAccount(String account) {
    sessions.forEach((session, subscription) -> {
      if (subscription.trip() == null && account.equals(subscription.account())
          && valid(session, subscription)) send(session, "changed");
    });
  }

  private boolean valid(Session session, Subscription subscription) {
    if (subscription.expires() != null && subscription.expires().isAfter(Instant.now())) return true;
    close(session);
    return false;
  }

  @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 15_000)
  public void expireConnections() {
    sessions.forEach(this::valid);
  }

  private void send(Session session, String frame) {
    try {
      session.getAsyncRemote().sendText(frame, result -> {
        if (!result.isOK()) close(session);
      });
    } catch (RuntimeException ex) {
      close(session);
    }
  }

  private void close(Session session) {
    sessions.remove(session);
    try {
      session.close();
    } catch (java.io.IOException ignored) {
      // The transport may already be gone.
    }
  }

  public final class ChatEndpoint extends Endpoint {
    private final Subscription subscription;

    private ChatEndpoint(Subscription subscription) {
      this.subscription = subscription;
    }

    @Override public void onOpen(Session session, EndpointConfig config) {
      session.setMaxIdleTimeout(65_000);
      session.setMaxTextMessageBufferSize(64);
      session.getAsyncRemote().setSendTimeout(5_000);
      sessions.put(session, subscription);
      session.getAsyncRemote().sendText("ready", result -> {
        if (!result.isOK()) close(session);
      });
    }

    @Override public void onClose(Session session, CloseReason reason) {
      sessions.remove(session);
    }

    @Override public void onError(Session session, Throwable error) {
      if (session != null) close(session);
    }
  }
}
