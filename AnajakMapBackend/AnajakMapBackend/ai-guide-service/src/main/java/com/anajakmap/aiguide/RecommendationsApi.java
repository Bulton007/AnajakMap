package com.anajakmap.aiguide;

import com.anajakmap.platform.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

/** Grounded retrieval -> preference ranking -> optional model explanation. No automatic trip writes. */
@RestController
@RequestMapping("/api/v1/guide/recommendations")
public class RecommendationsApi {
  private final RestClient discovery;
  private final GuideProvider provider;
  private final RateLimit limit;
  private final StringRedisTemplate redis;
  private static final Set<String> INTERESTS = Set.of("culture","food","nature","beach","city");
  @org.springframework.beans.factory.annotation.Autowired
  public RecommendationsApi(@Value("${anajak.discovery-url}") String url, GuideProvider provider, RateLimit limit, StringRedisTemplate redis) {
    this.discovery=HttpClients.client(url,Duration.ofSeconds(23)); this.provider=provider; this.limit=limit; this.redis=redis;
  }
  RecommendationsApi(RestClient discovery, GuideProvider provider, RateLimit limit, StringRedisTemplate redis) {
    this.discovery=discovery; this.provider=provider;this.limit=limit;this.redis=redis;
  }
  public record Request(@NotBlank @Size(max=120) String destination, @NotEmpty @Size(max=5) List<@NotBlank String> interests,
      @Pattern(regexp="relaxed|balanced|active") String pace, @Pattern(regexp="en|km") String language, boolean useAi) {}

  @PostMapping
  public Object recommend(@AuthenticationPrincipal Jwt jwt, @RequestHeader("Authorization") String bearer, @Valid @RequestBody Request request) {
    if (!INTERESTS.containsAll(request.interests()) || request.pace()==null || request.language()==null) throw new IllegalArgumentException("Invalid preferences");
    limit.check("recommendations:"+jwt.getSubject(),20,60);
    String focus=request.interests().getFirst();
    String term=switch(focus){case "culture"->"temple";case "food"->"restaurant";case "nature"->"park";case "beach"->"beach";default->"";};
    String query=(term+" "+request.destination().strip()).strip();
    Map envelope=discovery.get().uri(b->b.path("/api/v1/discovery/places").queryParam("query",query).queryParam("size",20).build()).header("Authorization",bearer).retrieve().body(Map.class);
    if (envelope==null || !(envelope.get("data") instanceof List<?> raw)) throw new IllegalStateException("Invalid discovery response");
    var candidates=new ArrayList<Map<String,Object>>();
    for (Object value:raw) if (value instanceof Map<?,?> row && row.get("id") instanceof String && row.get("name") instanceof String) candidates.add(new LinkedHashMap<>((Map<String,Object>)row));
    candidates.sort(Comparator.comparingInt((Map<String,Object> p)->score(p,request.interests())).reversed());
    int max=switch(request.pace()){case "relaxed"->3;case "active"->8;default->5;};
    String mode="preference_match", aiStatus="not_requested";
    var selection=new ArrayList<Map<String,Object>>();
    for(int i=0;i<Math.min(max,candidates.size());i++) selection.add(Map.of("placeIndex",i,"reason",""));
    Long cooldown=redis.getExpire("recommendations:ai:cooldown");
    if(request.useAi() && !candidates.isEmpty()) {
      if(cooldown!=null && cooldown>0) aiStatus="rate_limited";
      else {
        limit.check("recommendations:ai:"+jwt.getSubject(),4,60);
        try { selection=new ArrayList<>(provider.recommend(candidates,request.interests(),request.language())); mode="ai_grounded";aiStatus="available"; }
        catch(ResponseStatusException e) {
          aiStatus=e.getStatusCode().value()==429?"rate_limited":"unavailable";
          if(e.getStatusCode().value()==429) try {
            long delay=Long.parseLong(e.getHeaders().getFirst("Retry-After"));
            if(delay>0) redis.opsForValue().set("recommendations:ai:cooldown","1",Duration.ofSeconds(Math.min(delay,604800)));
          } catch(Exception ignored) { }
        } catch(Exception e) { aiStatus="unavailable"; }
      }
    }
    var results=new ArrayList<Map<String,Object>>();
    var seen=new HashSet<Integer>();
    for(var choice:selection) {
      int index=((Number)choice.get("placeIndex")).intValue();
      if(index<0 || index>=candidates.size() || !seen.add(index)) throw new IllegalArgumentException("Ungrounded recommendation");
      var place=new LinkedHashMap<>(candidates.get(index));
      place.put("reason",choice.getOrDefault("reason",""));
      place.put("matchedInterest",request.interests().stream().filter(i->score(place,List.of(i))>0).findFirst().orElse(""));
      place.put("references",references(place));
      results.add(place); if(results.size()==max)break;
    }
    var response=new LinkedHashMap<String,Object>();
    response.put("items",results);response.put("mode",mode);response.put("aiStatus",aiStatus);response.put("query",query);response.put("retrievedAt",Instant.now());
    cooldown=redis.getExpire("recommendations:ai:cooldown");
    if(cooldown!=null && cooldown>0)response.put("retryAt",Instant.now().plusSeconds(cooldown));
    return response;
  }
  static int score(Map<String,Object> place,List<String> interests) {
    String category=Objects.toString(place.get("category"),"").toLowerCase(Locale.ROOT);
    return interests.stream().anyMatch(i->switch(i){
      case "culture"->Set.of("temple","place_of_worship","museum","monument","archaeological_site","attraction").contains(category);
      case "food"->Set.of("restaurant","cafe","food_court","marketplace").contains(category);
      case "nature"->Set.of("park","nature_reserve","waterfall","peak","forest").contains(category);
      case "beach"->category.equals("beach");default->Set.of("city","town","village").contains(category);
    })?10:0;
  }
  static List<Map<String,String>> references(Map<String,Object> place) {
    String id=Objects.toString(place.get("id"),"");
    if(!id.matches("osm:[NWR]:[0-9]+"))return List.of();
    String[] parts=id.split(":");
    String type=switch(parts[1]){case "N"->"node";case "W"->"way";default->"relation";};
    return List.of(Map.of("title","OpenStreetMap","url","https://www.openstreetmap.org/"+type+"/"+parts[2],"supports","name_location_category"));
  }
}
