# Windows container image — IIS serving a static page.
# IMPORTANT: this image ONLY builds/runs on a Windows host with Windows containers
# enabled (Docker Desktop in "Windows containers" mode, or a Windows Server host).
# It CANNOT be built on Linux/WSL or run on K3s. See README "Por que o app Windows
# nao sobe no K3s local".
#
# Alternative base (ASP.NET 4.8 / .NET Framework):
#   FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2022

FROM mcr.microsoft.com/windows/servercore/iis:windowsservercore-ltsc2022

# Drop the default IIS page and ship our static site
RUN powershell -NoProfile -Command "Remove-Item -Recurse -Force C:\inetpub\wwwroot\*"
COPY site/ C:/inetpub/wwwroot/

# IIS already exposes 80 and starts via ServiceMonitor in the base image
EXPOSE 80

# HEALTHCHECK uses PowerShell because curl is not guaranteed on servercore
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD powershell -NoProfile -Command "try { (Invoke-WebRequest -UseBasicParsing http://localhost/).StatusCode -eq 200 ? 0 : 1 } catch { exit 1 }"
