package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.anajakmap.platform.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Validator;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.server.ResponseStatusException;

class GuideChatPrivacyTest {
  final JdbcTemplate jdbc = mock(JdbcTemplate.class);
  final GuideProvider provider = mock(GuideProvider.class);
  final Jwt jwt = Jwt.withTokenValue("test").header("alg", "none").subject("owner").build();
  final GuideApi api = new GuideApi(mock(ObjectStore.class), jdbc, mock(Changes.class), provider,
      mock(TripAccess.class), mock(Validator.class), "http://trip", "http://discovery");

  @Test void legacyClientsDefaultToNoHistorySharing() throws Exception {
    var request = new ObjectMapper().readValue("{\"text\":\"Hello\"}", GuideApi.Message.class);
    assertFalse(request.useContext());
    when(jdbc.queryForObject(anyString(), eq(Integer.class), eq("conversation"), eq("owner"))).thenReturn(1);
    when(provider.perform(eq("chat"), anyMap())).thenThrow(new IllegalStateException("stop before persistence"));
    assertThrows(IllegalStateException.class, () -> api.message("conversation", jwt, request));
    verify(provider).perform("chat", Map.of("text", "Hello"));
    // Only the ownership query runs: no history read for a non-consenting client.
    verify(jdbc).queryForObject(anyString(), eq(Integer.class), eq("conversation"), eq("owner"));
    verifyNoMoreInteractions(jdbc);
  }
  @Test void anotherOwnersConversationCannotReachProvider() {
    when(jdbc.queryForObject(anyString(), eq(Integer.class), eq("foreign"), eq("owner"))).thenReturn(0);
    assertThrows(ResponseStatusException.class,
        () -> api.message("foreign", jwt, new GuideApi.Message("Hello", true)));
    verifyNoInteractions(provider);
  }
}
