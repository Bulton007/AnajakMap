package com.anajakmap.aiguide;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import com.anajakmap.platform.RateLimit;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.*;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class RecommendationsTest {
  final RestClient.Builder builder=RestClient.builder().baseUrl("http://discovery");
  final MockRestServiceServer server=MockRestServiceServer.bindTo(builder).build();
  final GuideProvider provider=mock(GuideProvider.class);
  final StringRedisTemplate redis=mock(StringRedisTemplate.class);
  final RecommendationsApi api=new RecommendationsApi(builder.build(),provider,mock(RateLimit.class),redis);
  final Jwt user=Jwt.withTokenValue("test").header("alg","none").claim("sub","account").build();
  void places() {
    server.expect(requestTo("http://discovery/api/v1/discovery/places?query=temple%20Siem%20Reap&size=20"))
      .andExpect(header("Authorization","Bearer local-token"))
      .andRespond(withSuccess("{\"data\":[{\"id\":\"osm:N:123\",\"name\":\"Cafe\",\"category\":\"cafe\"},{\"id\":\"osm:W:456\",\"name\":\"Temple\",\"category\":\"place_of_worship\"}]}",MediaType.APPLICATION_JSON));
  }
  RecommendationsApi.Request request(boolean ai){return new RecommendationsApi.Request("Siem Reap",List.of("culture"),"balanced","en",ai);}
  @Test void preferenceMatchesAreUsefulWithoutAnyModelCall() {
    places();
    Map result=(Map)api.recommend(user,"Bearer local-token",request(false));
    assertEquals("preference_match",result.get("mode"));
    assertEquals("not_requested",result.get("aiStatus"));
    Map first=(Map)((List)result.get("items")).getFirst();
    assertEquals("Temple",first.get("name"));
    assertEquals("culture",first.get("matchedInterest"));
    assertTrue(first.get("references").toString().contains("https://www.openstreetmap.org/way/456"));
    verifyNoInteractions(provider);server.verify();
  }
  @Test void optionalAiFailurePreservesPlacesAndHonestMode() {
    places();when(provider.recommend(anyList(),anyList(),eq("en"))).thenThrow(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE));
    Map result=(Map)api.recommend(user,"Bearer local-token",request(true));
    assertEquals("preference_match",result.get("mode"));assertEquals("unavailable",result.get("aiStatus"));
    assertEquals(2,((List)result.get("items")).size());
  }
  @Test void aiUsesSuppliedIndicesAndSourcesRemainServerOwned() {
    places();when(provider.recommend(anyList(),anyList(),eq("en"))).thenReturn(List.of(Map.of("placeIndex",0,"reason","Fits your culture interest.")));
    Map result=(Map)api.recommend(user,"Bearer local-token",request(true));
    assertEquals("ai_grounded",result.get("mode"));
    Map first=(Map)((List)result.get("items")).getFirst();
    assertEquals("osm:W:456",first.get("id"));
    assertEquals("Fits your culture interest.",first.get("reason"));
  }
  @Test void rejectsUnsupportedInterestsAndUntrustedSourceIdentifiers() {
    assertThrows(IllegalArgumentException.class,()->api.recommend(user,"Bearer local-token",new RecommendationsApi.Request("Siem Reap",List.of("fake"),"balanced","en",false)));
    assertTrue(RecommendationsApi.references(Map.of("id","osm:N:https://evil.test")).isEmpty());
    assertTrue(RecommendationsApi.references(Map.of("id","fixture")).isEmpty());
  }
  @Test void quotaCooldownNeverCallsModelAgain() {
    places();when(redis.getExpire("recommendations:ai:cooldown")).thenReturn(5000L);
    Map result=(Map)api.recommend(user,"Bearer local-token",request(true));
    assertEquals("rate_limited",result.get("aiStatus"));assertNotNull(result.get("retryAt"));verifyNoInteractions(provider);
  }
}
