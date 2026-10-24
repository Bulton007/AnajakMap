package com.anajakmap.discovery;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
class DestinationWeatherTest {
  final RestClient.Builder builder=RestClient.builder().baseUrl("https://api.open-meteo.com");
  final MockRestServiceServer server=MockRestServiceServer.bindTo(builder).build();
  final PhotonPlaces places=mock(PhotonPlaces.class);
  @Test void coordinatesScopeCacheAndRetainProviderObservationTime() {
    server.expect(requestTo(org.hamcrest.Matchers.containsString("latitude=11.5")))
      .andRespond(withSuccess("{\"current\":{\"temperature_2m\":29.5,\"weather_code\":3,\"time\":\"2026-10-24T02:00\"}}",MediaType.APPLICATION_JSON));
    server.expect(requestTo(org.hamcrest.Matchers.containsString("latitude=13.4")))
      .andRespond(withSuccess("{\"current\":{\"temperature_2m\":27,\"weather_code\":61,\"time\":\"2026-10-24T02:00\"}}",MediaType.APPLICATION_JSON));
    var weather=new DestinationWeather(true,places,builder.build());
    var first=Map.of("latitude","11.5","longitude","104.9");
    assertEquals(29.5,weather.weather(first).get("temperatureCelsius"));
    assertEquals(29.5,weather.weather(first).get("temperatureCelsius"));
    assertEquals(27,weather.weather(Map.of("latitude","13.4","longitude","103.8")).get("temperatureCelsius"));
    assertEquals("2026-10-24T02:00Z",weather.weather(first).get("updatedAt"));
    server.verify();
  }
  @Test void disabledOrInvalidWeatherNeverReturnsSunnyFixtures() {
    assertEquals(503,assertThrows(ResponseStatusException.class,()->new DestinationWeather(false,places,builder.build()).weather(Map.of())).getStatusCode().value());
    assertThrows(IllegalArgumentException.class,()->new DestinationWeather(true,places,builder.build()).weather(Map.of("latitude","NaN","longitude","100")));
    server.verify();
  }
}
