@echo off
REM add-dns-records.bat - Lab 05 Activity 1: create A + PTR records on the domain controller.
REM Double-click it on the Windows Server. It asks for admin rights if needed.

REM Relaunch as admin once; the "elevated" flag stops it relaunching itself in a loop
fltmc >nul 2>&1 || (
    if "%~1"=="elevated" (
        echo Could not get admin rights. Right-click the file and choose Run as administrator.
        pause
        exit /b
    )
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -LiteralPath '%~f0' -Raw) -split '#PS-START\r?\n', 2)[1]"
echo.
pause
exit /b

#PS-START
$ErrorActionPreference = 'Stop'

# Edit here if an IP changes: short hostname = IP address
$records = [ordered]@{
    'pfsense' = '192.168.1.254'   # pfSense gateway
    'storage' = '192.168.1.5'     # Rocky storage server
    'win11'   = '192.168.1.11'    # Windows 11 client
    'rocky'   = '192.168.1.4'     # Rocky client
}

try {
    $zone = (Get-ADDomain).DNSRoot
} catch {
    Write-Host "Could not find the domain. Run this on the domain controller." -ForegroundColor Red
    return
}
Write-Host "Domain zone: $zone`n"

foreach ($name in $records.Keys) {
    $ip = $records[$name]
    $o = $ip.Split('.')
    $revZone = "$($o[2]).$($o[1]).$($o[0]).in-addr.arpa"

    try {
        if (Get-DnsServerResourceRecord -ZoneName $zone -Name $name -RRType A -ErrorAction SilentlyContinue) {
            Write-Host "$name.$zone already has an A record"
        } else {
            Add-DnsServerResourceRecordA -ZoneName $zone -Name $name -IPv4Address $ip
            Write-Host "Added A    $name.$zone -> $ip" -ForegroundColor Green
        }

        if (Get-DnsServerResourceRecord -ZoneName $revZone -Name $o[3] -RRType Ptr -ErrorAction SilentlyContinue) {
            Write-Host "$ip already has a PTR record"
        } else {
            Add-DnsServerResourceRecordPtr -ZoneName $revZone -Name $o[3] -PtrDomainName "$name.$zone"
            Write-Host "Added PTR  $ip -> $name.$zone" -ForegroundColor Green
        }
    } catch {
        Write-Host "Problem with $name ($ip): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n--- Forward zone ($zone) ---"
Get-DnsServerResourceRecord -ZoneName $zone -RRType A | Format-Table HostName, @{n='IP';e={$_.RecordData.IPv4Address}} -AutoSize

Write-Host "--- Reverse zone ---"
Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone -and $_.ZoneName -like '*.168.192.in-addr.arpa' } | ForEach-Object {
    Get-DnsServerResourceRecord -ZoneName $_.ZoneName -RRType Ptr | Format-Table HostName, @{n='Points to';e={$_.RecordData.PtrDomainName}} -AutoSize
}
