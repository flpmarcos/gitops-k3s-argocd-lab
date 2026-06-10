using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

var app = builder.Build();

// ---- Config sources ----
// APP_VERSION  -> injected by Deployment env (image tag mirror), defaults to "dev"
// Greeting     -> comes from ConfigMap (appsettings-style key)
// APP_SECRET   -> comes from Secret, never logged in full
var version  = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev";
var greeting = app.Configuration["Greeting"] ?? "Hello from modern Linux app";
var secret   = Environment.GetEnvironmentVariable("APP_SECRET") ?? "no-secret-set";
var maskedSecret = secret.Length <= 4 ? "****" : secret[..2] + "****" + secret[^2..];

var startedAt = DateTimeOffset.UtcNow;

app.MapGet("/", () => Results.Ok(new
{
    message   = greeting,
    version,
    secretHint = maskedSecret,
    hostname  = Environment.MachineName
}));

// Liveness + readiness target. Cheap, no external deps.
app.MapGet("/health", () => Results.Ok(new
{
    status    = "healthy",
    uptimeSec = (long)(DateTimeOffset.UtcNow - startedAt).TotalSeconds
}));

app.MapGet("/version", () => Results.Ok(new
{
    version,
    framework = Assembly.GetEntryAssembly()?
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
        ?? Environment.Version.ToString(),
    dotnet = Environment.Version.ToString()
}));

app.Run();
