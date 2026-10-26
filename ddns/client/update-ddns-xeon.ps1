# =============================================================================
# CORNET DDNS Update Script - wvt465-xeon (Windows 10)
# =============================================================================
# Deployed to: C:\ProgramData\CORNET\update-ddns.ps1 on wvt465-xeon (128.173.94.81)
# Scheduled Task: CORNET-DDNS-Update (runs every 3 hours as SYSTEM)
# Updates IP via Flask API on dns-server container (198.82.18.150)
# =============================================================================

$hostname = "wvt465-xeon"
$apiUrl = "http://198.82.18.150:5000/update"
$token = "c156174195be0621f574b3fc11ed815f0c41b6cf2f51ddc6b512d3ed01f1ee96"
$logFile = "C:\ProgramData\CORNET\ddns-update.log"

# Get current campus IP (ethernet only, not loopback or VPN)
$currentIP = (Get-NetIPAddress -AddressFamily IPv4 `
    | Where-Object { $_.IPAddress -notlike "127.*" `
    -and $_.IPAddress -notlike "169.*" `
    -and $_.IPAddress -notlike "100.*" `
    -and $_.PrefixOrigin -ne "WellKnown" } `
    | Select-Object -First 1).IPAddress

# Build request body
$body = @{
    hostname = $hostname
    ip       = $currentIP
    token    = $token
} | ConvertTo-Json

# Send update to API
try {
    $response = Invoke-WebRequest -Uri $apiUrl `
        -Method POST `
        -Body $body `
        -ContentType "application/json" `
        -UseBasicParsing
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - Updated $hostname -> $currentIP" | Add-Content $logFile
    Write-Host "Updated: $currentIP"
} catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - Failed to update: $_" | Add-Content $logFile
    Write-Host "Failed: $_"
}
