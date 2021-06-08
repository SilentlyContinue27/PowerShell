

####################
#### This First Code Block Generates a CSV Of Users either for review or Input to the next Block.
#####################
$Days = 180
<#Note that PasswordLastSet is on an 11 day delayed replication. Should not matter when working in months…#>
$Date = (Get-Date).AddDays(-$Days)
$PathToCSV = "C:\Power\PWNotSetInDays$days.csv"


'OU=Departments,DC=dom,DC=dom,DC=edu', 
'OU=Employees,DC=dom,DC=dom,DC=edu' | ForEach-Object {
    (Get-ADUser -Filter { (passwordlastset -le $Date) -and (enabled -eq 'True') -and (emailaddress -like '*@*') 
            -and (name -notlike '*toexcludestring*') -and (name -notlike '*office*') -and (name -notlike '*admin*') } `
            -SearchBase $_ -Properties PasswordLastSet | Select-Object Name, SamAccountName, PasswordLastSet) 
} |  Export-Csv $PathToCSV  -Delimiter "," -NoTypeInformation
    


#####################
#### Get the outputed CSV from the above block as input for which accounts to deactivate/randomizePW.
#####################
$csv = Import-Csv -Path $PathToCSV #CHECK $Date/$PathToCSV SET CORRECTLY ABOVE!!!
$TodaysDate = Get-Date -Format MM/dd/yyyy
ForEach ($account in $csv) { 
    $UserUPN = $($account.SamAccountName + "@skagit.edu")
    $user = Get-ADUser -Filter { userprincipalname -like $UserUPN } -Properties Description
    $SecurePass = $((([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..12 | 
                Sort-Object { Get-Random })[0..12] -join '') | ConvertTo-SecureString -AsPlainText -Force)
    Set-ADAccountPassword $user -NewPassword $SecurePass -Reset
    $Description = "Disabled on " + $TodaysDate + " - " + $User.Description
    Set-ADUser -Identity $user -Description $Description
    $user | Disable-ADAccount
}




