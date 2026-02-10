FROM dart:stable AS build

WORKDIR /app

# Copy trufi_core_planner dependency
COPY trufi-core/packages/trufi_core_planner /deps/trufi_core_planner

# Copy pubspec files
COPY trufi-server-planner/pubspec.* ./

# Override git dependency with local path for Docker build
RUN sed -i '/trufi_core_planner:/,/path: packages\/trufi_core_planner/{s|git:|# git:|;s|url:.*|# &|;s|ref:.*|# &|;s|path: packages/trufi_core_planner|path: /deps/trufi_core_planner|}' pubspec.yaml

# Get dependencies
RUN dart pub get

# Copy source files
COPY trufi-server-planner/lib ./lib
COPY trufi-server-planner/bin ./bin
COPY trufi-server-planner/gtfs_data.zip ./gtfs_data.zip
COPY trufi-server-planner/web ./web

# Compile the server
RUN dart compile exe bin/server.dart -o bin/server

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates wget && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled binary, GTFS data, and web files
COPY --from=build /app/bin/server /app/server
COPY --from=build /app/gtfs_data.zip /app/gtfs_data.zip
COPY --from=build /app/web /app/web

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/health || exit 1

# Run the server
ENTRYPOINT ["/app/server"]
