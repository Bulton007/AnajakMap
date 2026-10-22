package com.anajakmap.discovery.rpg;

import com.anajakmap.platform.Changes;
import java.sql.Timestamp;
import java.time.*;
import java.time.temporal.TemporalAdjusters;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

/** Called inside RpgService's account-row lock and transaction, never directly by HTTP. */
final class RpgProgression {
  private final JdbcTemplate db;
  private final Clock clock;
  RpgProgression(JdbcTemplate db,Clock clock){this.db=db;this.clock=clock;}
  record Quest(String id,String title,int progress,int target,String source,int xp,int gold,boolean claimed) {
    public boolean completed(){return progress>=target;}
    Map<String,Object> view(){return Map.of("id",id,"title",title,"progress",progress,"target",target,"completed",completed(),"claimed",claimed,"xp",xp,"gold",gold);}
  }
  int count(String sql,Object... args){return db.queryForObject(sql,Integer.class,args);}
  void seed(String scope,String starter) {
    db.update("INSERT INTO rpg_inventory(scope_id,item,quantity) VALUES(?,'potion',5)",scope);
    db.update("INSERT INTO rpg_inventory(scope_id,item,quantity) VALUES(?,'crystal',8)",scope);
    db.update("INSERT INTO rpg_party(scope_id,slot,monster_id) VALUES(?,1,?)",scope,starter);
  }
  void idle(String scope) {
    if(count("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=? AND status='active'",scope)>0)
      throw new ResponseStatusException(HttpStatus.CONFLICT,"Finish or retreat from your encounter first");
  }
  int quantity(String scope,String item){return count("SELECT quantity FROM rpg_inventory WHERE scope_id=? AND item=?",scope,item);}
  void item(String scope,String source,String item,int delta) {
    if(delta==0)return;
    if(db.update("UPDATE rpg_inventory SET quantity=quantity+? WHERE scope_id=? AND item=? AND quantity+? BETWEEN 0 AND 9999",delta,scope,item,delta)!=1)
      throw new ResponseStatusException(HttpStatus.CONFLICT,"Insufficient items or inventory full");
    transaction(scope,source,item,delta);
  }
  void spend(String scope,String source,int gold) {
    if(db.update("UPDATE rpg_players SET gold=gold-? WHERE scope_id=? AND gold>=?",gold,scope,gold)!=1)
      throw new ResponseStatusException(HttpStatus.CONFLICT,"Not enough game gold");
    transaction(scope,source,"gold",-gold);
  }
  private void transaction(String scope,String source,String asset,int delta) {
    db.update("INSERT INTO rpg_transactions(id,scope_id,source_id,asset,delta) VALUES(?,?,?,?,?)",UUID.randomUUID().toString(),scope,source,asset,delta);
  }
  void party(String scope,List<String> ids) {
    idle(scope);
    if(ids.isEmpty()||ids.size()>3||new HashSet<>(ids).size()!=ids.size())throw new IllegalArgumentException("Choose one to three different companions");
    for(String id:ids)if(count("SELECT COUNT(*) FROM rpg_monsters WHERE id=? AND scope_id=?",id,scope)!=1)
      throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Companion not found");
    db.update("DELETE FROM rpg_party WHERE scope_id=?",scope);
    for(int i=0;i<ids.size();i++)db.update("INSERT INTO rpg_party(scope_id,slot,monster_id) VALUES(?,?,?)",scope,i+1,ids.get(i));
  }
  void evolve(String scope,String id,int expectedStage,String key) {
    idle(scope);
    var monster=db.queryForMap("SELECT xp,evolution FROM rpg_monsters WHERE scope_id=? AND id=?",scope,id);
    int stage=((Number)monster.get("EVOLUTION")).intValue();
    int level=RpgRules.level(((Number)monster.get("XP")).intValue());
    if(stage!=expectedStage||stage>=2||level<(stage==0?4:8))
      throw new ResponseStatusException(HttpStatus.CONFLICT,"Evolution requires stage 0 at level 4, or stage 1 at level 8");
    spend(scope,"evolve:"+key,75*(stage+1));
    db.update("UPDATE rpg_monsters SET evolution=evolution+1 WHERE scope_id=? AND id=?",scope,id);
  }
  List<Map<String,Object>> party(String scope){return db.queryForList("SELECT slot,monster_id FROM rpg_party WHERE scope_id=? ORDER BY slot",scope);}
  List<Map<String,Object>> exploration(String scope) {
    return db.queryForList("SELECT d.id,d.name,d.boss_unlock_wins,(SELECT COUNT(*) FROM rpg_sessions s WHERE s.scope_id=? AND s.destination_id=d.id AND s.status IN ('won','captured')) AS successes,(SELECT COUNT(*) FROM rpg_sessions s WHERE s.scope_id=? AND s.destination_id=d.id AND s.status='won' AND s.kind='boss') AS bosses FROM rpg_destinations d ORDER BY d.name",scope,scope);
  }
  List<Quest> quests(String scope) {
    var today=LocalDate.now(clock);var week=today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    var quests=new ArrayList<Quest>();
    add(quests,scope,"first-win","Win your first battle",count("SELECT wins FROM rpg_players WHERE scope_id=?",scope),1,"",50,20);
    add(quests,scope,"first-capture","Capture your first companion",count("SELECT captures FROM rpg_players WHERE scope_id=?",scope),1,"",50,20);
    add(quests,scope,"daily-win","Daily: win two battles",completedSince(scope,today,"won"),2,today.toString(),40,25);
    add(quests,scope,"weekly-capture","Weekly: capture three companions",completedSince(scope,week,"captured"),3,week.toString(),100,60);
    add(quests,scope,"collector","Discover three species",count("SELECT COUNT(DISTINCT species_id) FROM rpg_monsters WHERE scope_id=?",scope),3,"",70,40);
    add(quests,scope,"evolution","Evolve a companion",count("SELECT COUNT(*) FROM rpg_monsters WHERE scope_id=? AND evolution>0",scope),1,"",80,30);
    add(quests,scope,"guardian","Defeat a destination guardian",count("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=? AND kind='boss' AND status='won'",scope),1,"",100,60);
    int level=RpgRules.level(count("SELECT xp FROM rpg_players WHERE scope_id=?",scope));
    for(int milestone:new int[]{2,3,5,10})add(quests,scope,"level-"+milestone,"Reach level "+milestone,level,milestone,"",0,20*milestone);
    for(var d:exploration(scope))add(quests,scope,"destination-"+d.get("ID"),"Explore "+d.get("NAME"),((Number)d.get("SUCCESSES")).intValue(),3,"",60,30);
    return quests;
  }
  private int completedSince(String scope,LocalDate day,String status) {
    return count("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=? AND status=? AND completed_at>=?",scope,status,Timestamp.from(day.atStartOfDay().toInstant(ZoneOffset.UTC)));
  }
  private void add(List<Quest> out,String scope,String id,String title,int progress,int target,String period,int xp,int gold) {
    String source="quest:"+id+(period.isEmpty()?"":":"+period);
    boolean claimed=count("SELECT COUNT(*) FROM rpg_ledger WHERE scope_id=? AND source_id=?",scope,source)>0;
    out.add(new Quest(id,title,progress,target,source,xp,gold,claimed));
  }
  List<Map<String,Object>> achievements(String scope) {
    var quests=quests(scope);var out=new ArrayList<Map<String,Object>>();
    out.add(Map.of("id","traveler","title","Traveler","unlocked",true));
    for(String id:List.of("first-win","collector","evolution","guardian")) {
      var q=quests.stream().filter(v->v.id.equals(id)).findFirst().orElseThrow();
      out.add(Map.of("id",id,"title",switch(id){case "first-win"->"Trailblazer";case "collector"->"Creature Keeper";case "evolution"->"Awakened";default->"Guardian Challenger";},"unlocked",q.completed()));
    }
    return out;
  }
  void title(String scope,String id) {
    if(achievements(scope).stream().noneMatch(a->a.get("id").equals(id)&&a.get("unlocked").equals(true)))
      throw new ResponseStatusException(HttpStatus.CONFLICT,"Title is not unlocked");
    db.update("UPDATE rpg_players SET equipped_title=? WHERE scope_id=?",id,scope);
  }
}
