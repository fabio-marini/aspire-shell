# Copilot Instructions

## Build, Test, and Run

```bash
# Restore and build
dotnet restore src/AzdAspire.sln
dotnet build src/AzdAspire.sln --configuration Release

# Run all tests
dotnet test src/AzdAspire.sln --configuration Release --verbosity normal

# Run a single test
dotnet test src/AzdAspire.Tests/AzdAspire.Tests.csproj --filter "FullyQualifiedName~<TestName>"

# Run locally (Development profile — RabbitMQ container)
dotnet run --project src/AzdAspire.AppHost/AzdAspire.AppHost.csproj --launch-profile Development

# Run in hybrid mode (Azure services, local apps)
dotnet run --project src/AzdAspire.AppHost/AzdAspire.AppHost.csproj --launch-profile Production
```

## Architecture Overview

This is a **.NET 10 / Aspire** solution (`src/AzdAspire.sln`) that deploys to **Azure Container Apps** via `azd`.

### Projects

| Project | Role |
|---|---|
| `AzdAspire.AppHost` | Aspire orchestrator — wires all resources and projects together |
| `AzdAspire.ServiceDefaults` | Shared library — OpenTelemetry, health checks, service discovery, Rebus message types |
| `AzdAspire.WebApplication1` | ASP.NET app — exposes `POST /echo`, sends `EchoRequest` via Rebus |
| `AzdAspire.WebApplication2` | ASP.NET app — handles `EchoRequest`, replies with `EchoResponse` |
| `AzdAspire.Tests` | Aspire integration test harness (currently a scaffold) |

### Three Development Modes

The `AppHost` branches on `IsDevelopment()`:

- **Local** (`Development` profile): No Azure resources. RabbitMQ runs as a Docker container; secrets/settings come from `dotnet user-secrets` and `appsettings.Development.json`.
- **Hybrid** (`Production` profile + `HYBRID_ENVIRONMENT=true` in `.azure/<env>/.env`): Only shared Azure services (Key Vault, App Config, Service Bus) are provisioned. Apps run locally.
- **Cloud** (full `azd provision` + `azd deploy`): All resources provisioned; apps run in Azure Container Apps.

### Messaging (Rebus)

[Rebus](https://github.com/rebus-org/Rebus) abstracts transport:
- **Local**: RabbitMQ (`rmq-messaging` connection string)
- **Hybrid/Cloud**: Azure Service Bus (`asb-messaging` connection string)

Queue names are hardcoded: `rebus-webapp1` (WebApp1's inbox) and `rebus-webapp2` (WebApp2's inbox). `EchoRequest` routes to `rebus-webapp2`; replies go back to `rebus-webapp1`.

### Configuration Resolution (`AddFromConfiguration`)

`AppHost/Extensions.cs` provides `AddFromConfiguration(name, key)`:
1. If the resource already exists in the builder, return it.
2. If `.azure/<env>/.env` contains the config key (e.g., `ASB_MESSAGING_SERVICEBUSENDPOINT`), create a connection-string resource from that URI.
3. Otherwise, return `null` — and the caller falls back to `AddAzureServiceBus(...)` etc. to let Aspire provision a new resource.

This pattern is what makes hybrid mode work without code changes.

### Azure Credentials (`WithAzureCredentials`)

Each web app uses a custom `DefaultAzureCredential` that:
- Excludes `WorkloadIdentity` and `SharedTokenCache` always.
- Excludes `ManagedIdentity` in `Development` (so local VS/CLI credentials are used).

### Infrastructure (Bicep)

`infra/` is modular:
- `main.bicep` — subscription-scoped entry point; delegates to `main-hybrid.bicep` or `main-remote.bicep` based on the `hybridEnvironment` flag.
- `main-hybrid.bicep` — deploys shared services and assigns developer RBAC roles. Used when `hybridEnvironment = true`.
- `main-remote.bicep` — deploys both shared services and cloud resources, and assigns Managed Identity RBAC roles. Used for full cloud deployments.
- `services.bicep` — always-deployed shared services: Key Vault, App Config, Service Bus.
- `resources.bicep` — Container Apps environment, ACR, Managed Identity (used by `main-remote.bicep` only).
- `app-roles.bicep` — assigns RBAC roles for a given principal; called once by each sub-entrypoint.

The `hybridEnvironment` Bicep parameter must be set manually in `.azure/<env>/.env` as `HYBRID_ENVIRONMENT="true"`.

## CI/CD Pipelines

Two GitHub Actions workflows in `.github/workflows/`:

| Workflow | File | Trigger | What it does |
|---|---|---|---|
| CI | `aspire-shell-ci.yml` | Push/PR to `main` or `develop` | `dotnet restore` → `build` → `test` with XPlat Code Coverage → generate coverage report via ReportGenerator → upload test results and coverage report as GitHub Artifacts |
| CD | `aspire-shell-cd.yml` | Manual (`workflow_dispatch`) | `azd provision` then `azd deploy` — provisions infrastructure and deploys application code in one run |

### Required GitHub repository variables (for CD)

These must be set as **repository variables** (not secrets) before either workflow can run. `AZURE_ENV_NAME` is supplied as a `workflow_dispatch` **input** at run time (not a repository variable):

| Variable | Description |
|---|---|
| `AZURE_CLIENT_ID` | Client ID of the app registration used for OIDC login |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `AZURE_LOCATION` | Azure region (e.g., `eastus`) |

`AZURE_ENV_NAME` is provided interactively when triggering the CD workflow via `workflow_dispatch`.

Authentication uses **OIDC federated credentials** (no client secret stored). The app registration needs a federated credential for the GitHub repo. Run `azd pipeline config -e <env>` to set this up automatically.

## RBAC Role Assignments

`infra/app-roles.bicep` is invoked once by each sub-entrypoint:
1. `main-hybrid.bicep` calls it for the developer (`principalType: 'User'`, `principalId` from `AZURE_PRINCIPAL_ID`).
2. `main-remote.bicep` calls it for the app's Managed Identity (`principalType: 'ServicePrincipal'`, ID from `resources.bicep` output).

The following roles are assigned to both principals on each shared service:

| Resource | Role | Role Definition ID |
|---|---|---|
| Key Vault | **Key Vault Secrets Officer** | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| App Configuration | **App Configuration Data Owner** | `5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b` |
| Service Bus | **Azure Service Bus Data Owner** | `090c5cfd-751d-490a-894a-3ce6f1109419` |

> **Note**: The `Key Vault Secrets User` role (`4633458b...`) is commented out in `app-secrets-roles.module.bicep` in favour of the broader `Key Vault Secrets Officer` role. Do not switch back without updating both the developer and MI assignments.

## Key Conventions

- **`Extensions.cs` pattern**: Every project has an `Extensions.cs` with static extension methods on `IHostApplicationBuilder` for service registration. New integrations should follow this pattern.
- **Shared message types live in `ServiceDefaults`**: `EchoRequest` and `EchoResponse` are `sealed record` types in `AzdAspire.ServiceDefaults.Messages`. New message types belong there.
- **Connection strings drive feature activation**: `AddAzureKeyVault()`, `AddAzureAppConfiguration()`, and `AddRebus()` in the web apps check for their connection string before registering — absent connection string = feature silently skipped (correct for local mode).
- **Secret naming**: Key Vault secrets use `--` as separator (e.g., `WebApp1--AppKey`) which maps to `WebApp1:AppKey` in .NET configuration.
- **`.env` file**: `AppHost` loads `.azure/<DOTNET_ENVIRONMENT>/.env` at startup via `DotNetEnv`. The `Production` launch profile sets `DOTNET_ENVIRONMENT` to the `azd` environment name.
- **Test endpoint**: `POST /echo` on WebApp1 (default dev port `https://localhost:7099`) is the integration smoke test. Check WebApp2 logs for `EchoRequest` received and WebApp1 logs for `EchoResponse` received.
