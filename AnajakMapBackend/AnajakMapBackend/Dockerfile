FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /build
COPY . .
ARG SERVICE
RUN mvn -B -pl ${SERVICE}-service -am package -DskipTests
RUN cp ${SERVICE}-service/target/${SERVICE}-service-0.1.0-SNAPSHOT.jar /app.jar
FROM eclipse-temurin:21-jre-alpine
WORKDIR /opt/anajakmap
COPY --from=build /app.jar app.jar
RUN mkdir -p /opt/anajakmap/logs && chgrp -R 0 /opt/anajakmap && chmod -R g=u /opt/anajakmap
ENV LOG_PATH=/opt/anajakmap/logs
USER 1001
ENTRYPOINT ["java","-XX:MaxRAMPercentage=70","-jar","app.jar"]
