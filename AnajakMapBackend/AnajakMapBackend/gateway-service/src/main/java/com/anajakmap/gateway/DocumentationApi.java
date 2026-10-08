package com.anajakmap.gateway;

import com.anajakmap.platform.*;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
public class DocumentationApi {
  @GetMapping("/v3/api-docs/{service}")
  public Object docs(@PathVariable String service) {
    Map<String, Integer> ports =
        Map.of(
            "identity",
            8081,
            "trip",
            8082,
            "ai-guide",
            8083,
            "discovery",
            8084,
            "expense",
            8085,
            "reservation",
            8086,
            "journal",
            8087,
            "notification",
            8088);
    if (!ports.containsKey(service)) throw Api.missing();
    String url = System.getenv(service.toUpperCase().replace('-', '_') + "_URL");
    if (url == null) url = "http://" + service + "-service:" + ports.get(service);
    Map docs = HttpClients.client(url).get().uri("/v3/api-docs").retrieve().body(Map.class);
    docs.put("servers", List.of(Map.of("url", "/")));
    return docs;
  }
}
