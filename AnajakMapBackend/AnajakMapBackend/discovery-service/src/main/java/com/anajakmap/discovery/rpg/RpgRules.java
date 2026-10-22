package com.anajakmap.discovery.rpg;

import java.time.*;
import java.util.*;

/** Pure Stage B rules. All mutable combat values originate on the server. */
public final class RpgRules {
  private RpgRules() {}
  public record Species(String id, String name, String habitat, String element,
                        String rarity, int weight, int hp, int attack, int defense, int speed) {}
  public static final List<Species> SPECIES = List.of(
      new Species("mossling","Mossling","temple","earth","Common",60,60,16,10,12),
      new Species("amberhorn","Amberhorn","temple","fire","Rare",30,70,19,12,10),
      new Species("moonwarden","Moonwarden","temple","water","Epic",10,80,21,14,15),
      new Species("bubblefin","Bubblefin","beach","water","Common",60,60,16,10,12),
      new Species("coralclaw","Coralclaw","beach","fire","Rare",30,70,19,12,10),
      new Species("tidewing","Tidewing","beach","earth","Epic",10,80,21,14,15));
  public static Species species(String id) {
    return SPECIES.stream().filter(s -> s.id.equals(id)).findFirst().orElseThrow(IllegalArgumentException::new);
  }
  public static Species select(String habitat, Random random) {
    var pool=SPECIES.stream().filter(s -> s.habitat.equals(habitat)).toList();
    int roll=random.nextInt(pool.stream().mapToInt(Species::weight).sum());
    for(var s:pool) { roll-=s.weight; if(roll<0) return s; }
    throw new IllegalArgumentException();
  }
  public static int level(int xp) { return Math.min(50, 1+xp/100); }
  public record Location(double latitude,double longitude,double accuracy,Instant measuredAt,boolean mocked) {}
  public static double distance(double a,double b,double c,double d) {
    double p=Math.toRadians(c-a), q=Math.toRadians(d-b);
    double x=Math.pow(Math.sin(p/2),2)+Math.cos(Math.toRadians(a))*Math.cos(Math.toRadians(c))*Math.pow(Math.sin(q/2),2);
    return 6371000*2*Math.asin(Math.sqrt(Math.min(1,x)));
  }
  public static boolean eligible(Location l, Instant now,double lat,double lon,int radius) {
    return l!=null && l.measuredAt!=null && !l.mocked && Double.isFinite(l.latitude)
      && Double.isFinite(l.longitude) && Math.abs(l.latitude)<=90 && Math.abs(l.longitude)<=180
      && Double.isFinite(l.accuracy) && l.accuracy>0 && l.accuracy<=50
      && !l.measuredAt.isBefore(now.minusSeconds(60)) && !l.measuredAt.isAfter(now.plusSeconds(5))
      && distance(lat,lon,l.latitude,l.longitude)+l.accuracy<=radius;
  }
  public record Fighter(String speciesId,int level,int variation,int hp,int energy,int poison,int shield,int evolution) {
    public Fighter(String speciesId,int level,int variation,int hp,int energy,int poison,int shield){this(speciesId,level,variation,hp,energy,poison,shield,0);}
    public int maxHp(){return species(speciesId).hp+level*4+variation+evolution*12;}
    Fighter change(int hp,int energy,int poison,int shield){
      return new Fighter(speciesId,level,variation,Math.max(0,Math.min(maxHp(),hp)),energy,poison,shield,evolution);
    }
  }
  public record Battle(Fighter ally,Fighter enemy,int crystals,int potions,int turn,String status,List<String> log,boolean boss) {
    public Battle(Fighter ally,Fighter enemy,int crystals,int potions,int turn,String status,List<String> log){this(ally,enemy,crystals,potions,turn,status,log,false);}
  }
  public static Fighter fighter(String species,int level,int variation) {
    return fighter(species,level,variation,0);
  }
  public static Fighter fighter(String species,int level,int variation,int evolution) {
    var f=new Fighter(species,level,variation,1,3,0,0,evolution);
    return f.change(f.maxHp(),3,0,0);
  }
  public static Battle start(Fighter ally,Fighter enemy) {return new Battle(ally,enemy,3,2,0,"active",List.of("Encounter started"));}
  public static double affinity(String attack,String defend) {
    if(attack.equals(defend)) return 1;
    return (attack.equals("water")&&defend.equals("fire")) || (attack.equals("fire")&&defend.equals("earth"))
        || (attack.equals("earth")&&defend.equals("water")) ? 1.5 : .75;
  }
  public static int damage(Fighter a,Fighter d,boolean magic,boolean critical) {
    var sa=species(a.speciesId); var sd=species(d.speciesId);
    double raw=(sa.attack+a.level*2+a.variation+a.evolution*4)*(magic?1.4:1)- (sd.defense+d.level+d.evolution*2)/2.0;
    return Math.max(1,(int)Math.round(raw*(magic?affinity(sa.element,sd.element):1)*(critical?1.5:1)) - d.shield);
  }
  public static double captureChance(Battle b) {
    return Math.clamp(.2+.65*(1-b.enemy.hp/(double)b.enemy.maxHp())
      -(species(b.enemy.speciesId).rarity.equals("Epic")?.12:0),.08,.85);
  }
  public static Battle action(Battle b,String move,Random random) {
    if(!b.status.equals("active")) throw new IllegalArgumentException("Battle finished");
    if(!List.of("strike","magic","burst","guard","heal","capture","retreat","switch").contains(move)) throw new IllegalArgumentException();
    if(move.equals("burst")&&(b.ally.level<3||b.ally.energy<2))throw new IllegalArgumentException("Burst unlocks at level 3 and costs two energy");
    if(move.equals("capture")&&b.boss)throw new IllegalArgumentException("Guardians cannot be captured");
    if(b.ally.hp<=0&&!move.equals("retreat"))throw new IllegalArgumentException("Switch to a healthy companion");
    if(move.equals("magic")&&b.ally.energy<1 || move.equals("heal")&&b.potions<1
        || move.equals("capture")&&b.crystals<1) throw new IllegalArgumentException("Resource exhausted");
    if(move.equals("retreat")) return new Battle(b.ally,b.enemy,b.crystals,b.potions,b.turn+1,"escaped",List.of("Retreated without rewards"),b.boss);
    Fighter a=b.ally,e=b.enemy; int crystals=b.crystals,potions=b.potions;
    var logs=new ArrayList<String>(b.log);logs.add("Turn "+(b.turn+1));
    a=a.change(a.hp-(a.poison>0?5:0),a.energy,Math.max(0,a.poison-1),0);
    if(a.hp==0) {logs.add("Poison caused defeat");return new Battle(a,e,crystals,potions,b.turn+1,"lost",List.copyOf(logs),b.boss);}
    boolean fast=species(a.speciesId).speed+a.level>=species(e.speciesId).speed+e.level;
    if(move.equals("guard")) {a=a.change(a.hp,Math.min(3,a.energy+1),a.poison,12+a.evolution*2);logs.add("Guard: shield and recover energy");}
    if(!fast) {a=enemyTurn(a,e,b.turn,random,logs,b.boss);}
    String status="active";
    if(a.hp>0) {
      switch(move) {
        case "strike", "magic", "burst" -> {
          boolean magic=!move.equals("strike"); boolean crit=random.nextDouble()<.1;
          int hit=(int)Math.round(damage(a,e,magic,crit)*(move.equals("burst")?1.6:1));
          if(random.nextDouble()>=.95){hit=0;logs.add("Attack missed");}
          e=e.change(e.hp-hit,e.energy,0,0);
          a=a.change(a.hp,magic?a.energy-(move.equals("burst")?2:1):Math.min(3,a.energy+1),a.poison,a.shield);
          logs.add(move+" dealt "+hit+(crit?" critical":""));
        }
        case "heal" -> {potions--;a=a.change(a.hp+30,a.energy,0,a.shield);logs.add("Potion restored up to 30 HP and cleared poison");}
        case "capture" -> {crystals--;if(random.nextDouble()<captureChance(new Battle(a,e,crystals,potions,b.turn,"active",List.of()))) {status="captured"; logs.add("Captured");}else logs.add("Capture failed");}
        default -> {}
      }
      if(e.hp==0) status="won";
      if(move.equals("switch"))logs.add("Companion switched; enemy responds");
      if(fast&&status.equals("active")) a=enemyTurn(a,e,b.turn,random,logs,b.boss);
    }
    if(a.hp==0) status="lost";
    if(b.turn>=49&&status.equals("active")){status="escaped";logs.add("Turn limit reached");}
    return new Battle(a,e,crystals,potions,b.turn+1,status,List.copyOf(logs),b.boss);
  }
  private static Fighter enemyTurn(Fighter a,Fighter e,int turn,Random r,List<String> log,boolean boss) {
    int hit=damage(e,a,turn%3==2,r.nextDouble()<.1);
    if(boss&&e.hp<e.maxHp()/2){hit=(int)Math.round(hit*1.4);log.add("Guardian phase 2: enraged");}
    log.add("Enemy dealt "+hit);
    return a.change(a.hp-hit,a.energy,turn%4==3?2:a.poison,0);
  }
}
