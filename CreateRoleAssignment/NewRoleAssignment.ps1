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
    [string]$RITMNumber = $env:RITMnumber,
    [Parameter(Mandatory = $false)]
    [string]$RoleAssignmentFilePath = "./Azure/CreateRoleAssignment/RoleAssignment.json"
)

begin {
    function SendResultToCaller {
        param(
            [Parameter(Mandatory=$True)][string]$bodyData,
            [Parameter(Mandatory=$True)][string]$RITM,
            [Parameter(Mandatory=$True)][string]$url,
            [Parameter(Mandatory=$True)][string]$username,
            [Parameter(Mandatory=$True)][string]$password
        )
        $secpasswdrainier = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($username, $secpasswdrainier)
        
        try {
            $result = Invoke-RestMethod $url -Credential $credential -ContentType "application/json" -Method Put -Body $bodyData
            Write-Host "Successfully updated Msg to Rainier: $($result | ConvertTo-Json)"
        }
        catch {
            throw "Unable to trigger Msg to Rainier URL: $($_)"
        }
    }
}

process {
    try {
        Set-AzContext -SubscriptionId $SubscriptionId
        $scope = "/subscriptions/" + $SubscriptionId
        $userDetails = ConvertFrom-Json $UsersPermissionList
        $userPermissionDetails = $userDetails.data
        $userDetailscount = $userPermissionDetails.Count
        
        if (Test-Path $RoleAssignmentFilePath) {
            $roleMappingJson = Get-Content -Path $RoleAssignmentFilePath -Raw
            $roleMapping = ConvertFrom-Json $roleMappingJson
        } else {
            throw "RoleAssignment.json file not found at path: $RoleAssignmentFilePath"
        }
        
        $allEmailsValid = $true
        [String]$catchedError = $null
        
        for ($i = 0; $i -lt $userDetailscount; $i++) {
            try {
                $userPermissionDetail = $userPermissionDetails.Item($i)
                $emailId = $userPermissionDetail.user
                $requestedRoles = $userPermissionDetail.role                
                
                foreach ($role in $requestedRoles) {
                    $principal = Get-AzADUser -UserPrincipalName $emailId
                    $principalId = $principal.Id
                    $existingRoles = Get-AzRoleAssignment -ObjectId $principalId -ExpandPrincipalGroups | Where-Object {$_.Scope -notlike "$($scope)/*"} | Select-Object -ExpandProperty RoleDefinitionName -Unique
                
                    $currentRoles = @($existingRoles)
                    if ($currentRoles) {
                        Write-Host "`tExisting Roles: $($currentRoles -join ', ')"
                    } else {
                        Write-Host "`tNo existing roles found."
                    }
                    $assignRole = $true
                    foreach ($mapping in $roleMapping.roles) {
                        if ($currentRoles -contains $mapping.current) {
                            if ($mapping.reject -contains $role -or $mapping.reject -eq '*' -and $mapping.accept -notcontains $role){
                                $assignRole = $false
                                $restrictingRole = $mapping.current
                            }
                        }
                    }
                    
                    if ($assignRole) {
                        try {
                            $roleDefinition = Get-AzRoleDefinition -Name $role -ErrorAction Continue
                            if ($null -ne $roleDefinition) {
                                $existingRoleAssignment = Get-AzRoleAssignment -SignInName $emailId -RoleDefinitionName $roleDefinition.Name -Scope $scope | Where-Object {$_.Scope -notlike "$($scope)/*"} -ErrorAction SilentlyContinue
                                if ($null -eq $existingRoleAssignment) {
                                    New-AzRoleAssignment -SignInName $emailId -RoleDefinitionName $roleDefinition.Name -Scope $scope -WarningAction Ignore
                                    #Start-Sleep -Seconds 120
                                    Write-Output "`n$role role successfully assigned for $emailId"
                                } else {
                                    Write-Output "`n$role Role for $emailId already Exists"
                                    Continue
                                }
                            } else {
                                throw "`nGiven Role $role doesn't exist"
                                $_
                                $allEmailsValid = $false
                                Continue
                            }
                        }
                        catch {
                            $catchedError += "$role role for $emailId" + ','
                            Write-Error "`nUnable to assign $role role for $emailId"
                            $_
                            $allEmailsValid = $false
                            Continue
                        }
                    } else {
                        $catchedError += "`nDuplication Role validation Error: $role role for $emailId cannot be assigned as the user is already having $restrictingRole role assigned which is having required permission."
                        
                    }
                }
            }
            catch {
                $log = $_   
                $errormsg = $log.Exception.MESSAGE
                Write-Error $errormsg
            }
        }
        
        if ($catchedError) {
            if ($RITMNumber -ne 'NONE') {
                $body = @{}
                $body.Add("number", $RITMNumber)
                $body.Add("pipelinestatusinfo", "Failure msg: Unable to assign $catchedError. Pipeline status: Failed. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID).`n")
                SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
            }
            Write-Error "Unable to assign $catchedError."
        } else {
            if ($RITMNumber -ne 'NONE') {
                $body = @{}
                $body.Add("number", $RITMNumber)
                $body.Add("pipelinestatusinfo", "Success msg: Roles successfully assigned for UPN users. Pipeline status: Success. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID).`n")
                SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
            }
            Write-Output "`nRoles successfully assigned for UPN users."
        }
    }
    catch {
        $pipelinedetails = "`nPipeline status: Failed. Project name: $($env:SYSTEM_TEAMPROJECT). Pipeline name: $($env:BUILD_DEFINITIONNAME). Build number: $($env:BUILD_BUILDNUMBER). Definition ID: $($env:SYSTEM_DEFINITIONID)."
        $log = $_   
        $errormsg = $log.Exception.MESSAGE
        $errormsg += $pipelinedetails
        if ($RITMNumber -ne 'NONE') {
            $body = @{}
            $body.Add("number", $RITMNumber)
            $body.Add("pipelinestatusinfo", $errormsg)
            SendResultToCaller -bodyData ($body | ConvertTo-Json) -RITM $RITMNumber -url $rainierurl -username $rainierusername -password $rainierpasswords
        }
        Write-Error $errormsg
    }
}

end {
    if ($allEmailsValid -eq $true) {
        Write-Output "`nRole assignments succeeded."
    } else {
        throw "Failure of Role Assignment for the users can be viewed in above logs"
    }
}