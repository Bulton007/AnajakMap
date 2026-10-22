package com.anajakmap.discovery.rpg;

import static org.junit.jupiter.api.Assertions.*;
import java.time.Instant;
import java.util.Random;
import java.util.List;
import org.junit.jupiter.api.Test;

class RpgRulesTest {
  @Test void evolutionBurstAndBossPhaseHaveRealCombatEffects() {
    var base=RpgRules.fighter("mossling",4,2);var evolved=RpgRules.fighter("mossling",4,2,1);
    var enemy=RpgRules.fighter("amberhorn",5,2,2);
    assertEquals(base.maxHp()+12,evolved.maxHp());
    assertTrue(RpgRules.damage(evolved,enemy,false,false)>RpgRules.damage(base,enemy,false,false));
    var burst=RpgRules.action(RpgRules.start(evolved,enemy),"burst",new Random(4));
    assertEquals(1,burst.ally().energy());
    assertThrows(IllegalArgumentException.class,()->RpgRules.action(RpgRules.start(RpgRules.fighter("mossling",1,0),enemy),"burst",new Random()));
    var boss=new RpgRules.Battle(evolved,enemy.change(10,3,0,0),3,2,0,"active",List.of(),true);
    assertThrows(IllegalArgumentException.class,()->RpgRules.action(boss,"capture",new Random()));
    assertTrue(RpgRules.action(boss,"guard",new Random(3)).log().stream().anyMatch(v->v.contains("phase 2")));
  }
  @Test void proximityRequiresFreshAccurateUnmockedLocation() {
    var now=Instant.parse("2026-10-16T00:00:00Z");
    assertTrue(RpgRules.eligible(new RpgRules.Location(11,104,10,now,false),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(11,104,10,now,true),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(11,104,51,now,false),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(11,104,10,now.minusSeconds(61),false),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(11,104,10,now.plusSeconds(6),false),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(11.001,104,10,now,false),now,11,104,100));
    assertFalse(RpgRules.eligible(new RpgRules.Location(Double.NaN,104,10,now,false),now,11,104,100));
    assertFalse(RpgRules.eligible(null,now,11,104,100));
  }
  @Test void seededSelectionStaysWithinHabitatAndIncludesAllMvpRarities() {
    var a=new Random(55);var b=new Random(55);var seen=new java.util.HashSet<String>();
    for(int i=0;i<1000;i++) {var s=RpgRules.select("beach",a);assertEquals(s,RpgRules.select("beach",b));assertEquals("beach",s.habitat());seen.add(s.rarity());}
    assertEquals(java.util.Set.of("Common","Rare","Epic"),seen);
  }
  @Test void levelCapsAndElementalCriticalDamage() {
    assertEquals(1,RpgRules.level(0));assertEquals(2,RpgRules.level(100));assertEquals(50,RpgRules.level(100000));
    var a=RpgRules.fighter("bubblefin",5,2);var d=RpgRules.fighter("amberhorn",5,2);
    assertEquals(1.5,RpgRules.affinity("water","fire"));assertEquals(.75,RpgRules.affinity("fire","water"));
    assertTrue(RpgRules.damage(a,d,true,true)>RpgRules.damage(a,d,true,false));
  }
  @Test void speedDeathPoisonResourcesAndTerminalState() {
    var fast=RpgRules.fighter("moonwarden",50,5);var weak=RpgRules.fighter("mossling",1,0);
    var result=RpgRules.action(RpgRules.start(fast,weak),"strike",new Random(8));
    assertEquals("won",result.status());assertEquals(fast.hp(),result.ally().hp());
    assertThrows(IllegalArgumentException.class,()->RpgRules.action(result,"strike",new Random()));
    var poisoned=new RpgRules.Fighter("mossling",1,0,4,0,1,0);
    var battle=RpgRules.start(poisoned,weak);
    assertThrows(IllegalArgumentException.class,()->RpgRules.action(battle,"magic",new Random()));
    assertEquals("lost",RpgRules.action(battle,"strike",new Random()).status());
  }
  @Test void captureGetsEasierWithDamageAndRetreatNeverWins() {
    var a=RpgRules.fighter("mossling",1,2);var e=RpgRules.fighter("moonwarden",1,2);
    var healthy=RpgRules.start(a,e);var weak=RpgRules.start(a,e.change(1,3,0,0));
    assertTrue(RpgRules.captureChance(weak)>RpgRules.captureChance(healthy));
    assertEquals("escaped",RpgRules.action(healthy,"retreat",new Random()).status());
    var captured=RpgRules.action(weak,"capture",new Random(){@Override public double nextDouble(){return 0;}});
    assertEquals("captured",captured.status());assertEquals(2,captured.crystals());
  }
}
