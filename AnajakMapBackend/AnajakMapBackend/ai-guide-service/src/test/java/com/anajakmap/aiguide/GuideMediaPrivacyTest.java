package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.anajakmap.platform.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Validator;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.server.ResponseStatusException;

class GuideMediaPrivacyTest {
  final JdbcTemplate jdbc = mock(JdbcTemplate.class);
  final GuideProvider provider = mock(GuideProvider.class);
  final ObjectStore storage = mock(ObjectStore.class);
  final Changes changes = mock(Changes.class);
  final Jwt jwt = Jwt.withTokenValue("test").header("alg", "none").subject("owner").build();
  final GuideApi api = new GuideApi(storage, jdbc, changes, provider,
      mock(TripAccess.class), mock(Validator.class), "http://trip", "http://discovery");
  GuideMediaPrivacyTest() {
    when(changes.json(any())).thenAnswer(invocation -> new ObjectMapper().writeValueAsString(invocation.getArgument(0)));
    when(provider.capabilities()).thenReturn(Map.of("voice",true,"vision",true));
  }
  @Test void unconsentedMediaCannotReachStorageOrProvider() {
    for (String operation : List.of("voice", "vision")) {
      assertThrows(IllegalArgumentException.class, () -> api.perform(operation, jwt,
          new GuideApi.Input(Map.of("mediaId","photo", "shareWithProvider",false))));
    }
    verifyNoInteractions(jdbc, storage);
    verify(provider, never()).perform(anyString(), anyMap());
  }
  @Test void anotherOwnersMediaCannotReachProvider() {
    when(jdbc.queryForList(anyString(), eq("foreign"), eq("owner"))).thenReturn(List.of());
    assertThrows(ResponseStatusException.class, () -> api.perform("voice", jwt,
        new GuideApi.Input(Map.of("mediaId","foreign", "shareWithProvider",true))));
    verify(jdbc).queryForList(contains("owner_id=?"), eq("foreign"), eq("owner"));
    verifyNoInteractions(storage);
    verify(provider, never()).perform(anyString(), anyMap());
  }
  @Test void ownedAudioUsesStoredBytesRatherThanClientBase64() {
    when(jdbc.queryForList(anyString(), eq("mine"), eq("owner")))
        .thenReturn(List.of(Map.of("OBJECT_KEY","stored-key", "MIME_TYPE","audio/wav")));
    when(storage.download("stored-key")).thenReturn(VoiceAudioTest.wave(1));
    when(provider.perform(eq("voice"), anyMap())).thenReturn(Map.of("transcript","Hello", "text","Hello traveler"));
    api.perform("voice", jwt, new GuideApi.Input(Map.of("mediaId","mine", "shareWithProvider",true,
        "audioBase64","untrusted-client-bytes")));
    var capture = ArgumentCaptor.forClass(Map.class);
    verify(provider).perform(eq("voice"), capture.capture());
    assertEquals(Base64.getEncoder().encodeToString(VoiceAudioTest.wave(1)), capture.getValue().get("audioBase64"));
    assertFalse(capture.getValue().containsKey("imageBase64"));
  }
  @Test void invalidAudioAndOversizedPhotosNeverEnterObjectStorage() {
    assertThrows(IllegalArgumentException.class, () -> api.upload(jwt,
        new MockMultipartFile("file", "test.wav", "audio/wav", new byte[]{1,2,3})));
    assertThrows(IllegalArgumentException.class, () -> api.upload(jwt,
        new MockMultipartFile("file", "test.png", "image/png", new byte[4 * 1024 * 1024 + 1])));
    verifyNoInteractions(storage, jdbc);
  }
}
