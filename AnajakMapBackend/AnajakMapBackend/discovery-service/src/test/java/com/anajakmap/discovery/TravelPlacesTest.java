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

class TravelPlacesTest {
  final ObjectMapper json=new ObjectMapper();
  final Map<String,Object> city=Map.of("id","osm:R:1","name","Phnom Penh","latitude",11.568,"longitude",104.922,"category","city");
  static final String BODY="""
      {"query":{"pages":[
       {"pageid":10,"title":"Royal Palace of Cambodia","pageimage":"Palace.jpg","coordinates":[{"lat":11.564,"lon":104.931}]},
       {"pageid":11,"title":"Wat Phnom","pageimage":"Wat.jpg","coordinates":[{"lat":11.576,"lon":104.923}]},
       {"pageid":12,"title":"Night Market BRT station","pageimage":"Station.jpg","coordinates":[{"lat":11.574,"lon":104.927}]},
       {"pageid":13,"title":"National Museum of Cambodia","pageimage":"Map.svg","coordinates":[{"lat":11.565,"lon":104.929}]},
       {"pageid":14,"title":"Remote Temple","pageimage":"Remote.jpg","coordinates":[{"lat":13.4,"lon":103.8}]}]}}
      """;

  @Test void onlyNearbyPhotographedTravelSightsAreAdded() throws Exception {
    var places=TravelPlaces.normalize(json.readTree(BODY),city);
    assertEquals(2,places.size());
    assertTrue(places.stream().anyMatch(p->p.get("name").equals("Royal Palace of Cambodia")));
    assertTrue(places.stream().allMatch(p->p.get("id").toString().startsWith("wikipedia:en:")&&p.get("rpgEligible").equals(false)));
    assertTrue(places.stream().allMatch(p->p.get("source").toString().contains("Wikipedia")));
  }
  @SuppressWarnings("unchecked")
  @Test void exactCitySearchAddsRealSightsAndPaginationKeepsEveryGeocoderResult() throws Exception {
    var photon=mock(PhotonPlaces.class);
    var geocoded=new ArrayList<Map<String,Object>>();geocoded.add(city);
    for(int i=0;i<22;i++)geocoded.add(Map.of("id","osm:N:"+(10+i),"name","Place "+i,"latitude",11.5,"longitude",104.9,"category","place"));
    when(photon.search("Phnom Penh",0,50)).thenReturn(geocoded);
    var redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);
    when(redis.opsForValue()).thenReturn(values);when(values.setIfAbsent(anyString(),eq("1"),any(Duration.class))).thenReturn(true);
    var builder=RestClient.builder().baseUrl("https://wiki.test");var server=MockRestServiceServer.bindTo(builder).build();
    server.expect(queryParam("generator","geosearch")).andRespond(withSuccess(BODY,MediaType.APPLICATION_JSON));
    var travel=new TravelPlaces(photon,builder.build(),redis,json);
    var first=travel.search("Phnom Penh",0,20);
    assertEquals(20,first.size());assertTrue(first.getFirst().get("id").toString().startsWith("wikipedia:"));
    verify(values).set(startsWith("travel-sights:v1:"),anyString(),eq(Duration.ofHours(24)));
    when(values.get(startsWith("travel-sights:v1:"))).thenReturn(json.writeValueAsString(TravelPlaces.normalize(json.readTree(BODY),city)));
    var second=travel.search("Phnom Penh",1,20);
    assertEquals(5,second.size());
    var all=new HashSet<Object>();first.forEach(p->all.add(p.get("id")));second.forEach(p->all.add(p.get("id")));
    assertEquals(25,all.size());server.verify();
  }
  @SuppressWarnings("unchecked")
  @Test void optionalWikipediaFailureNeverHidesOsmResultsAndNonCityDoesNotCallIt() {
    var photon=mock(PhotonPlaces.class);when(photon.search("Phnom Penh",0,50)).thenReturn(List.of(city));
    when(photon.search("Royal Palace",0,50)).thenReturn(List.of(Map.of("id","p","name","Royal Palace","category","palace")));
    var redis=mock(StringRedisTemplate.class);ValueOperations<String,String> values=mock(ValueOperations.class);
    when(redis.opsForValue()).thenReturn(values);when(values.setIfAbsent(anyString(),eq("1"),any(Duration.class))).thenReturn(true);
    var builder=RestClient.builder().baseUrl("https://wiki.test");var server=MockRestServiceServer.bindTo(builder).build();
    server.expect(anything()).andRespond(withServerError());
    var travel=new TravelPlaces(photon,builder.build(),redis,json);
    assertEquals(List.of(city),travel.search("Phnom Penh",0,20));
    assertEquals("Royal Palace",travel.search("Royal Palace",0,20).getFirst().get("name"));server.verify();
  }
}
