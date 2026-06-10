# syntax=docker/dockerfile:1
# ---- Build stage ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore first (better layer cache)
COPY src/app-modern-linux.csproj ./
RUN dotnet restore app-modern-linux.csproj

# Build + publish
COPY src/ ./
RUN dotnet publish app-modern-linux.csproj -c Release -o /app /p:UseAppHost=false

# ---- Runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app ./

# Listen on 8080 (non-privileged port, matches Service/probes)
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Run as the non-root user provided by the aspnet image
USER app

ENTRYPOINT ["dotnet", "app-modern-linux.dll"]
