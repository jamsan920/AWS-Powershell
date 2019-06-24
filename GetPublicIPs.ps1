# Description:
# This script retrieves all elastic IPs and dynamically assigned public IPs from all AWS regions, utilizing existing credentials files
#
# Last updated: 2019.06.24
# Version: 0.1
# Requirements: AWS Tools for Windows Powershell; Existing AWS credentials stored in the default location

############################################################################################################################################################
# Optional Parameters
# PublicIP: Enter in a public IP if you want to filter on a singular IP and not have to wade through the entire list (e.g. 10.10.10.10 or partial, 10.10. )
#
# Regions: Enter in a region (single region or comma separated list) to only search in specific regions instead of all (e.g. us-east-1,us-west-1 )
#
# Accounts: Enter in a profile name (single name or comma separated list) to only search using specific credential named profiles (e.g. profile1,profile2 )
############################################################################################################################################################



param
(
    $PublicIP = '',
    $Regions = '',
    $Accounts = ''
)

# Get list of available credentials in the .aws credentials file - prefer input of $Accounts if input is provided
if ($Accounts -ne '')
{ $cred_list = Get-AWSCredential -ListProfileDetail | select ProfileName | Where-Object {$_.ProfileName -in $Accounts } }

else
{ $cred_list = Get-AWSCredential -ListProfileDetail | select ProfileName }


# Array to hold the final list of IPs and their attributes
$EIPDetailsList = New-Object System.Collections.ArrayList


# First loop through all the available credentials
foreach ($cred in $cred_list)
{

    # Get a list of all the available AWS regions to loop through - prefer input of $Regions if input is provided
    if ($Regions -ne '')
    { $region_list = Get-AWSRegion | select Region, Name | Where-Object {$_.Region -in $Regions } }

    else
    { $region_list = Get-AWSRegion | select Region, Name }


    # secondary inner loop to loop through all the regions, working injunction with the outer loop to also get all regions for each set of credentials (accounts)
    foreach ($region in $region_list)
    {
        "Checking: " + $cred.ProfileName + " / " + $region.Name

        try {

        # Use Get-EC2Instance to find a listing of all the dynamically assigned Public IPs currently use on individual EC2 instances
            #loop through the results and place them into the EIPDetailsList array
        $instances = (Get-EC2Instance -Region $region.Region -ProfileName $cred.ProfileName).Instances | Where-Object {$_.PublicIpAddress -ne $null}

        foreach ($instance in $instances) {
            $ElasticIP = [pscustomobject] @{
                "Region"            = $region.Name
                "Account"           = $cred.ProfileName
                "Name"              = $instance.Tags | Where-Object {$_.key -eq "Name"} | Select-Object -Expand Value
                "IP"                = $instance.PublicIpAddress
                "Assigned to"       = $instance.InstanceId
                "Network Interface" = $instance.NetworkInterfaceId

            }
            [void]$EIPDetailsList.Add($ElasticIP)
        }

        
        # Use Get-EC2Address to find a listing of all the elastic IPs currently use on the account, loop through the results and place them into the EIPDetailsList array        
        $EIPs = Get-EC2Address -Region $region.Region -ProfileName $cred.ProfileName

        foreach ($eip in $EIPs) {
            # Filter out any elastic IPs that were already assigned to an EC2 instance
            if ($eip.PublicIp -notin $EIPDetailsList.IP)
            {
            $ElasticIP = [pscustomobject] @{
                "Region"            = $region.Name
                "Account"           = $cred.ProfileName
                "Name"              = $eip.Tags | Where-Object {$_.key -eq "Name"} | Select-Object -Expand Value
                "IP"                = $eip.PublicIp
                "Assigned to"       = $eip.InstanceId
                "Network Interface" = $eip.NetworkInterfaceId
                }
                            
            [void]$EIPDetailsList.Add($ElasticIP)
            }
        }        
    }

    # In case there's any errors in a particular account / region with permissions (usually a problem with Hong Kong if it's not in use by the account)
    #catch { Write-Error $_  }
    catch {"Error Checking: " + $cred.ProfileName + " / " + $region.Name + ". Please ensure you have appropriate permissions to run Get-EC2Address and Get-EC2Instance"}
    }
}

# Output the final list - if a Public IP was specified, filter based on that using a wildcard
$EIPDetailsList | Where-Object {$_.IP -like "*$PublicIP*"} | Format-Table

