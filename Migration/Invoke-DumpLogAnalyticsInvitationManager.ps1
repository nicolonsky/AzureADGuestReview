#Requires -Module Az.OperationalInsights, Az.Accounts, AzureAD

[CmdletBinding(SupportsShouldProcess)]
param (
    # ID of your Log Analytics Workspace
    [Parameter(Mandatory)]
    [guid]
    $WorkspaceID
)

$WorkspaceID = "5b066528-e140-4af9-8aac-405a6718c770"

$query = 
@"
AuditLogs
| where OperationName == 'Invite external user' and Result == 'success'
"@

$queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $query -ErrorAction Stop
$guestInvitations = [System.Linq.Enumerable]::ToArray($queryResults.Results)
$azureADUsers = Get-AzureADUser -All:$true -EA Stop

foreach ($invitation in $guestInvitations){

    try{
        $inviter = $invitation.InitiatedBy | ConvertFrom-Json -EA SilentlyContinue
        $inviterUpn = $inviter.user.userPrincipalName
        $inviterId = $inviter.user.id

        $guest = $invitation.TargetResources | ConvertFrom-Json -EA SilentlyContinue 
    
        if ($null -ne $inviter.user -and $null -ne $guest){
            Write-Output "User '$($inviterUpn)' ($($inviterId)) invited: '$($guest.userPrincipalName)' ($($guest.id))"
    
            if ($azureADUsers.ObjectId -contains $inviterId -and $azureADUsers.ObjectId -contains $guest.id){
                if ($PSCmdlet.ShouldProcess("$($guest.userPrincipalName) ($($guest.id)","Set Azure AD manager '$($inviterUpn)' ($($inviterId))")){
                    Set-AzureADUserManager -ObjectId $guest.id -RefObjectId $inviterId -Verbose
                }
            }else {
                Write-Warning "Either guest or inviter does not exist anymore"
            }
            
        }
    }catch{
        Write-Error $_
    }
}