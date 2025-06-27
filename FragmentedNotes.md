#ALLOW SELF SIGNED CERTS (TRUST ALL)
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


#VLAN CREATE NOTES
$AppID = "100"
$UrlVlans = "https://ipam.domain.com/api/$AppID/vlans/"
foreach ($Vlan in $VlansToBeCreated) {
    Write-Host "Create - vlan with id '$($_.VID)' and name '$($_.Sone)'"
    
    $Payload  = @{    
      domainId    = $domainId
      name        = $Vlan.Sone
      number      = $Vlan.VID
    }
    $Data = $Payload | ConvertTo-Json -Depth 5 -Compress        
    try {
      Invoke-RestMethod -Uri $UrlVlans -Method Post -Headers $headers -Body $Data -ErrorAction Stop
      Write-Host "Result - Success" -ForegroundColor Green
    }
    catch {
      Write-Host "Result - Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

#GET ALL ENDPOINTS AND SUBNETS FROM ALL AZURE SUBSCRIPTIONS IN A TENANT
# Start cloudshell in Azure Portal
$allEndpoints = @()
$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    $vnets = Get-AzVirtualNetwork
    foreach ($vnet in $vnets) {
        foreach ($subnet in $vnet.Subnets) {
            # Join address prefix(es) into a string
            $subnetAddress = ($subnet.AddressPrefix -join ", ")

            # Get all NICs in this subscription that are connected to this subnet
            $nics = Get-AzNetworkInterface | Where-Object {
                $_.IpConfigurations.Subnet.Id -eq $subnet.Id
            }

            foreach ($nic in $nics) {
                foreach ($ipConfig in $nic.IpConfigurations) {
                    $obj = [PSCustomObject]@{
                        Subscription      = $sub.Name
                        ResourceGroup     = $nic.ResourceGroupName
                        VNet              = $vnet.Name
                        Subnet            = $subnet.Name
                        SubnetAddress     = $subnetAddress
                        NICName           = $nic.Name
                        PrivateIPAddress  = $ipConfig.PrivateIpAddress
                    }
                    $allEndpoints += $obj
                }
            }
        }
    }
}
$allEndpoints
$allEndpoints | Export-Csv -Path "nic-endpoints.csv" -NoTypeInformation    #Then Download the file "nic-endpoints.csv" and use output to create subnets and addresses i phpIPAM


#SUBNET CREATE NOTES
$AppID = "100"
$UrlVlans = "https://ipam.domain.com/api/$AppID/subnets/"
foreach ($Subnet in $SubnetsToBeCreated) {      
  $description = $Subnet.description
  $cidr = $Subnet.cidr
  $ip = ($cidr -split '/')[0]
  $mask = ($cidr -split '/')[1]

  Write-Host "Create - $cidr with description '$description' in master subnet '$masterSubnetId', section '$sectionId'"
  
  $vlanid = #Must be provided. I used a lookuptable
  $IDOfVlan = #Then find id of vlan by querying existing vlans

  $Payload  = @{    
    subnet         = $ip
    mask           = $mask
    vlanId         = $IDOfVlan.id
    masterSubnetId = $masterSubnetId
    sectionId      = $sectionId
    description    = ($Subnet.Sone).ToLower()
  }
  $Data = $Payload | ConvertTo-Json -Depth 5 -Compress  
  try {
    Invoke-RestMethod -Uri $UrlSubnets -Method Post -Headers $headers -Body $Data -ErrorAction Stop
    Write-Host "Result - Success" -ForegroundColor Green
  }
  catch {
    if ($_.Exception.Message -match "(Subnet overlaps with|Conflict)") {
      Write-Host "Warning - Already exist?" -ForegroundColor Yellow
    }
    else {
      Write-Host "Result - Error: $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}
