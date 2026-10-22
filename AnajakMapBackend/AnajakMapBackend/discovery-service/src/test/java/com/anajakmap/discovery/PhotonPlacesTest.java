package com.anajakmap.discovery;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.mockito.ArgumentMatchers.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.*;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class PhotonPlacesTest {
  static final String BODY="""
    {"features":[{"properties":{"name":"Kampot","countrycode":"KH","osm_type":"R","osm_id":7,"osm_value":"city","state":"Kampot","country":"Cambodia"},"geometry":{"coordinates":[104.18,10.61]}},
    {"properties":{"name":"Wrong country","countrycode":"TH","osm_type":"N","osm_id":8},"geometry":{"coordinates":[100,13]}}]}
    """;
  @SuppressWarnings("unchecked")
  @Test void cambodiaResultsAreNormalizedCachedAndPaged() throws Exception {
    var redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);
    when(redis.opsForValue()).thenReturn(values);when(values.setIfAbsent(anyString(),eq("1"),any(Duration.class))).thenReturn(true);
    var builder=RestClient.builder().baseUrl("https://provider.test");var server=MockRestServiceServer.bindTo(builder).build();
    server.expect(requestTo("https://provider.test/api/?q=kampot&countrycode=KH&lang=en&limit=50")).andRespond(withSuccess(BODY,MediaType.APPLICATION_JSON));
    var provider=new PhotonPlaces(builder.build(),redis,new ObjectMapper());
    var result=provider.search("  KAMPOT  ",0,20);
    assertEquals(1,result.size());assertEquals("osm:R:7",result.getFirst().get("id"));assertEquals(false,result.getFirst().get("mock"));
    verify(values).set(startsWith("photon:kh:en:v2:"),anyString(),eq(Duration.ofHours(24)));
    when(values.get(anyString())).thenReturn(BODY);
    assertEquals(result,provider.search("Kampot",0,20));assertTrue(provider.search("Kampot",1,20).isEmpty());
    assertTrue(provider.search("Kampot",Integer.MAX_VALUE,100).isEmpty());server.verify();
  }
  @SuppressWarnings("unchecked")
  @Test void throttleAndProviderFailuresNeverReturnFixtures() {
    var redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);when(redis.opsForValue()).thenReturn(values);
    var builder=RestClient.builder().baseUrl("https://provider.test");var server=MockRestServiceServer.bindTo(builder).build();
    var provider=new PhotonPlaces(builder.build(),redis,new ObjectMapper());
    var failure=assertThrows(ResponseStatusException.class,()->provider.search("Kampot",0,20));assertEquals(429,failure.getStatusCode().value());assertEquals("2",failure.getHeaders().getFirst("Retry-After"));
    when(values.setIfAbsent(anyString(),eq("1"),any(Duration.class))).thenReturn(true);
    server.expect(anything()).andRespond(withServerError());
    assertEquals(503,assertThrows(ResponseStatusException.class,()->provider.search("Kampot",0,20)).getStatusCode().value());server.verify();
  }
}
