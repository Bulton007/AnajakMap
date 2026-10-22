package com.anajakmap.discovery.rpg;

import com.anajakmap.platform.RateLimit;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/rpg")
public class RpgApi {
  private final RpgService service;
  private final RateLimit limit;
  public RpgApi(RpgService service,RateLimit limit){this.service=service;this.limit=limit;}
  private String actor(Jwt jwt){String id=jwt.getSubject();limit.check("rpg:"+id,60,60);return id;}
  @GetMapping("/capabilities") public Object capabilities(){return service.capabilities();}
  @GetMapping("/{realm}/world") public Object world(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm){return service.world(actor(jwt),realm);}
  @GetMapping("/{realm}/profile") public Object profile(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm){return service.profile(actor(jwt),realm);}
  @PostMapping("/{realm}/encounters") public Object start(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Start input){return service.start(actor(jwt),realm,key,input);}
  @PostMapping("/{realm}/battles/{id}/actions") public Object move(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@PathVariable String id,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Move input){return service.move(actor(jwt),realm,id,key,input);}
  @PostMapping("/{realm}/quests/{id}/claim") public Object claim(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@PathVariable String id,@RequestHeader("Idempotency-Key") String key){return service.claim(actor(jwt),realm,id,key);}
  @PostMapping("/{realm}/party") public Object party(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Party input){return service.party(actor(jwt),realm,key,input);}
  @PostMapping("/{realm}/monsters/{id}/evolve") public Object evolve(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@PathVariable String id,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Evolution input){return service.evolve(actor(jwt),realm,id,key,input);}
  @PostMapping("/{realm}/inventory/purchase") public Object purchase(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Purchase input){return service.purchase(actor(jwt),realm,key,input);}
  @PostMapping("/{realm}/title") public Object title(@AuthenticationPrincipal Jwt jwt,@PathVariable String realm,@RequestHeader("Idempotency-Key") String key,@Valid @RequestBody RpgService.Title input){return service.title(actor(jwt),realm,key,input);}
}
