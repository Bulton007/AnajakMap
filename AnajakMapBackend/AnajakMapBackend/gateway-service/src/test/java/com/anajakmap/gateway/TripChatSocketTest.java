package com.anajakmap.gateway;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.anajakmap.platform.RateLimit;
import com.anajakmap.platform.TripAccess;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.net.URI;
import java.net.http.*;
import java.nio.file.Path;
import java.time.Instant;
import java.util.concurrent.*;
import org.apache.catalina.startup.Tomcat;
import org.apache.tomcat.websocket.server.WsSci;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.oauth2.jwt.Jwt;

class TripChatSocketTest {
  @TempDir Path temporary;

  @Test
  void sendsLiveSignalOverActualWebSocketAndRechecksMembership() throws Exception {
    var access = mock(TripAccess.class);
    var chat = new TripChatSocket(access, mock(RateLimit.class));
    var jwt = Jwt.withTokenValue("test").header("alg", "none").subject("recipient")
        .expiresAt(Instant.now().plusSeconds(60)).build();
    var tomcat = new Tomcat();
    tomcat.setBaseDir(temporary.toString());
    tomcat.setPort(0);
    tomcat.getConnector().setProperty("address", "127.0.0.1");
    var app = tomcat.addContext("", temporary.toString());
    app.addServletContainerInitializer(new WsSci(), null);
    Tomcat.addServlet(app, "chat", new HttpServlet() {
      @Override protected void doGet(HttpServletRequest req, HttpServletResponse res)
          throws IOException {
        try {
          chat.connect("test-trip", jwt, req, res);
        } catch (Exception ex) {
          throw new IOException(ex);
        }
      }
    });
    app.addServletMappingDecoded("/chat", "chat");
    tomcat.start();
    try (var client = HttpClient.newHttpClient()) {
      var frames = new LinkedBlockingQueue<String>();
      var ws = client.newWebSocketBuilder().header("Authorization", "Bearer test")
          .buildAsync(URI.create("ws://127.0.0.1:" + tomcat.getConnector().getLocalPort() + "/chat"),
              new WebSocket.Listener() {
                @Override public CompletionStage<?> onText(WebSocket socket, CharSequence data, boolean last) {
                  frames.add(data.toString());
                  socket.request(1);
                  return null;
                }
              }).get(5, TimeUnit.SECONDS);
      try {
        assertEquals("ready", frames.poll(5, TimeUnit.SECONDS));
        chat.publish("another-trip");
        chat.publish("test-trip");
        assertEquals("changed", frames.poll(5, TimeUnit.SECONDS));
        verify(access, times(2)).require("test-trip", "Bearer test", false);
      } finally {
        ws.abort();
      }
    } finally {
      tomcat.stop();
      tomcat.destroy();
    }
  }
}
