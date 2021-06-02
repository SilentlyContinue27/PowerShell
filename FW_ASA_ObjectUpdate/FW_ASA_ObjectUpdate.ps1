 
#################################################################################################
#################################################################################################
# Update Trafic Manager IP Addresses in the ASA   -  V 0.5
# 4/15/2021 - SilentlyContinue TJE
# Requirements: Powershell 5+, .Net 4+, Posh-SSH module, NuGet, elevated PS console                                        
#################################################################################################
#################################################################################################



<# 
Wish list...

Credential management? 
"Install" for creating a scheduled task.
Logging/email.

#>


$Creds = Get-Credential 
$ASAIPAddress = "192.168.1.2"
# Name of the traffic manager object group in the ASA: 
$NetworkGroup = "Outside-Traffic-Mgr-IPs" # 

# Define each URI for each JSON file.
# https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview
# Date stamps and .json are added during the try catch phase.
$jsonFileURLs = @(
    "https://download.microsoft.com/download/7/1/D/71D86715-5596-4529-9B13-DA13A5DE5B63/ServiceTags_Public_"
    "https://download.microsoft.com/download/6/4/D/64DB03BF-895B-4173-A8B1-BA4AD5D4DF22/ServiceTags_AzureGovernment_"
)
# you find those date stamped URLs by digging down through the download links. 
# once the file is actually downloading, grab the url from the 
# "click here if the file does not download automatically" link.






#####
# Check for Posh-SSH module and Admin rights
#####
# Test for admin/elevated PS console: required to install the module and task.  
$currentUser = New-Object Security.Principal.WindowsPrincipal $(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if ( ( $currentUser.IsInRole( [Security.Principal.WindowsBuiltinRole]::Administrator) ) -like $True) {
    # Powershell was run as admin.
    $RunAsAdmin = $True
}
else { $RunAsAdmin = $False }

if ( Get-Module -Name "Posh-SSH") { 
    <# Module is Imported: Continue with the script. #>
}
elseif ( Get-Module -ListAvailable | Where-Object name -Like "Posh-SSH" ) {
    # Module is installed and needs to be imported.
    Import-Module "posh-ssh"
}
else {
    # Module is not installed: See if we can install it.
    if ( $RunAsAdmin -like $True) {
        Write-Host "Installing NuGet package provider and Posh-SSH module. This may take a moment." -ForegroundColor Cyan
        # Powershell was run as admin: Install the module.
        # NuGet is required to install Posh-SSH Module. Install it first.
        # TLS 1.2 is required to install NuGet: This is for this session only and does not change the default.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
        Install-PackageProvider -Name "NuGet" -Force
        Install-Module  "Posh-SSH" -Force
        Import-Module "posh-ssh"
    }
    else { 
        Write-Host "Missing admin/elevated rights to install modules. Please restart powershell as admin. "
        Pause
    }
}

           

       



#####
# Get any new addresses from M$oft #
# M$oft posts new ip addresses on Mondays, but late in the day.
# So run this on a tuesday or wed...
#####
 
# Get Monday Date for URI
$n = 0
do {
    $Monday = (Get-Date -Hour 0 -Minute 0 -Second 0).AddDays(-$n)
    $n++
}
Until ( $Monday.DayOfWeek -eq "Monday" )


$NewTrafficManagerAddresses = @()
foreach ($URL in $jsonFileURLs) {
    # Download the JSON file 
    try {
        $DateParams = @{
            Day    = $Monday.day 
            Year   = $Monday.year 
            Month  = $Monday.month 
            Format = "yyyyMMdd"
        }
        $date = Get-Date  @DateParams
        $URI = $url + $Date + ".json"
        $Json = Invoke-WebRequest -Uri $URI | ConvertFrom-Json
    }
    catch {
        Write-Host "No file at 
        $URI 
        Trying the previous monday instead.
        This might happen if you are trying to download the file early in the day on a monday.
        Try a tuesday or wednesday instead.
        
        Alternativly, M`$oft may have skipped this week.
        "  
        # Remove any previous results.
        if ($json) { Remove-Variable json }
        if ($PastWeek) { Remove-Variable PastWeek }
        # Try untill we get a past file upload; 
        # this ensures that our script will not accidentally remove addresses just because M$oft has not posted new ones.
        do {
            $PastWeek += -7
            $DateParams = @{
                Day    = $Monday.adddays( $PastWeek ).day 
                Year   = $Monday.year 
                Month  = $Monday.month 
                Format = "yyyyMMdd"
            }
            $date = Get-Date  @DateParams
            $URI = $url + $Date + ".json"

            $Json = Invoke-WebRequest -Uri $URI  | ConvertFrom-Json
        } until ($Json)
    }

    $NewTrafficManagerAddresses += $( $json.values |
        Where-Object name -Like "AzureTrafficManager" | 
        Select-Object -ExpandProperty properties | 
        Select-Object -ExpandProperty addressprefixes ).replace("/32", "")  
}
 




#####
# Get the IP addresses currently in the Core FW #
#####
#Build SSH session. 
$Session = New-SSHSession -ComputerName $ASAIPAddress -Credential $creds -AcceptKey 

#Build open stream for use in cisco devices
$stream = $session.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)

# Read the stream to clear it of any login messages. Not needed if you can filter it out later.
# $Stream.Read()

# Run commands. 
# Remember that writes are cap sensitive. 
# Add a new line (actual enter, or `n) after each command, or `n between commands on the same line.
# Add spaces on a new line to skip any MORE stops, just like at a putty terminal.
$stream.Write("show object-group id $NetworkGroup
               ") # See the New Line to send the command, and then the spaces to trigger MORE :)

# Wait a second for the command to process before reading the stream.
Start-Sleep 2

# Filter the results to get only the IP addresses.  
# Reading the stream will clear it; assign it to a variable every time you read it to capture results. 
$AddressesInASA = ( $Stream.Read() ).Split( [Environment]::NewLine ) | 
Where-Object { $PSitem -like " network-object host*" } | 
ForEach-Object { $PSitem.replace( " network-object host ", "" ) }  





#####
# Compare the two sets of IP addresses
#####
$CompareParams = @{
    ReferenceObject  = $NewTrafficManagerAddresses
    DifferenceObject = $AddressesInASA
    IncludeEqual     = $True
}
$Comparison = Compare-Object @CompareParams

$ChangesToMake? = ( $Comparison.sideindicator -contains "<=" ) -or 
( $Comparison.sideindicator -contains "=>" )

if ( $ChangesToMake? ) {
    $Commands = "config terminal
        object-group network $NetworkGroup
        "
    $Comparison | ForEach-Object {
        if ($PSitem.sideindicator -like "<=") {
            # <= is an address in the new traffic manager IP address list that needs to be added to ASA.
            $Commands += "network-object host $($PSitem.inputobject)
            "
        }
        elseif ($PSitem.sideindicator -like "=>") {
            # => is an address in the ASA that is no longer used by Traffic Manager. It can be removed from ASA.
            # Removing the host from the last/all groups will remove it's host object from the firewall.
            # Hosts that are refferenced by other groups will only be removed from This group.
            $Commands += "no network-object host $($PSitem.inputobject)
            "
        }
    }
    $Commands += "Write Mem
    "
    $Stream.write($Commands) 

}


#####
# Cleanup SSH session.
#####
$stream.Write("logout
")
$Stream.close()
$Stream.dispose()
$Session | Remove-SSHSession  


 


