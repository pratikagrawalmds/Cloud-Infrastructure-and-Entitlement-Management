[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = $env:SubscriptionID,
    [Parameter(Mandatory = $false)]
    [string]$UsersPermissionList = $env:UsersPermissionList,
    [Parameter(Mandatory = $false)]
    [string]$rainierurl = $env:URL,
    [Parameter(Mandatory = $false)]
    [string]$rainierusername = $env:rainierusername,
    [Parameter(Mandatory = $false)]
    [string]$rainierpasswords = $env:rainierpasswords,
    [Parameter(Mandatory = $false)]
    [string]$RITMNumber = $env:RITMnumber
)
begin {
    # Send Error Logs to Rainier url stored in Pipeline Variables
    function SendResultToCaller{
    param(
    [Parameter(Mandatory=$True)][string]$bodyData,
    [Parameter(Mandatory=$True)][string]$RITM,
    [Parameter(Mandatory=$True)][string]$url,
    [Parameter(Mandatory=$True)][string]$username,
    [Parameter(Mandatory=$True)][string]$password
    )
        $secpasswdrainier = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($username, $secpasswdrainier)
        
        try{
            $result = Invoke-RestMethod $url -Credential $credential -ContentType "application/json" -Method Put -Body $bodyData
            Write-Host "Successfully updated Msg to Rainier : $($result | ConvertTo-Json)"
        }
        catch{
            throw "Unable to trigger Msg to Rainier URL: $($_)"
        }
    }
   
}
process {
    try {
        Set-AzContext -SubscriptionId $SubscriptionId
$scope = "/subscriptions/" + $SubscriptionId
# Converting from JSON data 
$userDetails = ConvertFrom-Json $UsersPermissionList
$userPermissionDetails = $userDetails.data
$userDetailscount = $userPermissionDetails.Count
$allEmailsValid = $true
[String]$catchedError = $null
 
for ($i = 0; $i -lt $userDetailscount; $i++) {
    try {
        $userPermissionDetail = $userPermissionDetails.Item($i)
        $emailId = $userPermissionDetail.user
        $roles = $userPermissionDetail.role
        $userRoles=Get-AzRoleAssignment -SignInName $emailId -ErrorAction SilentlyContinue
                if($userRoles -eq $null){
        
         $catchedError +="`nRole Assignment for user '$emailId' does not exists in current subscription"
         Write-Output "Role Assignment for user '$emailId' does not exists in current subscription"
        
        }
        else{           
        foreach ($role in $roles) {
            try {
               
                     $role=$role.Trim()
                    # Check if the email exists in the scope before attempting to remove the role
                    $existingRoleAssigment = Get-AzRoleAssignment -SignInName $emailId -RoleDefinitionName $role -Scope $scope -ErrorAction SilentlyContinue
                    if ($null -eq $existingRoleAssigment) {

                $catchedError=$catchedError+"`n"+"'$role' role is not assigned to '$emailId' User. Please verify whether role is misspelled or assigned to '$emailId' User."
                Write-Host "'$role' role is not assigned to '$emailId' User. Please verify whether role is misspelled or assigned to '$emailId' User."
                    }
                    else {
                        # Delete role from user
                        Remove-AzRoleAssignment -SignInName $emailId -RoleDefinitionName $role -Scope $scope -WarningAction Ignore
                        Write-Output "`n$role role successfully deleted for $emailId"
                    }               
            }
            catch {
                $catchedError = $catchedError + "$role role for $emailId " + ','
                Write-Error "`nUnable to delete $role role for $emailId"
                $_
                $allEmailsValid = $false
            }
        }
        }
    }
    catch {
        $log = $_   
        $errormsg = $log.Exception.MESSAGE
        Write-Error $errormsg
        # Continue
    }
}

        if($catchedError){
                if($RITMNumber -ne 'NONE'){
                    $body = @{}
                    $body.Add("number", $RITMNumber)
                    $body.Add("pipelinestatusinfo", "Failure msg : $catchedError. "+" Pipeline status: Failed. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID).`n")
                    SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
                }
        
            Write-Error $catchedError
            }
            else{
                if($RITMNumber -ne 'NONE'){
                    $body = @{}
                    $body.Add("number", $RITMNumber)                    
                    $body.Add("pipelinestatusinfo", "Success msg : Roles successfully deleted for UPN users."+" Pipeline status: Success. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID).`n")
                    SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
                }
            Write-Output "`nRoles successfully deleted for users."     
            }
    }
    catch {
        $pipelinedetails = "`n Pipeline status: Failed. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID)."
        $log = $_   
        $errormsg = $log.Exception.MESSAGE
        $errormsg += $pipelinedetails
    
    if($errormsg -notmatch "Please verify whether role is misspelled" -and $errormsg -notmatch "does not exists in current subscription")
        {
             if($RITMNumber -ne 'NONE'){
                $body = @{}
                $body.Add("number", $RITMNumber)
                $body.Add("pipelinestatusinfo",$errormsg)
                SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
           }
            Write-Error $errormsg
        }   
    else{
        Write-Error $catchedError
    }   
    }
}
