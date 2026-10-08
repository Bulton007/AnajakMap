package com.anajakmap.platform;

import java.time.Instant;
import java.util.*;
import org.slf4j.MDC;
import org.springframework.core.MethodParameter;
import org.springframework.http.*;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.server.*;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseBodyAdvice;

@RestControllerAdvice
public class Success implements ResponseBodyAdvice<Object> {
  public boolean supports(MethodParameter p, Class<? extends HttpMessageConverter<?>> c) {
    return true;
  }

  public Object beforeBodyWrite(
      Object body,
      MethodParameter p,
      MediaType m,
      Class<? extends HttpMessageConverter<?>> c,
      ServerHttpRequest req,
      ServerHttpResponse res) {
    if (body == null
        || body instanceof byte[]
        || body instanceof Api.Error
        || !req.getURI().getPath().startsWith("/api/v1/")) return body;
    return new Envelope(body, Objects.toString(MDC.get("traceId"), ""), Instant.now());
  }
  public record Envelope(Object data,String traceId,Instant timestamp) {}
}
