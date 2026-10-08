package com.anajakmap.trip;

import jakarta.persistence.*;
import java.time.*;

@Entity
@Table(name = "trips")
public class Trip {
  @Id public String id;
  public String ownerId;
  public String title;
  public String destination;
  public String timezone;
  public LocalDate startDate;
  public LocalDate endDate;
  public Instant createdAt = Instant.now();
  @Version public long version;

  public Trip() {}
}
