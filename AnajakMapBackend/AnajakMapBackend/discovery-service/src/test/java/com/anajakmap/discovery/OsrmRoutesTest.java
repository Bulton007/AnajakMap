package com.anajakmap.discovery;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class OsrmRoutesTest {
  final RestClient.Builder builder = RestClient.builder().baseUrl("https://router.example.test");
  final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
  final Map<String,String> input = Map.of("originLat","11.5","originLon","104.9","destinationLat","11.6","destinationLon","104.91","mode","driving");
  @Test void usesActualGeometryAndMetricEstimates() {
    server.expect(requestTo(org.hamcrest.Matchers.containsString("geometries=geojson")))
      .andRespond(withSuccess("{\"code\":\"Ok\",\"routes\":[{\"distance\":1234,\"duration\":321,\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[104.9,11.5],[104.91,11.6]]}}]}", MediaType.APPLICATION_JSON));
    var result = new OsrmRoutes(builder.build()).route(input);
    assertEquals(1234.0,result.get("distanceMeters"));
    assertEquals(321.0,result.get("durationSeconds"));
    assertEquals(false,result.get("trafficAware"));
    assertEquals(2,((List<?>)result.get("coordinates")).size());
    server.verify();
  }
  @Test void missingProviderAndUnsupportedModeCannotFabricateRoutes() {
    var router = new OsrmRoutes((RestClient)null);
    assertEquals(503,assertThrows(ResponseStatusException.class,()->router.route(input)).getStatusCode().value());
    var walking = new HashMap<>(input); walking.put("mode","walking");
    assertEquals(400,assertThrows(ResponseStatusException.class,()->router.route(walking)).getStatusCode().value());
    var invalid = new HashMap<>(input); invalid.put("originLat","NaN");
    assertThrows(IllegalArgumentException.class,()->router.route(invalid));
  }
  @Test void noRouteDoesNotBecomeADevelopmentEstimate() {
    server.expect(anything()).andRespond(withSuccess("{\"code\":\"NoRoute\",\"routes\":[]}",MediaType.APPLICATION_JSON));
    assertEquals(404,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
}
