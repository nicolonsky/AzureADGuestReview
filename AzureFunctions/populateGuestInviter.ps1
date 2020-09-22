using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Acquire Graph Token / Get Secrets from Key Vault via MSI
$tenantId = $env:TenantID
$authBody = @{
    client_id     = $env:ApplicationID
    client_secret = $env:ClientSecret
    scope         = "https://graph.microsoft.com/.default"
    grant_type    = "client_credentials"
}

$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$accessToken = Invoke-WebRequest -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $authBody -Method Post -ErrorAction Stop
$accessToken = $accessToken.content | ConvertFrom-Json
$authHeader = @{
    'Content-Type'  = 'application/json'
    'Authorization' = "Bearer " + $accessToken.access_token
    'ExpiresOn'     = $accessToken.expires_in
}

#Take the  information from Azure Common Alert Schema for Log Analytics,
# and get the query results into a format we can actually use
$columns = $Request.body.data.alertContext.SearchResults.tables.columns.name
$rows = $Request.body.data.alertContext.SearchResults.tables.rows

#Set name-value pairs for each Search Result
$arr = @()

if ($Request.body.data.alertContext.ResultCount -eq 1) {
    $hash = @{}
    for ($i = 0; $i -lt $columns.count; $i++) {
        $hash.Add($columns[$i], $rows[$i])
    }
    $arr += $hash
}
else {
    $rows | ForEach-Object {
        $hash = @{}
        for ($i = 0; $i -lt $columns.count; $i++) {
            $hash.Add($columns[$i], $_[$i])
        }
        $arr += $hash
    }
}

foreach ($guestInvitation in $arr) {
    try {
        # Deserialize JSON content of common alert scheme
        $initiatedBy = $guestInvitation.InitiatedBy | ConvertFrom-Json
        $targetResources = $guestInvitation.TargetResources | ConvertFrom-Json

        Write-Host "User: $($targetResources[0].userPrincipalName) was invited by $($initiatedBy.user.userPrincipalName)"

        # Populate Manager
        $guest = $targetResources[0].id
        $inviter = $initiatedBy.user.id
        $uri = "https://graph.microsoft.com/v1.0/users/$guest/manager/`$ref"
        $requestBody = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/users/$inviter"
        }
        $null = Invoke-WebRequest -Method Put -Body $($requestBody | ConvertTo-Json) -Uri $uri -Headers $authHeader

        # Populate Extension Attributes
        $uri = "https://graph.microsoft.com/v1.0/users/$guest/extensions"
        $requestBody = @{
            "@odata.type" = "microsoft.graph.openTypeExtension"
            extensionName = "ch.nicolonsky.tech.guestManagement"
            inviterId     = $initiatedBy.user.id
            inviterUpn    = $initiatedBy.user.userPrincipalName
            lastReview    = $guestInvitation.TimeGenerated
        }
        $null = Invoke-WebRequest -Method Post -Body $($requestBody | ConvertTo-Json) -Uri $uri -Headers $authHeader

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = "Successfuly updated guest '$($guest)'"
            })

        Push-OutputBinding -Name outputBlob -Value $($Request.body | ConvertTo-Json -Depth 99)

    }
    catch {
        Write-Error $_
    }
}