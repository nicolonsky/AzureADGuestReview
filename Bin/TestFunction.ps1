
$functionUri = ""

$requestBody= @{
    userId = "6cd0a3dd-b8e9-4c95-8289-c78bd234cad7"
}

$webrequestParams = @{
    Uri = $functionUri
    Body = $($requestBody | ConvertTo-Json)
    Method = "Post"
    ContentType = "application/json"
}
$functionRequest = Invoke-WebRequest @webrequestParams
# Parse respone and convert time
$resp = $functionRequest.Content | ConvertFrom-Json
$resp.lastReview = [DateTime]$resp.lastReview

Write-Output $resp