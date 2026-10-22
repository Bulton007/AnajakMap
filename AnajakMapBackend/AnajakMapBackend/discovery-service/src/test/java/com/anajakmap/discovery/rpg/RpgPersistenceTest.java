package com.anajakmap.discovery.rpg;

import static org.junit.jupiter.api.Assertions.*;
import com.anajakmap.platform.Changes;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.*;
import java.util.concurrent.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.condition.EnabledIf;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.*;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.web.server.ResponseStatusException;

@EnabledIf("databaseConfigured")
class RpgPersistenceTest {
  static boolean databaseConfigured() {
    return "true".equals(System.getenv("RPG_ORACLE_TEST")) || "true".equals(System.getenv("RPG_POSTGRES_TEST"));
  }
  JdbcTemplate db; RpgService service; ObjectMapper mapper; Changes changes;
  DriverManagerDataSource source;
  final String actor="rpg-test-"+UUID.randomUUID();
  final String destination="4b9f991fa8c7bb8f";
  String key(){return UUID.randomUUID().toString();}
  Map<?,?> map(Object value){return (Map<?,?>)value;}
  @BeforeEach void setup() {
    boolean postgres="true".equals(System.getenv("RPG_POSTGRES_TEST"));
    if(postgres) {
      String schema="verify_rpg_"+UUID.randomUUID().toString().substring(0,8);
      String url=System.getenv("POSTGRES_TEST_URL");
      source=new DriverManagerDataSource(url+(url.contains("?")?"&":"?")+"currentSchema="+schema,
          System.getenv().getOrDefault("POSTGRES_TEST_USER","postgres"),System.getenv().getOrDefault("POSTGRES_TEST_PASSWORD",""));
      Flyway.configure().dataSource(source).defaultSchema(schema).locations("classpath:db/postgresql").load().migrate();
      db=new com.anajakmap.platform.PostgresJdbcConfiguration().jdbcTemplate(source);
    } else {
      source=new DriverManagerDataSource(System.getenv("ORACLE_TEST_URL"),System.getenv("ORACLE_TEST_USER"),System.getenv("ORACLE_TEST_PASSWORD"));
      Flyway.configure().dataSource(source).locations("classpath:db/migration").load().migrate();
      db=new JdbcTemplate(source);
    }
    mapper=new ObjectMapper().findAndRegisterModules();changes=new Changes(db,mapper);
    service=create();
  }
  RpgService create(){return new RpgService(db,changes,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","test"),true);}
  String starter() {
    var profile=map(service.profile(actor,"practice"));
    return map(((List<?>)profile.get("monsters")).getFirst()).get("ID").toString();
  }
  @Test void persistenceOwnershipReplayAndRewardAtomicity() throws Exception {
    String owned=starter(), startKey=key();
    var body=new RpgService.Start(destination,owned,true,null);
    var first=map(service.start(actor,"practice",startKey,body));String id=first.get("id").toString();
    assertEquals(id,map(service.start(actor,"practice",startKey,body)).get("id"));
    assertThrows(ResponseStatusException.class,()->service.start(actor,"practice",startKey,new RpgService.Start(destination,owned,false,null)));
    assertThrows(org.springframework.dao.EmptyResultDataAccessException.class,()->service.move("other-user","practice",id,key(),new RpgService.Move(0,"capture")));
    assertEquals(id,map(map(create().profile(actor,"practice")).get("activeSession")).get("id"));
    assertThrows(ResponseStatusException.class,()->service.move(actor,"practice",id,key(),new RpgService.Move(99,"strike")));
    // Controlled persisted fixture guarantees a victory, independent of random crits.
    var battle=RpgRules.start(RpgRules.fighter("moonwarden",50,5),RpgRules.fighter("mossling",1,0));
    db.update("UPDATE rpg_sessions SET state=? WHERE id=?",changes.json(battle),id);
    String moveKey=key();var move=new RpgService.Move(0,"strike");
    assertEquals("won",map(service.move(actor,"practice",id,moveKey,move)).get("status"));
    service.move(actor,"practice",id,moveKey,move);
    assertThrows(ResponseStatusException.class,()->service.move(actor,"practice",id,key(),move));
    assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM rpg_ledger WHERE scope_id=?",Integer.class,actor+":practice"));
    try(var pool=Executors.newFixedThreadPool(4)) {
      var tasks=new ArrayList<Callable<Object>>();
      for(int i=0;i<4;i++)tasks.add(()->service.claim(actor,"practice","first-win",key()));
      for(var result:pool.invokeAll(tasks))result.get(20,TimeUnit.SECONDS);
    }
    assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM rpg_ledger WHERE scope_id=?",Integer.class,actor+":practice"));
    assertEquals(90,db.queryForObject("SELECT xp FROM rpg_players WHERE scope_id=?",Integer.class,actor+":practice"));
    assertThrows(org.springframework.dao.DataAccessException.class,()->db.update("DELETE FROM rpg_ledger WHERE scope_id=?",actor+":practice"));
    assertEquals(0,((Number)map(map(service.profile(actor,"field")).get("profile")).get("XP")).intValue());
    var fieldStarter=map(((List<?>)map(service.profile(actor,"field")).get("monsters")).getFirst()).get("ID").toString();
    assertEquals(403,assertThrows(ResponseStatusException.class,()->service.start(actor,"field",key(),new RpgService.Start(destination,fieldStarter,true,null))).getStatusCode().value());
    var cooldown=assertThrows(ResponseStatusException.class,()->service.start(actor,"practice",key(),body));
    assertEquals(429,cooldown.getStatusCode().value());assertNotNull(cooldown.getHeaders().getFirst("Retry-After"));
  }
  @Test void failedAuditRollsBackSessionAndCounters() {
    String owned=starter();
    var broken=new Changes(db,mapper){@Override public void record(String actor,String action,String id,Map<String,?> fields){throw new IllegalStateException("test rollback");}};
    var failing=new RpgService(db,broken,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","test"),true);
    assertThrows(IllegalStateException.class,()->failing.start(actor,"practice",key(),new RpgService.Start(destination,owned,true,null)));
    assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM rpg_sessions WHERE scope_id=?",Integer.class,actor+":practice"));
    assertEquals(0,db.queryForObject("SELECT daily_count FROM rpg_players WHERE scope_id=?",Integer.class,actor+":practice"));
  }
  @Test void captureRetriesCreateExactlyOneOwnedInstance() {
    String owned=starter();
    var deterministic=new RpgService(db,changes,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","test"),true,java.time.Clock.systemUTC(),new Random(){@Override public double nextDouble(){return 0;}});
    String id=map(deterministic.start(actor,"practice",key(),new RpgService.Start(destination,owned,true,null))).get("id").toString();
    String actionKey=key();var move=new RpgService.Move(0,"capture");
    assertEquals("captured",map(deterministic.move(actor,"practice",id,actionKey,move)).get("status"));
    deterministic.move(actor,"practice",id,actionKey,move);
    assertEquals(2,db.queryForObject("SELECT COUNT(*) FROM rpg_monsters WHERE scope_id=?",Integer.class,actor+":practice"));
    assertEquals(1,db.queryForObject("SELECT captures FROM rpg_players WHERE scope_id=?",Integer.class,actor+":practice"));
    assertEquals(destination,db.queryForObject("SELECT destination_id FROM rpg_monsters WHERE scope_id=? AND id<>?",String.class,actor+":practice",owned));
  }
  @Test void simulationCannotBeEnabledInProductionAndExpiredBattlesResumeAsExpired() {
    var production=new RpgService(db,changes,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","prod"),true);
    assertEquals(503,assertThrows(ResponseStatusException.class,()->production.profile(actor,"practice")).getStatusCode().value());
    var start=map(service.start(actor,"practice",key(),new RpgService.Start(destination,starter(),true,null)));
    db.update("UPDATE rpg_sessions SET expires_at=TIMESTAMP '2000-01-01 00:00:00' WHERE id=?",start.get("id"));
    assertNull(map(service.profile(actor,"practice")).get("activeSession"));
    assertEquals("expired",db.queryForObject("SELECT status FROM rpg_sessions WHERE id=?",String.class,start.get("id")));
  }
  @Test void inventoryEvolutionAndPartyAreOwnedTransactionalAndReplaySafe() {
    String first=starter(),scope=actor+":practice";
    db.update("UPDATE rpg_players SET gold=500 WHERE scope_id=?",scope);
    db.update("UPDATE rpg_monsters SET xp=800 WHERE id=?",first);
    String purchaseKey=key();var purchase=new RpgService.Purchase("potion",2);
    service.purchase(actor,"practice",purchaseKey,purchase);service.purchase(actor,"practice",purchaseKey,purchase);
    assertEquals(7,db.queryForObject("SELECT quantity FROM rpg_inventory WHERE scope_id=? AND item='potion'",Integer.class,scope));
    assertEquals(480,db.queryForObject("SELECT gold FROM rpg_players WHERE scope_id=?",Integer.class,scope));
    String evolutionKey=key();service.evolve(actor,"practice",first,evolutionKey,new RpgService.Evolution(0));
    service.evolve(actor,"practice",first,evolutionKey,new RpgService.Evolution(0));
    assertEquals(1,db.queryForObject("SELECT evolution FROM rpg_monsters WHERE id=?",Integer.class,first));
    assertEquals(405,db.queryForObject("SELECT gold FROM rpg_players WHERE scope_id=?",Integer.class,scope));
    assertThrows(ResponseStatusException.class,()->service.evolve(actor,"practice",first,key(),new RpgService.Evolution(0)));
    assertThrows(org.springframework.dao.EmptyResultDataAccessException.class,()->service.evolve("intruder","practice",first,key(),new RpgService.Evolution(1)));
    String second=UUID.randomUUID().toString();
    db.update("INSERT INTO rpg_monsters(id,scope_id,species_id,variation) VALUES(?,?,'bubblefin',3)",second,scope);
    service.party(actor,"practice",key(),new RpgService.Party(List.of(first,second)));
    assertThrows(IllegalArgumentException.class,()->service.party(actor,"practice",key(),new RpgService.Party(List.of(first,first))));
    assertThrows(ResponseStatusException.class,()->service.party("intruder","practice",key(),new RpgService.Party(List.of(first))));
    String battle=map(service.start(actor,"practice",key(),new RpgService.Start(destination,first,true,null))).get("id").toString();
    String switchKey=key();var move=new RpgService.Move(0,"switch",second);
    var switched=map(service.move(actor,"practice",battle,switchKey,move));
    assertEquals(second,switched.get("activeMonsterId"));
    assertEquals(1,((Number)map(service.move(actor,"practice",battle,switchKey,move)).get("revision")).intValue());
    assertThrows(ResponseStatusException.class,()->service.purchase(actor,"practice",key(),purchase));
    service.move(actor,"practice",battle,key(),new RpgService.Move(1,"retreat"));
    db.update("UPDATE rpg_players SET gold=0 WHERE scope_id=?",scope);
    assertThrows(ResponseStatusException.class,()->service.purchase(actor,"practice",key(),purchase));
    assertEquals(7,db.queryForObject("SELECT quantity FROM rpg_inventory WHERE scope_id=? AND item='potion'",Integer.class,scope));
  }
  @Test void recurringQuestPeriodAndGuardianUnlockComeFromPersistedOutcomes() {
    String first=starter(),scope=actor+":practice";
    assertThrows(ResponseStatusException.class,()->service.start(actor,"practice",key(),new RpgService.Start(destination,first,true,null,"boss")));
    var now=java.time.Instant.parse("2026-10-16T12:00:00Z");
    for(int i=0;i<3;i++) db.update("INSERT INTO rpg_sessions(id,scope_id,destination_id,monster_id,state,status,expires_at,completed_at) VALUES(?,?,?,?,?,'won',?,?)",key(),scope,destination,first,"{}",java.sql.Timestamp.from(now),java.sql.Timestamp.from(now));
    var today=new RpgService(db,changes,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","test"),true,java.time.Clock.fixed(now,java.time.ZoneOffset.UTC),new Random(2));
    today.claim(actor,"practice","daily-win",key());today.claim(actor,"practice","daily-win",key());
    assertEquals(1,db.queryForObject("SELECT COUNT(*) FROM rpg_ledger WHERE scope_id=? AND source_id='quest:daily-win:2026-10-16'",Integer.class,scope));
    var tomorrow=new RpgService(db,changes,mapper,new DataSourceTransactionManager(source),new MockEnvironment().withProperty("spring.profiles.active","test"),true,java.time.Clock.fixed(now.plusSeconds(86400),java.time.ZoneOffset.UTC),new Random(2));
    assertThrows(ResponseStatusException.class,()->tomorrow.claim(actor,"practice","daily-win",key()));
    var guardian=map(today.start(actor,"practice",key(),new RpgService.Start(destination,first,true,null,"boss")));
    assertEquals("boss",guardian.get("kind"));
    assertThrows(IllegalArgumentException.class,()->today.move(actor,"practice",guardian.get("id").toString(),key(),new RpgService.Move(0,"capture")));
  }
}
