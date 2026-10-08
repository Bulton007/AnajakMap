package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;

import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.time.*;
import org.junit.jupiter.api.Test;

class ProviderTimeoutTest {
  @Test
  void unavailableProviderFailsWithoutMockFallback() throws Exception {
    var socket = new java.net.ServerSocket(0);
    int port = socket.getLocalPort();
    socket.close();
    // Measure request timeout, not cold JVM TLS/Jackson initialization.
    var client = HttpClients.client("http://127.0.0.1:" + port);
    assertTimeoutPreemptively(
        Duration.ofSeconds(5),
        () ->
            assertThrows(
                org.springframework.web.client.ResourceAccessException.class,
                () ->
                    client
                        .get()
                        .retrieve()
                        .body(String.class)));
  }

  @Test
  void slowProviderTimesOutAfterBoundedRetries() throws Exception {
    var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    var pool = java.util.concurrent.Executors.newCachedThreadPool();
    server.setExecutor(pool);
    server.createContext(
        "/",
        exchange -> {
          try {
            Thread.sleep(500);
            exchange.sendResponseHeaders(200, 2);
            exchange.getResponseBody().write("ok".getBytes());
          } catch (Exception ignored) {
          } finally {
            exchange.close();
          }
        });
    server.start();
    try {
      var client = HttpClients.client(
          "http://127.0.0.1:" + server.getAddress().getPort(), Duration.ofMillis(100));
      assertTimeoutPreemptively(
          Duration.ofSeconds(3),
          () ->
              assertThrows(
                  org.springframework.web.client.ResourceAccessException.class,
                  () ->
                      client
                          .get()
                          .retrieve()
                          .body(String.class)));
    } finally {
      server.stop(0);
      pool.shutdownNow();
    }
  }
}
