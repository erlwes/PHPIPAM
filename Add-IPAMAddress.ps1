#
# Written to use with PHP IPAM v1.7.3
#
# Purpose: Create and update addresses in IPAM.
#   - If IP already exist, it will see if there are changes to hostname and desc, and if so, update the values
#   - Each input object can have multiple IPs (to support multi homed endpoints with several NICs)
#   - The subnets needs to exist in IPAM-already, but it will automatically figure out what subnet the address belongs in
#   - Script accepts PSObject form pipeline with ip, hostname and desc properties
#   - The idea is to use this script to create addresses from AD, Azure, AWS, your local hypervisor via. csv og PowerShell-objects with direct piping
#
# Requires HTTPS and a valid cert
#   - To accept self signed, ovveride TLS settings on PowerShell-process/console before running script
#   - Hint for Windows PowerShell (5.1): [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#
# Requires "SSL with App code token" API to be created in IPAM web-gui
#   - appid and token is needed as script parameter
#

param (
    [cmdletbinding()]
    [parameter(mandatory=$false, ValueFromPipeline=$true)][PSObject]$PSObject,
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$ip,
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$hostname,
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$description,
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$appid = '100',
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$token = 'TOKEN_HERE',
    [parameter(mandatory=$false, ValueFromPipeline=$false)][string]$baseUrl = 'https://ipam.domain.com/api'
)

begin {
    # [AUTH] (token + app id)
    $Headers = @{
        "token" = "$token"
        "Accept" = "application/json"
        "Content-Type" = "application/json"
    }

    # [API ENDPOINTS]
    $UrlSubnets = "$baseUrl/$AppID/subnets/"
    $UrlAddresses = "$baseUrl/$AppID/addresses/"
    
    # [FUNTIONS] (Borrowed from somewhere. Probably GitHub)
    Function Test-IPAddressInSubnet {
        [CmdletBinding()]
        [OutputType([bool], [string[]])]
        param (
            # IP Address to test against provided subnets.
            [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
            [ipaddress[]] $IpAddresses,
            # List of subnets.
            [Parameter(Mandatory = $true)]
            [string[]] $Subnets,
            # Return list of matching subnets rather than a boolean result.
            [Parameter(Mandatory = $false)]
            [switch] $ReturnMatchingSubnets
        )

        process {
            foreach ($IpAddress in $IpAddresses) {
                [System.Collections.Generic.List[string]] $listSubnets = New-Object System.Collections.Generic.List[string]
                [bool] $Result = $false
                foreach ($Subnet in $Subnets) {
                    [string[]] $SubnetComponents = $Subnet.Split('/')

                    [int] $bitIpAddress = [BitConverter]::ToInt32($IpAddress.GetAddressBytes(), 0)
                    [int] $bitSubnetAddress = [BitConverter]::ToInt32(([ipaddress]$SubnetComponents[0]).GetAddressBytes(), 0)
                    [int] $bitSubnetMaskHostOrder = 0
                    if ($SubnetComponents[1] -gt 0) {
                        $bitSubnetMaskHostOrder = -1 -shl (32 - [int]$SubnetComponents[1])
                    }
                    [int] $bitSubnetMask = [ipaddress]::HostToNetworkOrder($bitSubnetMaskHostOrder)

                    if (($bitIpAddress -band $bitSubnetMask) -eq ($bitSubnetAddress -band $bitSubnetMask)) {
                        if ($ReturnMatchingSubnets) {
                            $listSubnets.Add($Subnet)
                        }
                        else {
                            $Result = $true
                            continue
                        }
                    }
                }

                ## Return list of matches or boolean result
                if ($ReturnMatchingSubnets) {
                    if ($listSubnets.Count -gt 1) { Write-Output $listSubnets.ToArray() -NoEnumerate }
                    elseif ($listSubnets.Count -eq 1) { Write-Output $listSubnets.ToArray() }
                    else {
                        #$Exception = New-Object ArgumentException -ArgumentList ('The IP address {0} does not belong to any of the provided subnets.' -f $IpAddress)
                        #Write-Error -Exception $Exception -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'TestIpAddressInSubnetNoMatch' -TargetObject $IpAddress
                    }
                }
                else {
                    Write-Output $Result
                }
            }
        }
    }

    # [GET EXISTING SUBNETS]
    $ExistingSubnets = (Invoke-RestMethod -Uri $UrlSubnets -Headers $Headers -Method Get).data
    $ProcessedSubnets = @()
    foreach ($Subnet in $ExistingSubnets) {
        $Subnet | Add-Member -MemberType NoteProperty -Name CIDR -Value "$($Subnet.subnet)/$($Subnet.mask)"
        $ProcessedSubnets += $Subnet    
    }
    '';Write-Host "$($ProcessedSubnets.count) subnets addresses found."

    # [GET EXISTING ADDRESSES]
    $ExistingAddresses = (Invoke-RestMethod -Uri $UrlAddresses -Headers $Headers -Method Get).data
    Write-Host "$($ExistingAddresses.count) existing addresses found.";''

    # [ARRAY FOR PROCESSED INPUT]
    $ProcessedInput = @()
}

process {
    # [CREATE ONE COMPLETE ADDRESS PER IP] (if multihomed devices with more than one nic)
    if ($PSObject) {
        $ips = $PSObject.ip -split ";" -split ", "-split "," -split "\s" -split "`t"
        $objects = foreach ($ip in $ips) {
            [PSCustomObject]@{
                hostname    = $PSObject.hostname
                ip          = $ip
                description = $PSObject.description
            }
        }
    }
    else {
        $ips = $ip -split ";" -split ", "-split "," -split "\s" -split "`t"
        $objects = foreach ($ip in $ips) {
            [PSCustomObject]@{
                hostname    = $hostname
                ip          = $ip
                description = $description
            }
        }
    }
    $ProcessedInput += $objects
    Clear-Variable ips, objects
}

end {
    # [SUMMARY AND CONFIRM]
    Write-Host 'Processed input' -ForegroundColor Cyan
    $ProcessedInput | Select-Object ip, hostname, description | Format-Table *
    Start-Sleep -Seconds 1
    Pause

    # [PROCESS INPUT ADDRESSES]
    foreach ($Endpoint in $ProcessedInput) {

        # Get ip, hostname and desc from pipeline/parameters
        $hostname = $Endpoint.hostname
        $ip = $Endpoint.ip
        $description = $Endpoint.description -creplace "(Æ|Å)", 'A' -creplace "(æ|å)", 'a' -creplace "Ø", 'O' -creplace 'ø', 'o'
        if ($description.Length -ge 64) {
            # Description is limited to 64 chars. Truncate if it exceeds 64 in length
            $description = $description.Substring(0, [System.Math]::Min(63, $description.Length))
        }

        # Output input object to console
        Write-Host "$ip - Input: hostname '$hostname', description '$description'"

        # See if the address already exist
        $exsistingAddress = ($ExistingAddresses | Where-Object {$_.ip -eq $ip}) | Select-Object -Last 1

        # If exists, compare values to see if an update is needed
        if ($exsistingAddress) {
            Write-Host "$ip - Already exist: hostname '$($exsistingAddress.hostname)', description '$($exsistingAddress.description)'"

            # If values match, dont update
            if ($hostname -eq $ExsistingAddress.hostname -and $description -cmatch $exsistingAddress.description) {
                Write-Host "$ip - New values match existing values. No need to update"
                if ($Verbose) {
                    "$ip - Hostname compare: old: '$($exsistingAddress.hostname)' | new: '$hostname'"
                    "$ip - Description compare: old: '$($exsistingAddress.description)' | new: '$description'"
                }
            }

            # If values not match, update the address with new hostname and description
            else {
                Write-Host "$ip - New values does not match. Will update hostname to '$hostname' and description to '$description'"
                if ($Verbose) {
                    "$ip - Hostname compare: old: '$($exsistingAddress.hostname)' | new: '$hostname'"
                    "$ip - Description compare: old: '$($exsistingAddress.description)' | new: '$description'"
                }
                try {
                    $Payload  = @{
                        hostname    = [string]$hostname
                        description = [string]$description
                    }
                    $Json = $Payload | ConvertTo-Json -Depth 5 -Compress

                    $UrlAddresses = "$baseUrl/$AppID/addresses/$($ExsistingAddress.id)/"
                    Write-Host $Json

                    Invoke-RestMethod -Uri $UrlAddresses -Method Patch -Headers $Headers -Body $Json -ErrorAction Stop
                    Write-Host "Result - Success" -ForegroundColor Green
                    Clear-Variable Json, Payload
                }
                catch {
                    Write-Host "Result - Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        # if it did not exsist, try to create it
        else {
            # Find the correct subnet that the IP belongs in, and get the id
            $cidr = (Test-IPAddressInSubnet -IpAddresses $ip -Subnets $ProcessedSubnets.CIDR -ReturnMatchingSubnets) | Select-Object -Last 1
            $subnetid = $ProcessedSubnets | Where-Object {$_.CIDR -eq $cidr} | Select-Object -ExpandProperty id
            
            # If a matching subnet was found in IPAM, continue
            if ($subnetid) {
                Write-Host "$ip - Subnet match found: id '$subnetid' and CIDR '$cidr'"

                $Payload  = @{
                    subnetId    = [int]$subnetid
                    ip          = [string]$ip
                    hostname    = [string]$hostname
                    description = [string]$description
                }
                $Json = $Payload | ConvertTo-Json -Depth 5 -Compress
                Clear-Variable Payload

                try {
                    Invoke-RestMethod -Uri $UrlAddresses -Method Post -Headers $Headers -Body $Json -ErrorAction Stop
                    Write-Host "Result - Success" -ForegroundColor Green
                }
                catch {
                    if ($_.Exception.Message -match "Conflict") {
                        Write-Host "Warning - Already exist?" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "Result - Error: $($_.Exception.Message)" -ForegroundColor Red
                        $Json
                    }
                }
                Clear-Variable Json, cidr, subnetId
            }

            # If not matching subnet was found, move on to next address
            else {
                Write-Host "$ip - Subnet match not found" -ForegroundColor Yellow
            }
        }
        Clear-Variable hostname, ip, description, exsistingAddress
    }
}
