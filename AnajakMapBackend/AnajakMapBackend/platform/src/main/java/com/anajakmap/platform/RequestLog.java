package com.anajakmap.platform;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.*;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class RequestLog extends OncePerRequestFilter {
  private static final Logger log = LoggerFactory.getLogger(RequestLog.class);

  protected void doFilterInternal(
      HttpServletRequest req, HttpServletResponse res, FilterChain chain)
      throws ServletException, IOException {
    String incoming = req.getHeader("X-Trace-ID");
    String trace =
        incoming != null && incoming.matches("[a-zA-Z0-9-]{1,64}")
            ? incoming
            : UUID.randomUUID().toString();
    long start = System.nanoTime();
    MDC.put("traceId", trace);
    res.setHeader("X-Trace-ID", trace);
    try {
      chain.doFilter(req, res);
    } finally {
      log.info(
          "api method={} route={} status={} duration_ms={} user={}",
          req.getMethod(),
          req.getRequestURI(),
          res.getStatus(),
          (System.nanoTime() - start) / 1000000,
          req.getUserPrincipal() == null ? "anonymous" : req.getUserPrincipal().getName());
      MDC.clear();
    }
  }
}
