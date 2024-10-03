##Purpose
This script will Delete the specified Role Assignment for a user in the given Subscription.

##Implementation
deleteUserRoles.ps1 script takes SubscriptionId, JSON format input including User and Permission list Format Ex-{'data':[{'user':'firstname.lastname@wolterskluwer.com','role':['PermissionName1','PermissionName2']}]} user here is User Pricipal Name(UPN) and role includes list of roles separated by comma, apart from Rainier intergration parameters.

##Input Parameters
SubscriptionId - The Azure subscription ID. 
User and Permission List in JSON format - The WK User principal name(emailId) and Permission is user roles/permission separated by comma.

##Output
The status of the script will be displayed on pipeline logs.

##Link to User Story
https://wkenterprise.atlassian.net/browse/GES-1471

##Pipeline
Dev: https://wkrainier.visualstudio.com/WKServices/_build?definitionId=3490&_a=summary