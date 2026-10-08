package com.anajakmap.platform;

import io.swagger.v3.oas.models.*;
import io.swagger.v3.oas.models.info.*;
import io.swagger.v3.oas.models.security.*;
import org.springframework.context.annotation.*;

@Configuration
public class OpenApiConfig {
  @Bean
  OpenAPI openApiDefinition() {
    return new OpenAPI()
        .info(
            new Info()
                .title("AnajakMap API")
                .version("v1")
                .description(
                    "Authenticated travel APIs. JSON success: data, traceId, timestamp. Errors:"
                        + " code, message, traceId, timestamp. Use Idempotency-Key for protected"
                        + " creates. Media is multipart and content endpoints return binary."))
        .components(
            new Components()
                .addSecuritySchemes(
                    "bearer",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")))
        .addSecurityItem(new SecurityRequirement().addList("bearer"));
  }
}
