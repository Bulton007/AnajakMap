package com.anajakmap.platform;

import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

public final class HttpClients {
  private HttpClients() {}

  public static RestClient client(String url) {
    return client(url, Duration.ofSeconds(15));
  }

  public static RestClient client(String url, Duration timeout) {
    var f =
        new JdkClientHttpRequestFactory(
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
    f.setReadTimeout(timeout);
    return RestClient.builder()
        .baseUrl(url)
        .requestFactory(f)
        .requestInterceptor(
            (request, body, execution) -> {
              String trace = org.slf4j.MDC.get("traceId");
              if (trace != null) request.getHeaders().set("X-Trace-ID", trace);
              int max = request.getMethod() == org.springframework.http.HttpMethod.GET ? 3 : 1;
              for (int i = 1; ; i++) {
                try {
                  var response = execution.execute(request, body);
                  if (i < max && response.getStatusCode().is5xxServerError()) {
                    response.close();
                    continue;
                  }
                  return response;
                } catch (java.io.IOException e) {
                  if (i >= max) throw e;
                }
              }
            })
        .build();
  }
}
