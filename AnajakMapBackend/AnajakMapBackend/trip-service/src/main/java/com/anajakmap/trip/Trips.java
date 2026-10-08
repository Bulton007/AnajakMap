package com.anajakmap.trip;

import org.springframework.data.jpa.repository.JpaRepository;

public interface Trips extends JpaRepository<Trip, String> {}
