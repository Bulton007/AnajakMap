package com.anajakmap.discovery;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.*;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class PlacePhotosTest {
  final ObjectMapper json=new ObjectMapper();
  final Map<String,Object> place=Map.of("id","osm:R:1","name","Kampot","latitude",10.61,"longitude",104.18);
  final String metadata="""
    {"thumburl":"https://upload.wikimedia.org/image.jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:Kampot.jpg",
     "extmetadata":{"Artist":{"value":"<a>Photographer</a>"},"LicenseShortName":{"value":"CC BY-SA 4.0"},
     "LicenseUrl":{"value":"https://creativecommons.org/licenses/by-sa/4.0/"},"Credit":{"value":"Own work"}}}
    """;
  @Test void requiresExactPlaceAndNearbyCoordinate() throws Exception {
    assertTrue(PlacePhotos.matches(place,json.readTree("{\"title\":\"Kampot\",\"coordinates\":[{\"lat\":10.61,\"lon\":104.18}]}")));
    assertFalse(PlacePhotos.matches(place,json.readTree("{\"title\":\"Kampot\",\"coordinates\":[{\"lat\":13,\"lon\":104}]}")));
    assertFalse(PlacePhotos.matches(place,json.readTree("{\"title\":\"Kampot hotel\",\"coordinates\":[{\"lat\":10.61,\"lon\":104.18}]}")));
    var temple=Map.<String,Object>of("name","Baphuon temple","latitude",13.443,"longitude",103.857);
    assertTrue(PlacePhotos.matches(temple,json.readTree("{\"title\":\"Baphuon\",\"coordinates\":[{\"lat\":13.443,\"lon\":103.857}]}")));
    assertFalse(PlacePhotos.matches(temple,json.readTree("{\"title\":\"Banteay Srei\",\"coordinates\":[{\"lat\":13.443,\"lon\":103.857}]}")));
  }
  @Test void requiresPermittedLicenseAndTrustedImageHost() throws Exception {
    assertEquals("Photographer",PlacePhotos.metadata(json.readTree(metadata)).get("artist"));
    assertFalse(PlacePhotos.metadata(json.readTree(metadata.replace("upload.wikimedia.org","thumb.wikimedia.org"))).isEmpty());
    assertTrue(PlacePhotos.metadata(json.readTree(metadata.replace("CC BY-SA 4.0","All rights reserved"))).isEmpty());
    assertTrue(PlacePhotos.metadata(json.readTree(metadata.replace("upload.wikimedia.org","untrusted.example"))).isEmpty());
  }
  @SuppressWarnings("unchecked")
  @Test void batchLookupCachesAndOutageDoesNotBreakSearch() throws Exception {
    var redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);
    when(redis.opsForValue()).thenReturn(values);when(values.setIfAbsent(anyString(),eq("1"),any(Duration.class))).thenReturn(true);
    var builder=RestClient.builder().baseUrl("https://wiki.test");var server=MockRestServiceServer.bindTo(builder).build();
    server.expect(anything()).andRespond(withSuccess("""
      {"query":{"pages":[{"title":"Kampot","coordinates":[{"lat":10.61,"lon":104.18}],"pageimage":"Kampot.jpg"}]}}
      """,MediaType.APPLICATION_JSON));
    server.expect(anything()).andRespond(withSuccess("{\"query\":{\"pages\":[{\"title\":\"File:Kampot.jpg\",\"imageinfo\":["+metadata+"]}]}}",MediaType.APPLICATION_JSON));
    var client=builder.build();var photos=new PlacePhotos(client,client,client,redis,json);
    assertTrue(photos.photos(List.of(place)).containsKey("osm:R:1"));
    verify(values).set(startsWith("place-photos:v4:"),anyString(),eq(Duration.ofHours(24)));
    server.verify();server.reset();
    server.expect(anything()).andRespond(withServerError());
    assertTrue(photos.photos(List.of(place)).isEmpty());
  }
}
