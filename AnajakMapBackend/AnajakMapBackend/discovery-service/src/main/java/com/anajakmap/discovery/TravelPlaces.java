package com.anajakmap.discovery;

import com.anajakmap.platform.Changes;
import com.fasterxml.jackson.databind.*;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.*;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/** Adds geographically verified sights to an exact city search, retaining OSM results. */
@Component
public class TravelPlaces {
  private static final Pattern SIGHT = Pattern.compile(
      "(?i)\\b(palace|museum|wat|temple|pagoda|market|monument|memorial|park|beach|waterfall|national park|mosque|cathedral|restaurant)\\b");
  private static final Pattern EXCLUDED = Pattern.compile("(?i)\\b(station|hospital|university|embassy|school|republic|kingdom|battle|massacre)\\b");
  private final PhotonPlaces photon;
  private final RestClient wiki;
  private final StringRedisTemplate redis;
  private final ObjectMapper mapper;

  @Autowired public TravelPlaces(PhotonPlaces photon, StringRedisTemplate redis, ObjectMapper mapper) {
    this(photon, client(), redis, mapper);
  }
  TravelPlaces(PhotonPlaces photon, RestClient wiki, StringRedisTemplate redis, ObjectMapper mapper) {
    this.photon=photon;this.wiki=wiki;this.redis=redis;this.mapper=mapper;
  }
  private static RestClient client() {
    var factory=new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
    factory.setReadTimeout(Duration.ofSeconds(8));
    return RestClient.builder().baseUrl("https://en.wikipedia.org").requestFactory(factory)
        .defaultHeader("User-Agent","AnajakTravel/1.0 (https://github.com/Bulton007/AnajakMap)").build();
  }
  public List<Map<String,Object>> search(String query,int page,int size) {
    if(page<0||size<1||size>100)throw new IllegalArgumentException();
    // Pagination is applied after enrichment so changing pages never skips OSM results.
    var geocoded=photon.search(query,0,50);
    var city=geocoded.stream().filter(p->PlacePhotos.normal(query).equals(PlacePhotos.normal(p.get("name").toString())))
        .filter(p->List.of("city","town","village").contains(p.get("category"))).findFirst();
    var combined=new ArrayList<Map<String,Object>>();
    if(city.isPresent()) combined.addAll(sights(city.get()));
    for(var place:geocoded) {
      boolean duplicate=combined.stream().anyMatch(p->PlacePhotos.articleName(p.get("name").toString()).equals(PlacePhotos.articleName(place.get("name").toString()))
          &&distance(place,p)<.2);
      if(!duplicate)combined.add(place);
    }
    long offset=(long)page*size;
    return combined.subList((int)Math.min(offset,combined.size()),(int)Math.min(offset+size,combined.size()));
  }
  @SuppressWarnings("unchecked")
  private List<Map<String,Object>> sights(Map<String,Object> city) {
    String key="travel-sights:v1:"+Changes.hash(city.get("id").toString());
    try {
      String cached=redis.opsForValue().get(key);
      if(cached!=null)return mapper.readValue(cached,List.class);
      // At most one public geosearch for this city per cache lifetime.
      if(!Boolean.TRUE.equals(redis.opsForValue().setIfAbsent(key+":request","1",Duration.ofSeconds(10))))return List.of();
      var response=wiki.get().uri(b->b.path("/w/api.php").queryParam("action","query")
          .queryParam("format","json").queryParam("formatversion",2).queryParam("generator","geosearch")
          .queryParam("ggscoord",city.get("latitude")+"|"+city.get("longitude")).queryParam("ggsradius",10000)
          .queryParam("ggslimit",50).queryParam("ggsnamespace",0).queryParam("prop","coordinates|pageimages")
          .queryParam("colimit","max").queryParam("piprop","name").queryParam("pilicense","free")
          .queryParam("pilimit",50).build()).retrieve().body(JsonNode.class);
      if(response==null||response.has("error"))throw new IllegalStateException();
      var result=normalize(response,city);
      redis.opsForValue().set(key,mapper.writeValueAsString(result),result.isEmpty()?Duration.ofMinutes(5):Duration.ofHours(24));
      return result;
    } catch(Exception failure) {
      org.slf4j.LoggerFactory.getLogger(TravelPlaces.class).warn("travel_sights_unavailable type={}",failure.getClass().getSimpleName());
      return List.of(); // The original geocoder results remain available.
    }
  }
  static List<Map<String,Object>> normalize(JsonNode response,Map<String,Object> city) {
    var result=new ArrayList<Map<String,Object>>();
    for(var page:response.path("query").path("pages")) {
      String title=page.path("title").asText(),file=page.path("pageimage").asText();
      var c=page.path("coordinates").path(0);
      if(!page.path("pageid").canConvertToLong()||!SIGHT.matcher(title).find()||EXCLUDED.matcher(title).find()
          ||!file.matches("(?i).+\\.(jpe?g|png)")||!c.path("lat").isNumber()||!c.path("lon").isNumber())continue;
      double lat=c.path("lat").asDouble(),lon=c.path("lon").asDouble();
      if(!Double.isFinite(lat)||!Double.isFinite(lon)||lat<10||lat>15||lon<102||lon>108)continue;
      var item=new LinkedHashMap<String,Object>();
      item.put("id","wikipedia:en:"+page.path("pageid").asLong());item.put("name",title);
      item.put("latitude",lat);item.put("longitude",lon);item.put("category","attraction");
      if(distance(city,item)>10.1)continue;
      item.put("address","Near "+city.get("name")+", Cambodia");item.put("source","Wikipedia · geolocated travel sight");
      item.put("wikipediaImage",file);item.put("wikipediaTitle",title);
      item.put("mock",false);item.put("rpgEligible",false);
      result.add(item);
    }
    result.sort(Comparator.comparingDouble(p->distance(city,p)));
    return result.stream().limit(12).toList();
  }
  static double distance(Map<String,Object> first,Map<String,Object> second) {
    double lat=((Number)first.get("latitude")).doubleValue(),lon=((Number)first.get("longitude")).doubleValue();
    double otherLat=((Number)second.get("latitude")).doubleValue(),otherLon=((Number)second.get("longitude")).doubleValue();
    double a=Math.pow(Math.sin(Math.toRadians(otherLat-lat)/2),2)+Math.cos(Math.toRadians(lat))*Math.cos(Math.toRadians(otherLat))*Math.pow(Math.sin(Math.toRadians(otherLon-lon)/2),2);
    return 6371*2*Math.asin(Math.sqrt(Math.min(1,a)));
  }
}
