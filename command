$zone = (Get-ADDomain).DNSRoot

$records = @{
    "pfsense" = "192.168.1.254"   # pfSense gateway
    "storage" = "192.168.1.5"     # Rocky storage server
    "win11"   = "192.168.1.11"    # Windows 11 client
    "rocky"   = "192.168.1.4"     # Rocky client
}

foreach ($name in $records.Keys) {
    if (Get-DnsServerResourceRecord -ZoneName $zone -Name $name -RRType A -ErrorAction SilentlyContinue) {
        Write-Host "$name already exists, skipping"
    } else {
        Add-DnsServerResourceRecordA -ZoneName $zone -Name $name -IPv4Address $records[$name] -CreatePtr
        Write-Host "Added $name.$zone -> $($records[$name]) (with PTR)"
    }
}
