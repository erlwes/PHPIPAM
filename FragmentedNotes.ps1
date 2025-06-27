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
