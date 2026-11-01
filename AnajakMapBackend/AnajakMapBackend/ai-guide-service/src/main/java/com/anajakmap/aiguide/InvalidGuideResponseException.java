package com.anajakmap.aiguide;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** A provider reply failed validation; never blame valid user input or expose the reply. */
final class InvalidGuideResponseException extends ResponseStatusException {
  InvalidGuideResponseException() {
    super(HttpStatus.BAD_GATEWAY,
        "The AI returned an incomplete or invalid answer. Please try again. Your trip has not been changed.");
  }
}
