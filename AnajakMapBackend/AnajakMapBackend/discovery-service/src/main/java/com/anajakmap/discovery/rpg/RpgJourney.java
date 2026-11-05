package com.anajakmap.discovery.rpg;

import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

/** All writes run inside RpgService's account lock and idempotent transaction. */
final class RpgJourney {
  private final JdbcTemplate db;
  private final Clock clock;
  RpgJourney(JdbcTemplate db, Clock clock) { this.db=db; this.clock=clock; }
  private static double n(Map<String,Object> row,String key) { return ((Number)row.get(key)).doubleValue(); }
  boolean owns(String scope,String destination) {
    return db.queryForObject("SELECT COUNT(*) FROM rpg_journey_visits WHERE scope_id=? AND destination_id=?",Integer.class,scope,destination)>0;
  }
  Object current(String scope) {
    var rows=db.queryForList("SELECT id FROM rpg_journeys WHERE scope_id=? ORDER BY started_at DESC FETCH FIRST 1 ROWS ONLY",scope);
    return rows.isEmpty()?Map.of("available",true):view(scope,rows.getFirst().get("ID").toString());
  }
  private Map<String,Object> row(String scope,String id) {
    var rows=db.queryForList("SELECT * FROM rpg_journeys WHERE scope_id=? AND id=?",scope,id);
    if(rows.isEmpty())throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Journey not found");
    return rows.getFirst();
  }
  private Object view(String scope,String id) {
    var out=new LinkedHashMap<String,Object>();out.put("journey",row(scope,id));
    out.put("points",db.queryForList("SELECT latitude,longitude,accuracy,measured_at,sequence_no FROM rpg_journey_points WHERE journey_id=? ORDER BY sequence_no",id));
    return out;
  }
  Object start(String scope) {
    var active=db.queryForList("SELECT id FROM rpg_journeys WHERE scope_id=? AND ended_at IS NULL",scope);
    String id=active.isEmpty()?UUID.randomUUID().toString():active.getFirst().get("ID").toString();
    if(active.isEmpty())db.update("INSERT INTO rpg_journeys(id,scope_id,started_at) VALUES(?,?,?)",id,scope,Timestamp.from(clock.instant()));
    return view(scope,id);
  }
  Object stop(String scope,String id) {
    row(scope,id);
    db.update("UPDATE rpg_journeys SET ended_at=? WHERE scope_id=? AND id=? AND ended_at IS NULL",Timestamp.from(clock.instant()),scope,id);
    return view(scope,id);
  }
  Object point(String scope,String id,RpgRules.Location point) {
    var journey=row(scope,id);
    if(journey.get("ENDED_AT")!=null)throw new ResponseStatusException(HttpStatus.CONFLICT,"Journey has ended");
    if(!RpgRules.validLocation(point,clock.instant()))throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Fresh accurate non-mocked GPS is required");
    var previous=db.queryForList("SELECT * FROM rpg_journey_points WHERE journey_id=? ORDER BY sequence_no DESC FETCH FIRST 1 ROWS ONLY",id);
    Map<String,Object> last=previous.isEmpty()?null:previous.getFirst();
    int sequence=last==null?1:((Number)last.get("SEQUENCE_NO")).intValue()+1;
    if(sequence>3000)throw new ResponseStatusException(HttpStatus.CONFLICT,"Journey point limit reached; end this journey and start another");
    double distance=0;long seconds=0;
    if(last!=null) {
      seconds=Duration.between(((Timestamp)last.get("MEASURED_AT")).toInstant(),point.measuredAt()).getSeconds();
      if(seconds<10)return Map.of("accepted",false);
      distance=RpgRules.distance(n(last,"LATITUDE"),n(last,"LONGITUDE"),point.latitude(),point.longitude());
      if(distance/seconds>90)throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"GPS movement is implausible; wait for an accurate fix");
    }
    // Discard small positional jitter from travelled distance.
    double travelled=last!=null&&seconds<=45&&distance>Math.max(10,Math.max(point.accuracy(),n(last,"ACCURACY")))?distance:0;
    db.update("INSERT INTO rpg_journey_points(journey_id,sequence_no,latitude,longitude,accuracy,measured_at) VALUES(?,?,?,?,?,?)",id,sequence,point.latitude(),point.longitude(),point.accuracy(),Timestamp.from(point.measuredAt()));
    db.update("UPDATE rpg_journeys SET distance_m=distance_m+? WHERE id=?",travelled,id);
    String destination=null;
    // Two nearby samples at least 10 seconds apart establish a stop. Long gaps
    // after pausing cannot establish dwell time.
    if(last!=null&&seconds<=45&&distance<=25) {
      var visits=db.queryForList("SELECT d.id,d.latitude,d.longitude FROM rpg_destinations d JOIN rpg_journey_visits v ON v.destination_id=d.id WHERE v.scope_id=?",scope);
      for(var v:visits)if(RpgRules.distance(n(v,"LATITUDE"),n(v,"LONGITUDE"),point.latitude(),point.longitude())<=75) {destination=v.get("ID").toString();break;}
      if(destination==null) {
        destination="journey-"+UUID.randomUUID();
        db.update("INSERT INTO rpg_destinations(id,name,latitude,longitude,radius_m,habitat,accessible,source) VALUES(?,?,?, ?,100,'roaming',1,'Personal GPS journey stop')",destination,"Journey stop",point.latitude(),point.longitude());
        db.update("INSERT INTO rpg_journey_visits(destination_id,scope_id,journey_id,visited_at) VALUES(?,?,?,?)",destination,scope,id,Timestamp.from(point.measuredAt()));
        for(var species:RpgRules.SPECIES)db.update("INSERT INTO rpg_spawn_rules(destination_id,species_id,weight) VALUES(?,?,?)",destination,species.id(),species.weight());
      }
    }
    var result=new LinkedHashMap<String,Object>();
    result.put("accepted",true);result.put("destinationId",destination);
    result.put("distanceM",n(journey,"DISTANCE_M")+travelled);
    result.put("sequence",sequence);
    return result;
  }
}
