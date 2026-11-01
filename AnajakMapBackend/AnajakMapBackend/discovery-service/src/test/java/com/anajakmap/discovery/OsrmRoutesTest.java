package com.anajakmap.discovery;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.*;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.mock.env.MockEnvironment;
import java.util.concurrent.atomic.AtomicLong;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class OsrmRoutesTest {
  final RestClient.Builder builder = RestClient.builder().baseUrl("https://router.example.test");
  final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
  final Map<String,String> input = Map.of("originLat","11.5","originLon","104.9","destinationLat","11.6","destinationLon","104.91","mode","driving");
  @Test void usesActualGeometryAndMetricEstimates() {
    server.expect(requestTo(org.hamcrest.Matchers.allOf(org.hamcrest.Matchers.containsString("geometries=geojson"), org.hamcrest.Matchers.containsString("radiuses=1000;1000"))))
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
  @Test void publicDemoIsExplicitlyLabelledAndGloballyThrottled() {
    var time = new AtomicLong(1000);
    var router = new OsrmRoutes(builder.build(), true, time::get);
    String response = "{\"code\":\"Ok\",\"routes\":[{\"distance\":1234,\"duration\":321,\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[104.9,11.5],[104.91,11.6]]}}]}";
    server.expect(anything()).andRespond(withSuccess(response, MediaType.APPLICATION_JSON));
    server.expect(anything()).andRespond(withSuccess(response, MediaType.APPLICATION_JSON));
    var result = router.route(input);
    assertEquals(true, result.get("demo"));
    assertTrue(result.get("source").toString().contains("public demo"));
    var limited = assertThrows(ResponseStatusException.class, () -> router.route(input));
    assertEquals(429, limited.getStatusCode().value());
    assertEquals("1", limited.getHeaders().getFirst("Retry-After"));
    time.set(2000);
    assertEquals(1234.0, router.route(input).get("distanceMeters"));
    server.verify();
  }
  @Test void demoCannotSilentlyBecomeAProductionDependency() {
    var environment = new MockEnvironment().withProperty("OSRM_DEMO_ENABLED", "true");
    assertEquals(503, assertThrows(ResponseStatusException.class,
        () -> new OsrmRoutes(environment).route(input)).getStatusCode().value());
    environment.setProperty("OSRM_URL", "https://router.project-osrm.org");
    assertThrows(IllegalStateException.class, () -> new OsrmRoutes(environment));
    environment.setActiveProfiles("dev");
    assertDoesNotThrow(() -> new OsrmRoutes(environment));
  }
  @Test void noRoadSegmentHasAnHonestNotFoundState() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.BAD_REQUEST)
        .body("{\"code\":\"NoSegment\"}").contentType(MediaType.APPLICATION_JSON));
    assertEquals(404, assertThrows(ResponseStatusException.class,
        () -> new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void providerRateLimitPreservesRetryTiming() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.TOO_MANY_REQUESTS).header("Retry-After", "12"));
    var limited = assertThrows(ResponseStatusException.class,
        () -> new OsrmRoutes(builder.build()).route(input));
    assertEquals(429, limited.getStatusCode().value());
    assertEquals("12", limited.getHeaders().getFirst("Retry-After"));
    server.verify();
  }
  @Test void disconnectedRoadNetworksNeverAcceptProviderSnappingAnotherCountry() {
    server.expect(anything()).andRespond(withSuccess("{\"code\":\"Ok\",\"routes\":[{\"distance\":14647967,\"duration\":100000,\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[-9.497727,38.78069],[104.91,11.6]]}}]}",MediaType.APPLICATION_JSON));
    var fromCalifornia = new HashMap<>(input);
    fromCalifornia.put("originLat", "37.422");
    fromCalifornia.put("originLon", "-122.084");
    assertEquals(404,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(fromCalifornia)).getStatusCode().value());
    server.verify();
  }
  @Test void aFarDestinationSnapIsAlsoRejected() {
    server.expect(anything()).andRespond(withSuccess("{\"code\":\"Ok\",\"routes\":[{\"distance\":1234,\"duration\":321,\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[104.9,11.5],[105.91,12.6]]}}]}",MediaType.APPLICATION_JSON));
    assertEquals(404,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void prettyPrintedProviderNoRouteRetainsItsMeaning() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.BAD_REQUEST).body("{\n  \"code\" : \"NoRoute\"\n}").contentType(MediaType.APPLICATION_JSON));
    assertEquals(404,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void tooBigMeansUnsupportedRouteRatherThanNetworkFailure() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.BAD_REQUEST).body("{\"code\":\"TooBig\"}").contentType(MediaType.APPLICATION_JSON));
    assertEquals(422,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void invalidRouteOptionsAreNotMisreportedAsNetworkFailure() {
    server.expect(anything()).andRespond(withStatus(HttpStatus.BAD_REQUEST).body("{\"code\":\"InvalidValue\"}").contentType(MediaType.APPLICATION_JSON));
    assertEquals(400,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void malformedProviderResponseCannotMasqueradeAsNoRoute() {
    server.expect(anything()).andRespond(withSuccess("{}",MediaType.APPLICATION_JSON));
    assertEquals(502,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
  @Test void excessiveGeometryRetainsUnsupportedRouteStatus() {
    String points = String.join(",", Collections.nCopies(50000,"[104.9,11.5]")) + ",[104.91,11.6]";
    server.expect(anything()).andRespond(withSuccess("{\"code\":\"Ok\",\"routes\":[{\"distance\":1234,\"duration\":321,\"geometry\":{\"type\":\"LineString\",\"coordinates\":["+points+"]}}]}",MediaType.APPLICATION_JSON));
    assertEquals(422,assertThrows(ResponseStatusException.class,()->new OsrmRoutes(builder.build()).route(input)).getStatusCode().value());
    server.verify();
  }
}
