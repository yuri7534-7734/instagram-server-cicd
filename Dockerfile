# JDK 17
FROM eclipse-temurin:17-jdk

# Rename jar filename
COPY build/libs/*SNAPSHOT.jar app.jar

# Start command on start container
ENTRYPOINT ["java", "-jar", "/app.jar"]