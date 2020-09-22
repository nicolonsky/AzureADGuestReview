using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Acquire Graph Token
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

# Interact with query parameters or the body of the request.
$guest = $Request.body.guestUserId

if ($guest) {
    try {
        # Update Extension Attributes
        $uri = "https://graph.microsoft.com/v1.0/users/$guest/extensions/ch.nicolonsky.tech.guestManagement"
        $requestBody = @{
            inviterId  = $Request.body.inviterId
            inviterUpn = $Request.body.inviterUpn
            lastReview = $Request.body.lastReview
        }
        $null = Invoke-WebRequest -Method Patch -Body $($requestBody | ConvertTo-Json) -Uri $uri -Headers $authHeader
    }
    catch {
        # Populate Extension Attributes
        $uri = "https://graph.microsoft.com/v1.0/users/$guest/extensions"
        $requestBody = @{
            "@odata.type" = "microsoft.graph.openTypeExtension"
            extensionName = "ch.nicolonsky.tech.guestManagement"
            lastReview    = $guestInvitation.TimeGenerated
        }
        $null = Invoke-WebRequest -Method Post -Body $($requestBody | ConvertTo-Json) -Uri $uri -Headers $authHeader
    }
}