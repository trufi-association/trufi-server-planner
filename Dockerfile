FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files and get dependencies (from git)
COPY pubspec.* ./
RUN dart pub get

# Copy source files
COPY lib ./lib
COPY bin ./bin

# Compile the server
RUN dart compile exe bin/server.dart -o bin/server

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates wget && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled binary
COPY --from=build /app/bin/server /app/server

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/health || exit 1

# Run the server
ENTRYPOINT ["/app/server"]
