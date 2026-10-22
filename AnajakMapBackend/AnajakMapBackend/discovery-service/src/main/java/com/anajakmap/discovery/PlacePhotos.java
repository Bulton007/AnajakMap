package com.anajakmap.discovery;

import com.anajakmap.platform.Changes;
import com.fasterxml.jackson.databind.*;
import java.net.URI;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.HtmlUtils;

/** Exact normalized article title plus coordinate match; no unrelated stock photos. */
@Component
public class PlacePhotos {
  private final RestClient en, km, commons;
  private final StringRedisTemplate redis;
  private final ObjectMapper mapper;
  @Autowired
  public PlacePhotos(StringRedisTemplate redis, ObjectMapper mapper) {
    this(client("https://en.wikipedia.org"), client("https://km.wikipedia.org"),
        client("https://commons.wikimedia.org"), redis, mapper);
  }
  PlacePhotos(RestClient en, RestClient km, RestClient commons, StringRedisTemplate redis, ObjectMapper mapper) {
    this.en=en; this.km=km; this.commons=commons; this.redis=redis; this.mapper=mapper;
  }
  private static RestClient client(String url) {
    var f=new JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
    f.setReadTimeout(Duration.ofSeconds(8));
    return RestClient.builder().baseUrl(url).requestFactory(f)
        .defaultHeader("User-Agent","AnajakTravel/1.0 (place photos; contact forusea168@gmail.com)").build();
  }
  public Map<String,Object> photos(List<Map<String,Object>> places) {
    if(places.isEmpty())return Map.of();
    String key="place-photos:v4:"+Changes.hash(places.toString());
    try {
      String cached=redis.opsForValue().get(key);
      if(cached!=null)return mapper.readValue(cached,Map.class);
      if(!Boolean.TRUE.equals(redis.opsForValue().setIfAbsent("place-photos:request","1",Duration.ofSeconds(3))))
        return Map.of();
      var files=new LinkedHashMap<String,String>();
      for(var entry:List.of(Map.entry(en,false),Map.entry(km,true))) {
        var selected=places.stream().filter(p->hasKhmer(p.get("name").toString())==entry.getValue()).toList();
        if(selected.isEmpty())continue;
        var variants=new LinkedHashSet<String>();
        for(var p:selected) {
          String name=p.get("name").toString().replace("|"," ");variants.add(name);
          String shortName=name.replaceFirst("(?i)\\s+temple$","").strip();
          if(shortName.length()>=4)variants.add(shortName);
        }
        String titles=String.join("|",variants);
        var response=entry.getKey().get().uri(b->b.path("/w/api.php")
            .queryParam("action","query").queryParam("format","json").queryParam("formatversion",2)
            .queryParam("prop","pageimages|coordinates").queryParam("piprop","name")
            .queryParam("pilicense","free").queryParam("pilimit",40).queryParam("colimit","max")
            .queryParam("titles",titles).build()).retrieve().body(JsonNode.class);
        if(response==null||response.has("error"))throw new IllegalStateException();
        for(var page:response.path("query").path("pages"))for(var place:selected)
          if(matches(place,page)&&!page.path("pageimage").asText().isBlank())
            files.put(place.get("id").toString(),"File:"+page.path("pageimage").asText());
      }
      var result=new LinkedHashMap<String,Object>();
      if(!files.isEmpty()) {
        var response=commons.get().uri(b->b.path("/w/api.php").queryParam("action","query")
            .queryParam("format","json").queryParam("formatversion",2).queryParam("prop","imageinfo")
            .queryParam("iiprop","url|extmetadata").queryParam("iiurlwidth",800)
            .queryParam("titles",String.join("|",new LinkedHashSet<>(files.values()))).build()).retrieve().body(JsonNode.class);
        if(response==null||response.has("error"))throw new IllegalStateException();
        for(var page:response.path("query").path("pages")) {
          var photo=metadata(page.path("imageinfo").path(0));
          if(photo.isEmpty())continue;
          files.forEach((id,file)->{if(normal(file).equals(normal(page.path("title").asText())))result.put(id,photo);});
        }
      }
      org.slf4j.LoggerFactory.getLogger(PlacePhotos.class).info("place_photos_matched files={} licensed={}",files.size(),result.size());
      redis.opsForValue().set(key,mapper.writeValueAsString(result),Duration.ofHours(24));
      return result;
    } catch(Exception e) {
      // Search results remain usable when optional photo services are unavailable.
      Throwable cause=e;while(cause.getCause()!=null)cause=cause.getCause();
      org.slf4j.LoggerFactory.getLogger(PlacePhotos.class).warn("place_photos_unavailable type={}",cause.getClass().getSimpleName());
      return Map.of();
    }
  }
  static boolean hasKhmer(String value){return value.codePoints().anyMatch(c->c>=0x1780&&c<=0x17ff);}
  static String normal(String value){return value.replace('_',' ').strip().toLowerCase(Locale.ROOT);}
  static String articleName(String value) { return normal(value).replaceFirst("\\s+temple$",""); }
  static boolean matches(Map<String,Object> p,JsonNode article) {
    if(!articleName(p.get("name").toString()).equals(articleName(article.path("title").asText())))return false;
    var c=article.path("coordinates").path(0);
    if(!c.path("lat").isNumber()||!c.path("lon").isNumber())return false;
    double lat=((Number)p.get("latitude")).doubleValue(),lon=((Number)p.get("longitude")).doubleValue();
    double a=Math.pow(Math.sin(Math.toRadians(c.path("lat").asDouble()-lat)/2),2)
        +Math.cos(Math.toRadians(lat))*Math.cos(Math.toRadians(c.path("lat").asDouble()))
        *Math.pow(Math.sin(Math.toRadians(c.path("lon").asDouble()-lon)/2),2);
    return 6371*2*Math.asin(Math.sqrt(Math.min(1,a)))<=5;
  }
  static Map<String,Object> metadata(JsonNode info) {
    var m=info.path("extmetadata");
    String license=plain(m.path("LicenseShortName").path("value").asText());
    String artist=plain(m.path("Artist").path("value").asText());
    String url=info.path("thumburl").asText(),source=info.path("descriptionurl").asText();
    String licenseUrl=m.path("LicenseUrl").path("value").asText();
    if(!license.matches("(?i)(CC BY(?:-SA)? [1-4]\\.0|CC0(?: 1\\.0)?|Public domain)")
        ||artist.isBlank()||(!allowed(url,"upload.wikimedia.org")&&!allowed(url,"thumb.wikimedia.org"))
        ||!allowed(source,"commons.wikimedia.org"))return Map.of();
    if(licenseUrl.startsWith("//"))licenseUrl="https:"+licenseUrl;
    if(!allowed(licenseUrl,"creativecommons.org")&&!allowed(licenseUrl,"commons.wikimedia.org"))return Map.of();
    return Map.of("url",url,"sourceUrl",source,"artist",artist,"license",license,
        "licenseUrl",licenseUrl,"credit",plain(m.path("Credit").path("value").asText()));
  }
  static boolean allowed(String value,String host) {
    try{var u=URI.create(value);return "https".equals(u.getScheme())&&host.equals(u.getHost())&&u.getUserInfo()==null;}
    catch(Exception e){return false;}
  }
  static String plain(String value) {
    String text=HtmlUtils.htmlUnescape(value.replaceAll("<[^>]*>","")).strip();
    return text.substring(0,Math.min(1000,text.length()));
  }
}
