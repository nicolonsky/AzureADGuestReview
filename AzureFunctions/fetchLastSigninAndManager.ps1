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
$userId = $Request.body.userId

if ($userId) {
    $body = "Passed user: $userId"
    # Most recent sign-in
    $uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?&`$filter=userId eq '$userId'&?`&`$top=1"

    try {
        $signinsRequest = Invoke-WebRequest -Uri $uri -Headers $authHeader
        $signin = $signinsRequest.Content | ConvertFrom-Json | Select-Object -ExpandProperty value

        if ($null -eq $signin.createdDateTime) {
            $lastSignin = "no recent sign-in"
        }
        else {
            $lastSignin = $signin.createdDateTime
        }
    }
    catch {
        $lastSignin = "no recent sign-in"
    }

    # Get manager
    $uri = "https://graph.microsoft.com/v1.0/users/$userId/manager"
    try {
        $managerInfo = Invoke-WebRequest -Uri $uri -Headers $authHeader
        $managerInfo = $managerInfo.Content | ConvertFrom-Json
        $manager = $managerInfo.mail
    }
    catch {
        $manager = "not available"
    }

    # Get open extension info
    $uri = "https://graph.microsoft.com/v1.0/users/$userId/extensions/ch.nicolonsky.tech.guestManagement"
    try {
        $openExtensionInfo = Invoke-WebRequest -Uri $uri -Headers $authHeader
        $openExtensionInfo = $openExtensionInfo.Content | ConvertFrom-Json
        $lastReview = $openExtensionInfo.lastReview
        $inviterId = $openExtensionInfo.inviterId
        $inviterUpn = $openExtensionInfo.inviterUpn

        if ($null -eq $lastReview) {
            $lastReview = Get-Date -Date "2000-01-01 00:00:00Z"
            $inviterId = "not available"
            $inviterUpn = "not available"
        }

    }
    catch {
        $lastReview = Get-Date -Date "2000-01-01 00:00:00Z"
        $inviterId = "not available"
        $inviterUpn = "not available"
    }

    $body = [PSCustomObject]@{
        managerUpn = $manager
        userId     = $userId
        lastSignIn = $lastSignin
        lastReview = $lastReview
        inviterId  = $inviterId
        inviterUpn = $inviterUpn
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}