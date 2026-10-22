package com.anajakmap.discovery;

import com.anajakmap.platform.Changes;
import com.fasterxml.jackson.databind.*;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.*;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

/** Cambodia-only search. Never replaces an upstream error with unrelated fixtures. */
@Component
public class PhotonPlaces {
  private final String url;
  private final RestClient client;
  private final StringRedisTemplate redis;
  private final ObjectMapper mapper;
  @org.springframework.beans.factory.annotation.Autowired
  public PhotonPlaces(@Value("${PHOTON_BASE_URL:}") String url, StringRedisTemplate redis, ObjectMapper mapper) {
    this.url=url; this.redis=redis; this.mapper=mapper;
    var factory=new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build());
    factory.setReadTimeout(Duration.ofSeconds(20));
    client=RestClient.builder().baseUrl(url.isBlank()?"https://photon.komoot.io":url).requestFactory(factory).build();
  }
  PhotonPlaces(RestClient client,StringRedisTemplate redis,ObjectMapper mapper){this.url="test";this.client=client;this.redis=redis;this.mapper=mapper;}
  boolean enabled(){return !url.isBlank();}
  public List<Map<String,Object>> search(String query,int page,int size) {
    String normalized=query.strip().replaceAll("\\s+"," ").toLowerCase(Locale.ROOT);
    if(normalized.isBlank()||normalized.length()>200||page<0||size<1||size>100)throw new IllegalArgumentException();
    long offset=(long)page*size;
    if(offset>=50)return List.of();
    String key="photon:kh:en:v2:"+Changes.hash(normalized);
    try {
      String cached=redis.opsForValue().get(key);
      JsonNode response;
      if(cached!=null)response=mapper.readTree(cached);
      else {
        if(!Boolean.TRUE.equals(redis.opsForValue().setIfAbsent("photon:kh:request", "1",Duration.ofSeconds(2)))) {
          throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Please wait two seconds before searching again") {
            @Override public HttpHeaders getHeaders(){var headers=new HttpHeaders();headers.set("Retry-After","2");return headers;}
          };
        }
        response=client.get().uri(b->b.path("/api/").queryParam("q",normalized).queryParam("countrycode","KH").queryParam("lang","en").queryParam("limit",50).build())
          .header("User-Agent","AnajakTravel/1.0 (Cambodia place search)").retrieve().body(JsonNode.class);
        if(response==null||!response.path("features").isArray())throw new IllegalStateException("Invalid place response");
        redis.opsForValue().set(key,mapper.writeValueAsString(response),Duration.ofHours(24));
      }
      var results=normalize(response);
      return results.subList((int)Math.min(offset,results.size()),(int)Math.min(offset+size,results.size()));
    } catch(ResponseStatusException e){throw e;}
    catch(Exception e){
      Throwable cause=e; while(cause.getCause()!=null)cause=cause.getCause();
      org.slf4j.LoggerFactory.getLogger(PhotonPlaces.class).warn("place_search_unavailable type={}",cause.getClass().getSimpleName());
      throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Place search is temporarily unavailable. Please try again later.");
    }
  }
  static List<Map<String,Object>> normalize(JsonNode response) {
    var results=new LinkedHashMap<String,Map<String,Object>>();
    for(JsonNode f:response.path("features")) {
      var p=f.path("properties");var c=f.path("geometry").path("coordinates");
      if(!p.path("countrycode").asText().equalsIgnoreCase("KH")||!c.isArray()||c.size()<2||!c.get(0).isNumber()||!c.get(1).isNumber())continue;
      double lon=c.get(0).asDouble(),lat=c.get(1).asDouble();
      if(!Double.isFinite(lat)||!Double.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180)continue;
      String type=p.path("osm_type").asText(),osm=p.path("osm_id").asText(),name=p.path("name").asText();
      if(name.isBlank()||osm.isBlank()||!List.of("N","W","R").contains(type))continue;
      var item=new LinkedHashMap<String,Object>();
      String id="osm:"+type+":"+osm;
      item.put("id",id);item.put("name",name);item.put("latitude",lat);item.put("longitude",lon);
      item.put("category",p.path("osm_value").asText("place"));
      var address=new LinkedHashSet<String>();
      for(String field:List.of("street","city","district","state","country"))if(!p.path(field).asText().isBlank())address.add(p.path(field).asText());
      item.put("address",String.join(", ",address));item.put("source","© OpenStreetMap contributors · Photon");
      item.put("mock",false);item.put("rpgEligible",false);
      results.putIfAbsent(id,item);
    }
    return new ArrayList<>(results.values());
  }
}
