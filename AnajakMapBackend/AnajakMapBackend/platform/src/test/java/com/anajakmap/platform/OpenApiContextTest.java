package com.anajakmap.platform;

import static org.junit.jupiter.api.Assertions.*;
import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class OpenApiContextTest {
  @Test void documentationAndErrorHandlerHaveDistinctBeanNames() {
    new ApplicationContextRunner().withUserConfiguration(Api.class,OpenApiConfig.class).run(context->{
      assertNull(context.getStartupFailure());
      assertNotNull(context.getBean(Api.class));
      assertNotNull(context.getBean(OpenAPI.class));
    });
  }
}
