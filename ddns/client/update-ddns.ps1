# =============================================================================
# CORNET DDNS Update Script - Windows Workstation Client
# =============================================================================
# Deployed to: C:\ProgramData\CORNET\update-ddns.ps1
# Runs automatically on boot via Windows Task Scheduler (CORNET-DDNS-Update)
# Updates IP via Flask API on dns-server container (198.82.18.150)
# =============================================================================

param(
    [string]$Hostname = $(if ($env:CORNET_HOSTNAME) { $env:CORNET_HOSTNAME } else { $env:COMPUTERNAME.ToLower() }),
    [string]$ApiUrl = "http://198.82.18.150:5000/update",
    [string]$Token = "c156174195be0621f574b3fc11ed815f0c41b6cf2f51ddc6b512d3ed01f1ee96",
    [string]$LogFile = "C:\ProgramData\CORNET\ddns-update.log"
)

# Ensure log directory exists
$logDir = Split-Path -Path $LogFile -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Retry loop up to 5 attempts with 5-second sleep (handles boot DHCP delay)
for ($attempt = 1; $attempt -le 5; $attempt++) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Get current campus IP (ethernet only: exclude loopback, APIPA 169.254, Tailscale 100.*, and link-local)
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 `
        | Where-Object { 
            $_.IPAddress -notlike "127.*" `
            -and $_.IPAddress -notlike "169.254*" `
            -and $_.IPAddress -notlike "100.*" `
            -and $_.PrefixOrigin -ne "WellKnown" 
        } `
        | Select-Object -First 1).IPAddress

    if (-not $currentIP) {
        "$timestamp - Attempt $attempt: No IPv4 address detected yet, retrying..." | Add-Content $LogFile
        Start-Sleep -Seconds 5
        continue
    }

    # Build request body
    $body = @{
        hostname = $Hostname
        ip       = $currentIP
        token    = $Token
    } | ConvertTo-Json

    # Send update to API
    try {
        $response = Invoke-WebRequest -Uri $ApiUrl `
            -Method POST `
            -Body $body `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 5

        if ($response.StatusCode -eq 200) {
            "$timestamp - Updated $Hostname -> $currentIP (attempt $attempt)" | Add-Content $LogFile
            Write-Host "Updated: $currentIP"
            exit 0
        }
    } catch {
        "$timestamp - Attempt $attempt: Failed to update: $_" | Add-Content $LogFile
    }

    Start-Sleep -Seconds 5
}

"$timestamp - Failed to update after 5 attempts" | Add-Content $LogFile
Write-Error "Failed to update DDNS after 5 attempts."
exit 1
