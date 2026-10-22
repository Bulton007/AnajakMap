package com.anajakmap.discovery.rpg;

import com.anajakmap.platform.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.function.Supplier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

@Service
public class RpgService {
  private final JdbcTemplate db;
  private final Changes changes;
  private final ObjectMapper json;
  private final TransactionTemplate tx;
  private final boolean practice;
  private final Clock clock;
  private final Random random;
  private final RpgProgression progression;

  @org.springframework.beans.factory.annotation.Autowired
  public RpgService(JdbcTemplate db, Changes changes, ObjectMapper json,
      PlatformTransactionManager manager, Environment env,
      @Value("${RPG_SIMULATION_ENABLED:false}") boolean simulation) {
    this(db,changes,json,manager,env,simulation,Clock.systemUTC(),new java.security.SecureRandom());
  }
  RpgService(JdbcTemplate db,Changes changes,ObjectMapper json,PlatformTransactionManager manager,
      Environment env,boolean simulation,Clock clock,Random random) {
    this.db=db;this.changes=changes;this.json=json;tx=new TransactionTemplate(manager);
    this.clock=clock;this.random=random;
    this.progression=new RpgProgression(db,clock);
    practice=simulation && Arrays.stream(env.getActiveProfiles()).anyMatch(p->p.equals("dev")||p.equals("test"));
  }
  public record Start(@NotBlank @Size(max=80) String destinationId,
      @NotBlank @Size(max=36) String monsterId,boolean safeConfirmed,@Valid RpgRules.Location location,
      @Pattern(regexp="wild|boss") String kind) {
    public Start(String destinationId,String monsterId,boolean safeConfirmed,RpgRules.Location location){this(destinationId,monsterId,safeConfirmed,location,"wild");}
  }
  public record Move(@Min(0) int revision,
      @NotNull @Pattern(regexp="strike|magic|burst|guard|heal|capture|retreat|switch") String move,@Size(max=36) String monsterId) {
    public Move(int revision,String move){this(revision,move,null);}
  }
  public record Party(@NotNull @Size(min=1,max=3) List<@NotBlank @Size(max=36) String> monsterIds) {}
  public record Evolution(@Min(0) @Max(1) int stage) {}
  public record Purchase(@NotNull @Pattern(regexp="potion|crystal") String item,@Min(1) @Max(10) int quantity) {}
  public record Title(@NotBlank @Size(max=40) String id) {}
  private String scope(String actor,String realm) {
    if(!List.of("practice","field").contains(realm)) throw new IllegalArgumentException();
    if(realm.equals("practice")&&!practice) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Server practice mode is disabled");
    if(actor.length()>100) throw new IllegalArgumentException();
    return actor+":"+realm;
  }
  public Object capabilities() { return Map.of("practiceEnabled",practice,"fieldRequiresReviewedDestination",true,"redemptionEnabled",false,"partySize",3); }
  public List<Map<String,Object>> world(String actor,String realm) {
    scope(actor,realm);
    var world=db.queryForList("SELECT * FROM rpg_destinations ORDER BY name");
    for(var d:world)d.put("spawnRules",db.queryForList("SELECT species_id,weight FROM rpg_spawn_rules WHERE destination_id=? ORDER BY species_id",d.get("ID")));
    return world;
  }
  private void ensure(String actor,String realm,String scope) {
    int created=db.update("INSERT INTO rpg_players(scope_id,actor,realm) SELECT ?,?,? FROM dual WHERE NOT EXISTS (SELECT 1 FROM rpg_players WHERE scope_id=?)",scope,actor,realm,scope);
    if(created==1) {
      String starter=UUID.randomUUID().toString();
      db.update("INSERT INTO rpg_monsters(id,scope_id,species_id,variation) VALUES(?,?,?,?)",starter,scope,"mossling",2);
      progression.seed(scope,starter);
    }
  }
  private Map<String,Object> lock(String actor,String realm,String scope) {
    ensure(actor,realm,scope);
    return db.queryForMap("SELECT * FROM rpg_players WHERE scope_id=? FOR UPDATE",scope);
  }
  private int number(Map<String,Object> row,String key){return ((Number)row.get(key)).intValue();}
  private <T> T parse(String value,Class<T> type) {
    try{return json.readValue(value,type);}catch(Exception e){throw new IllegalStateException("Invalid stored RPG state",e);}
  }
  private Object prior(String scope,String key,String operation,Object body) {
    return changes.prior(scope,key,operation,body).map(s->parse(s,Object.class)).orElse(null);
  }
  private Object mutate(String actor,String realm,String key,String op,Object body,Supplier<Object> fn) {
    String scope=scope(actor,realm);
    return tx.execute(status->{
      lock(actor,realm,scope);
      Object prior=prior(scope,key,op,body); if(prior!=null)return prior;
      Object result=fn.get(); changes.remember(scope,key,op,body,result);
      changes.record(actor,"rpg."+op,scope,Map.of("realm",realm));
      return result;
    });
  }
  public Object profile(String actor,String realm) {
    String scope=scope(actor,realm);
    return tx.execute(status->{lock(actor,realm,scope); expire(scope);return snapshot(scope,realm);});
  }
  private void expire(String scope) {
    db.update("UPDATE rpg_sessions SET status='expired' WHERE scope_id=? AND status='active' AND expires_at<?",scope,Timestamp.from(clock.instant()));
  }
  private Map<String,Object> snapshot(String scope,String realm) {
    var p=db.queryForMap("SELECT xp,gold,wins,captures,next_encounter,daily_count,equipped_title FROM rpg_players WHERE scope_id=?",scope);
    var monsters=db.queryForList("SELECT id,species_id,xp,variation,evolution,destination_id FROM rpg_monsters WHERE scope_id=? ORDER BY created_at,id",scope);
    for(var m:monsters) {
      int level=RpgRules.level(number(m,"XP")),stage=number(m,"EVOLUTION"),variation=number(m,"VARIATION");
      var species=RpgRules.species(m.get("SPECIES_ID").toString());
      m.put("stats",Map.of("level",level,"hp",RpgRules.fighter(species.id(),level,variation,stage).maxHp(),"attack",species.attack()+level*2+variation+stage*4,"defense",species.defense()+level+stage*2,"speed",species.speed()+level));
      m.put("abilities",level>=3?List.of("strike","magic","burst","guard","heal"):List.of("strike","magic","guard","heal"));
      m.put("passive",stage>0?"Awakened guard: +"+(stage*2)+" shield":"None");
    }
    var ledger=db.queryForList("SELECT id,source_id,xp,gold,kind,created_at FROM rpg_ledger WHERE scope_id=? ORDER BY created_at DESC FETCH FIRST 50 ROWS ONLY",scope);
    var active=db.queryForList("SELECT id FROM rpg_sessions WHERE scope_id=? AND status='active' ORDER BY created_at DESC FETCH FIRST 1 ROWS ONLY",scope);
    var quests=progression.quests(scope).stream().map(RpgProgression.Quest::view).toList();
    var out=new LinkedHashMap<String,Object>();
    out.put("realm",realm);out.put("profile",p);out.put("monsters",monsters);out.put("ledger",ledger);
    out.put("quests",quests);out.put("species",RpgRules.SPECIES);out.put("travelPoints",0);
    out.put("inventory",db.queryForList("SELECT item,quantity FROM rpg_inventory WHERE scope_id=? ORDER BY item",scope));
    out.put("party",progression.party(scope));out.put("exploration",progression.exploration(scope));
    out.put("achievements",progression.achievements(scope));
    out.put("transactions",db.queryForList("SELECT asset,delta,source_id,created_at FROM rpg_transactions WHERE scope_id=? ORDER BY created_at DESC FETCH FIRST 50 ROWS ONLY",scope));
    out.put("history",db.queryForList("SELECT id,destination_id,kind,status,completed_at FROM rpg_sessions WHERE scope_id=? AND status<>'active' ORDER BY created_at DESC FETCH FIRST 20 ROWS ONLY",scope));
    out.put("activeSession",active.isEmpty()?null:session(scope,active.getFirst().get("ID").toString()));
    return out;
  }
  private Map<String,Object> session(String scope,String id) {
    var row=db.queryForMap("SELECT revision,status,expires_at,monster_id,kind FROM rpg_sessions WHERE id=? AND scope_id=?",id,scope);
    // Oracle CLOB must be read through JDBC's String conversion, not toString().
    String state=db.queryForObject("SELECT state FROM rpg_sessions WHERE id=? AND scope_id=?",String.class,id,scope);
    var party=db.query("SELECT monster_id,state FROM rpg_combatants WHERE session_id=? ORDER BY monster_id",(rs,n)->Map.of("id",rs.getString(1),"fighter",parse(rs.getString(2),RpgRules.Fighter.class)),id);
    return Map.of("id",id,"battle",parse(state,RpgRules.Battle.class),"revision",row.get("REVISION"),"status",row.get("STATUS"),"expiresAt",row.get("EXPIRES_AT"),"activeMonsterId",row.get("MONSTER_ID"),"party",party,"kind",row.get("KIND"));
  }
  public Object start(String actor,String realm,String key,Start body) {
    return mutate(actor,realm,key,"encounter",body,()->{
      String scope=scope(actor,realm);expire(scope);
      var p=db.queryForMap("SELECT * FROM rpg_players WHERE scope_id=?",scope);
      var d=db.queryForMap("SELECT * FROM rpg_destinations WHERE id=?",body.destinationId);
      if(!body.safeConfirmed) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Confirm you are stationary in a safe permitted area");
      if(realm.equals("field")) {
        if(number(d,"APPROVED")!=1||number(d,"ACCESSIBLE")!=1) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Destination has not been reviewed for gameplay");
        if(!RpgRules.eligible(body.location,clock.instant(),((Number)d.get("LATITUDE")).doubleValue(),((Number)d.get("LONGITUDE")).doubleValue(),number(d,"RADIUS_M")))
          throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Fresh accurate location inside the permitted boundary is required");
      }
      if(RpgRules.level(number(p,"XP"))<number(d,"MIN_LEVEL")) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Player level too low");
      if(db.queryForObject("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=? AND status='active'",Integer.class,scope)>0) throw new ResponseStatusException(HttpStatus.CONFLICT,"Resume your active encounter first");
      if(db.queryForObject("SELECT COUNT(*) FROM rpg_monsters WHERE scope_id=?",Integer.class,scope)>=100) throw new ResponseStatusException(HttpStatus.CONFLICT,"MVP collection limit reached");
      Instant now=clock.instant(); Instant next=((Timestamp)p.get("NEXT_ENCOUNTER")).toInstant();
      String day=LocalDate.now(clock).toString();int count=day.equals(p.get("DAILY_DATE"))?number(p,"DAILY_COUNT"):0;
      if(next.isAfter(now)) throw retry("Encounter cooldown",Duration.between(now,next).toSeconds()+1);
      if(count>=number(d,"DAILY_LIMIT")) throw retry("Daily encounter limit reached",Duration.between(now,LocalDate.now(clock).plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)).toSeconds());
      var owned=db.queryForMap("SELECT species_id,xp,variation,evolution FROM rpg_monsters WHERE id=? AND scope_id=?",body.monsterId,scope);
      var party=progression.party(scope);
      if(party.stream().noneMatch(m->m.get("MONSTER_ID").equals(body.monsterId)))throw new ResponseStatusException(HttpStatus.CONFLICT,"Select a companion in your saved party");
      boolean boss="boss".equals(body.kind);
      if(boss&&progression.count("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=? AND destination_id=? AND status IN ('won','captured')",scope,body.destinationId)<number(d,"BOSS_UNLOCK_WINS"))throw new ResponseStatusException(HttpStatus.CONFLICT,"Complete this destination's encounters to unlock its guardian");
      var weights=db.queryForList("SELECT species_id,weight FROM rpg_spawn_rules WHERE destination_id=? ORDER BY species_id",body.destinationId);
      if(weights.isEmpty())throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Destination spawn rules are not configured");
      int roll=random.nextInt(weights.stream().mapToInt(w->number(w,"WEIGHT")).sum());
      String enemyId=weights.getLast().get("SPECIES_ID").toString();
      for(var w:weights){roll-=number(w,"WEIGHT");if(roll<0){enemyId=w.get("SPECIES_ID").toString();break;}}
      var enemy=RpgRules.species(enemyId);
      int level=RpgRules.level(number(owned,"XP"));
      int enemyLevel=boss?number(d,"BOSS_LEVEL"):Math.clamp(level-1,number(d,"ENEMY_LEVEL_MIN"),number(d,"ENEMY_LEVEL_MAX"));
      var battle=new RpgRules.Battle(RpgRules.fighter(owned.get("SPECIES_ID").toString(),level,number(owned,"VARIATION"),number(owned,"EVOLUTION")),RpgRules.fighter(enemy.id(),enemyLevel,random.nextInt(6),boss?2:0),Math.min(3,progression.quantity(scope,"crystal")),Math.min(2,progression.quantity(scope,"potion")),0,"active",List.of(boss?"Guardian challenge started":"Encounter started"),boss);
      String id=UUID.randomUUID().toString();
      db.update("INSERT INTO rpg_sessions(id,scope_id,destination_id,monster_id,state,status,expires_at,kind) VALUES(?,?,?,?,?,'active',?,?)",id,scope,body.destinationId,body.monsterId,changes.json(battle),Timestamp.from(now.plusSeconds(900)),boss?"boss":"wild");
      for(var member:party) {
        var m=db.queryForMap("SELECT * FROM rpg_monsters WHERE id=? AND scope_id=?",member.get("MONSTER_ID"),scope);
        db.update("INSERT INTO rpg_combatants(session_id,monster_id,state) VALUES(?,?,?)",id,member.get("MONSTER_ID"),changes.json(RpgRules.fighter(m.get("SPECIES_ID").toString(),RpgRules.level(number(m,"XP")),number(m,"VARIATION"),number(m,"EVOLUTION"))));
      }
      db.update("UPDATE rpg_players SET next_encounter=?,daily_date=?,daily_count=? WHERE scope_id=?",Timestamp.from(now.plusSeconds(number(d,"COOLDOWN_SECONDS"))),day,count+1,scope);
      return session(scope,id);
    });
  }
  private ResponseStatusException retry(String message,long seconds) {
    return new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,message) {
      @Override public org.springframework.http.HttpHeaders getHeaders(){var h=new org.springframework.http.HttpHeaders();h.set("Retry-After",Long.toString(seconds));return h;}
    };
  }
  public Object move(String actor,String realm,String id,String key,Move body) {
    return mutate(actor,realm,key,"action:"+id,body,()->{
      String scope=scope(actor,realm);
      var row=db.queryForMap("SELECT revision,status,expires_at,monster_id,destination_id FROM rpg_sessions WHERE id=? AND scope_id=?",id,scope);
      if(!row.get("STATUS").equals("active")) throw new ResponseStatusException(HttpStatus.CONFLICT,"Battle is already finished");
      if(!((Timestamp)row.get("EXPIRES_AT")).toInstant().isAfter(clock.instant())) throw new ResponseStatusException(HttpStatus.GONE,"Encounter expired; refresh your adventure");
      if(number(row,"REVISION")!=body.revision) throw new ResponseStatusException(HttpStatus.CONFLICT,"Battle changed; refresh before acting");
      var old=parse(db.queryForObject("SELECT state FROM rpg_sessions WHERE id=? AND scope_id=?",String.class,id,scope),RpgRules.Battle.class);
      String active=row.get("MONSTER_ID").toString();
      if(body.move.equals("switch")) {
        if(body.monsterId==null||active.equals(body.monsterId))throw new IllegalArgumentException("Choose another party member");
        var next=parse(db.queryForObject("SELECT state FROM rpg_combatants WHERE session_id=? AND monster_id=?",String.class,id,body.monsterId),RpgRules.Fighter.class);
        if(next.hp()<=0)throw new ResponseStatusException(HttpStatus.CONFLICT,"Companion is defeated");
        active=body.monsterId;
        old=new RpgRules.Battle(next,old.enemy(),old.crystals(),old.potions(),old.turn(),"active",old.log(),old.boss());
      }
      var battle=RpgRules.action(old,body.move,random);
      progression.item(scope,"action:"+id+":"+body.revision,"potion",battle.potions()-old.potions());
      progression.item(scope,"action:"+id+":"+body.revision,"crystal",battle.crystals()-old.crystals());
      db.update("UPDATE rpg_combatants SET state=? WHERE session_id=? AND monster_id=?",changes.json(battle.ally()),id,active);
      if(battle.status().equals("lost")) {
        var reserve=db.query("SELECT state FROM rpg_combatants WHERE session_id=? AND monster_id<>?",(rs,n)->parse(rs.getString(1),RpgRules.Fighter.class),id,active);
        if(reserve.stream().anyMatch(f->f.hp()>0))battle=new RpgRules.Battle(battle.ally(),battle.enemy(),battle.crystals(),battle.potions(),battle.turn(),"active",battle.log(),battle.boss());
      }
      db.update("UPDATE rpg_sessions SET state=?,revision=revision+1,status=?,monster_id=?,completed_at=? WHERE id=? AND scope_id=?",changes.json(battle),battle.status(),active,battle.status().equals("active")?null:Timestamp.from(clock.instant()),id,scope);
      if(battle.status().equals("won")||battle.status().equals("captured")) {
        int xp=(30+battle.enemy().level()*10)*(battle.boss()?3:1);int gold=(10+battle.enemy().level()*5)*(battle.boss()?3:1);
        award(scope,"battle:"+id,xp,gold,battle.status());
        db.update("UPDATE rpg_monsters SET xp=xp+? WHERE id=? AND scope_id=?",xp,active,scope);
        String drop=battle.status().equals("won")?"potion":"crystal";
        if(progression.quantity(scope,drop)<9999)progression.item(scope,"drop:"+id,drop,1);
        db.update("UPDATE rpg_players SET wins=wins+?,captures=captures+? WHERE scope_id=?",battle.status().equals("won")?1:0,battle.status().equals("captured")?1:0,scope);
        if(battle.status().equals("captured")) db.update("INSERT INTO rpg_monsters(id,scope_id,species_id,variation,destination_id) VALUES(?,?,?,?,?)",UUID.randomUUID().toString(),scope,battle.enemy().speciesId(),battle.enemy().variation(),row.get("DESTINATION_ID"));
      }
      return session(scope,id);
    });
  }
  private void award(String scope,String source,int xp,int gold,String kind) {
    db.update("INSERT INTO rpg_ledger(id,scope_id,source_id,xp,gold,kind) VALUES(?,?,?,?,?,?)",UUID.randomUUID().toString(),scope,source,xp,gold,kind);
    db.update("UPDATE rpg_players SET xp=xp+?,gold=gold+? WHERE scope_id=?",xp,gold,scope);
  }
  public Object claim(String actor,String realm,String id,String key) {
    if(id.length()>60)throw Api.missing();
    return mutate(actor,realm,key,"quest:"+id,Map.of("id",id),()->{
      String scope=scope(actor,realm);
      var quest=progression.quests(scope).stream().filter(q->q.id().equals(id)).findFirst().orElseThrow(Api::missing);
      if(!quest.completed())throw new ResponseStatusException(HttpStatus.CONFLICT,"Quest is not complete");
      if(!quest.claimed())award(scope,quest.source(),quest.xp(),quest.gold(),"quest");
      return snapshot(scope,realm);
    });
  }
  public Object party(String actor,String realm,String key,Party body) {
    return mutate(actor,realm,key,"party",body,()->{String s=scope(actor,realm);expire(s);progression.party(s,body.monsterIds);return snapshot(s,realm);});
  }
  public Object evolve(String actor,String realm,String id,String key,Evolution body) {
    return mutate(actor,realm,key,"evolve:"+id,body,()->{String s=scope(actor,realm);expire(s);progression.evolve(s,id,body.stage,key);return snapshot(s,realm);});
  }
  public Object purchase(String actor,String realm,String key,Purchase body) {
    return mutate(actor,realm,key,"purchase",body,()->{String s=scope(actor,realm);expire(s);progression.idle(s);if(!List.of("potion","crystal").contains(body.item)||body.quantity<1||body.quantity>10)throw new IllegalArgumentException();progression.spend(s,"buy:"+key,body.quantity*(body.item.equals("potion")?10:15));progression.item(s,"buy:"+key,body.item,body.quantity);return snapshot(s,realm);});
  }
  public Object title(String actor,String realm,String key,Title body) {
    return mutate(actor,realm,key,"title",body,()->{String s=scope(actor,realm);progression.title(s,body.id);return snapshot(s,realm);});
  }
}
