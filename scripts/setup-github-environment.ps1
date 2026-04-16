param(
    [Parameter(Mandatory=$true)]
    [string]$EnvFile,
    
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    
    [Parameter(Mandatory=$true)]
    [string]$Repo
)

# Validate file exists
if (-not (Test-Path $EnvFile)) {
    Write-Error "File not found: $EnvFile"
    exit 1
}

# Parse .env file into a hashtable
$envVars = @{}
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        return
    }
    
    # Parse key=value pairs
    if ($line -match '^\s*([^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        
        # Remove surrounding quotes if present
        if ($value[0] -in @('"', "'") -and $value[0] -eq $value[-1] -and $value.Length -gt 1) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        
        $envVars[$key] = $value
    }
}

# Extract environment name
$environmentName = $envVars["AZURE_ENV_NAME"]
if (-not $environmentName) {
    Write-Error "AZURE_ENV_NAME not found in $EnvFile"
    exit 1
}

Write-Host "GitHub environment name: $environmentName" -ForegroundColor Green
Write-Host "GitHub repository name: $Owner/$Repo`n" -ForegroundColor Green

# Create environment (idempotent)
Write-Host "Creating GitHub environment '$environmentName'..." -ForegroundColor Yellow

gh api repos/$Owner/$Repo/environments/$environmentName --method PUT 2>$null

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 422) {  # 422 = already exists
    Write-Host "✓ Environment ready`n" -ForegroundColor Green
} else {
    Write-Error "Failed to create environment"
    exit 1
}

# Add all variables and secrets (except AZURE_ENV_NAME) to the environment
$count = 0
$envVars.GetEnumerator() | ForEach-Object {
    $key = $_.Key
    $value = $_.Value
    
    # Skip AZURE_ENV_NAME (it's only used for the environment name)
    if ($key -eq "AZURE_ENV_NAME") {
        return
    }
    
    $count++
    
    # Treat sensitive-looking variables as secrets; others as environment variables
    if ($key -match '(SECRET|KEY|TOKEN|PASSWORD|CREDENTIAL)') {
        $value | gh secret set $key --env $environmentName 2>$null
    } else {
        $value | gh variable set $key --env $environmentName 2>$null
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set $key"
        exit 1
    }
}

Write-Host "`n✓ GitHub environment configured successfully!" -ForegroundColor Green
Write-Host "   Environment: $environmentName" -ForegroundColor Green
Write-Host "   Variables/Secrets added: $count" -ForegroundColor Green
