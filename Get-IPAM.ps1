#
# Written to use with PHP IPAM v1.7.3
#
# Purpose: Get addresses, subnets and vlans from IPAM
#   - Defaults to subnets. For each subnet it will display:  mastersubnet (cidr), subnet (cidr), vlanid (number), vlanname, description
#   - The idea is to have phpIPAM avaliable in cli for quick lookups
#
# Requires HTTPS and a valid cert
#   - To accept self signed, ovveride TLS settings on PowerShell-process/console before running script
#   - Hint for Windows PowerShell (5.1): [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#
# Requires "SSL with App code token" API to be created in IPAM web-gui
#   - appid and token is needed as script parameter (read only)
#

Param(
    [Parameter(Mandatory = $false)][ValidateSet('subnets', 'vlans', 'addresses')][String]$Type = 'subnets',
    [Parameter(Mandatory = $false)][String]$appid = '100',
    [Parameter(Mandatory = $false)][String]$token = 'TOKEN_HERE',
    [Parameter(Mandatory = $false)][String]$baseUrl = 'https://ipam.domain.com/api'
)

$headers = @{
    "token" = "$token" #Read-only
    "Accept" = "application/json"
    "Content-Type" = "application/json"
}

$urlsubnets =   "$baseUrl/$appid/subnets/"
$urlvlans =     "$baseUrl/$appid/vlans/" 
$urladdresses = "$baseUrl/$appid/addresses/"

if ($Type -eq 'subnets') {    
    $subnets    = (Invoke-RestMethod -Uri $urlsubnets -Headers $headers -Method Get).data
    $vlans      = (Invoke-RestMethod -Uri $urlvlans -Headers $headers -Method Get).data
}
if ($Type -eq 'vlans') {
    $vlans      = (Invoke-RestMethod -Uri $urlvlans -Headers $headers -Method Get).data
}
if ($Type -eq 'addresses') {
    $subnets    = (Invoke-RestMethod -Uri $urlsubnets -Headers $headers -Method Get).data
    $addresses  = (Invoke-RestMethod -Uri $urladdresses -Headers $headers -Method Get).data
}

if ($Type -eq 'subnets') {
    $processedSubnets = @()
    Foreach ($subnet in $subnets) {

        if ($subnet.masterSubnetId) {
            $mastersubnet = $subnets | Where-Object {$_.id -eq $subnet.masterSubnetId}
        }
        else {
            $mastersubnet = '-'
        }

        if ($subnet.vlanId) {
            $vlan = $vlans | Where-Object {$_.id -eq $subnet.vlanId}
            $vlanid = $vlan.number
            $vlanname = $vlan.name
        }
        else {
            $vlanid = '-'
            $vlanname = '-'
            $vlan = '-'
        }

        $Obj = New-Object PSObject -property @{
            mastersubnet = "$($mastersubnet.subnet)/$($mastersubnet.mask)"
            subnet = "$($subnet.subnet)/$($subnet.mask)"
            description = $subnet.description
            vlanid = $vlanid
            vlanname = $vlanname
        }
        $processedSubnets += $Obj
    }
    Clear-Variable mastersubnet, vlan, vlanid, vlanname
    $processedSubnets | Select-Object mastersubnet, subnet, vlanid, vlanname, description | Sort-Object mastersubnet, subnet
}

if ($Type -eq 'vlans') {
    $vlans | Select-Object number, name, description | Sort-Object number
}

if ($Type -eq 'addresses') {
    $processedAddresses = @()
    Foreach ($address in $addresses) {

        if ($address.subnetId) {
            $subnet = $subnets | Where-Object {$_.id -eq $address.subnetId}
        }
        else {
            $subnet = '-'
        }

        $Obj = New-Object PSObject -property @{
            subnet = "$($subnet.subnet)/$($subnet.mask)"
            ip = $address.ip
            hostname = $address.hostname
            description = $address.description
        }
        $processedAddresses += $Obj
    }
    Clear-Variable subnet
    $processedAddresses | Select-Object subnet, ip, hostname, description | Sort-Object subnet, ip
}
