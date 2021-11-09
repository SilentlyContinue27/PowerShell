#####
# GPO Search. Change your domains as neccessary. 
#####

# Run via powershell.
# Or, dot source in another script, and then call the Invoke-GPOSearch function. 

$PathToIcon - "\\somepath\some.ico"
$FirstDomain = "first.root.com"
$FirstDomainCaption = "First"
$SecondDomain = "Second.root.com"
$SecondDomainCaption = "Second"


#####
# Check for elevated console. Restart as admin if not elevated
#####

param([switch]$Elevated)
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if ((Test-Admin) -eq $false) {
    if ($elevated) {
        Write-Host " Failed to run with domain elevated credentials. 
        Abborting script." -ForegroundColor Yellow
        Start-Sleep 5
    } 
    else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
    }

    exit
}






#####
# form for searching GPOs
#####
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

function Invoke-GPOSearch {
    $frmGPOSearch = New-Object system.Windows.Forms.Form
    $frmGPOSearch.ClientSize = '617,230'
    $frmGPOSearch.text = "SVC GPO Search"
    $frmGPOSearch.TopMost = $False
    $frmGPOSearch.ControlBox = $False
    $frmGPOSearch.icon = $PathToIcon


    $lblSearchString = New-Object system.Windows.Forms.Label
    $lblSearchString.text = "Search String:"
    $lblSearchString.AutoSize = $true
    $lblSearchString.width = 25
    $lblSearchString.height = 10
    $lblSearchString.location = New-Object System.Drawing.Point(10, 21)
    $lblSearchString.Font = 'Microsoft Sans Serif,10'

    $txtSearchString = New-Object system.Windows.Forms.TextBox
    $txtSearchString.multiline = $false
    $txtSearchString.width = 504
    $txtSearchString.height = 20
    $txtSearchString.Anchor = 'top,right,left'
    $txtSearchString.location = New-Object System.Drawing.Point(102, 17)
    $txtSearchString.Font = 'Microsoft Sans Serif,10'

    $rdoFirstDomain = New-Object system.Windows.Forms.RadioButton
    $rdoFirstDomain.text = $FirstDomainCaption
    $rdoFirstDomain.AutoSize = $true
    $rdoFirstDomain.width = 104
    $rdoFirstDomain.height = 20
    $rdoFirstDomain.location = New-Object System.Drawing.Point(10, 52)
    $rdoFirstDomain.Font = 'Microsoft Sans Serif,10'
    $rdoFirstDomain.Checked = "True"

    $rdoSecondDomain = New-Object system.Windows.Forms.RadioButton
    $rdoSecondDomain.text = $SecondDomainCaption
    $rdoSecondDomain.AutoSize = $true
    $rdoSecondDomain.width = 104
    $rdoSecondDomain.height = 20
    $rdoSecondDomain.location = New-Object System.Drawing.Point(60, 52)
    $rdoSecondDomain.Font = 'Microsoft Sans Serif,10'

    $btnSearch = New-Object system.Windows.Forms.Button
    $btnSearch.text = "Search"
    $btnSearch.width = 110
    $btnSearch.height = 30
    $btnSearch.location = New-Object System.Drawing.Point(140, 43)
    $btnSearch.Font = 'Microsoft Sans Serif,10'
    $btnSearch.BackColor = "#00408C"
    $btnSearch.ForeColor = "#ffffff"

    $btnExitGPOsearch = New-Object system.Windows.Forms.Button
    $btnExitGPOsearch.text = "Exit"
    $btnExitGPOsearch.width = 98
    $btnExitGPOsearch.height = 30
    $btnExitGPOsearch.Anchor = 'top,right'
    $btnExitGPOsearch.location = New-Object System.Drawing.Point(507, 43)
    $btnExitGPOsearch.Font = 'Microsoft Sans Serif,10'
    $btnExitGPOsearch.ForeColor = "#ffffff"
    $btnExitGPOsearch.BackColor = "#d70000"

    $txtConsole = New-Object system.Windows.Forms.TextBox
    $txtConsole.multiline = $true
    $txtConsole.width = 599
    $txtConsole.height = 140
    $txtConsole.Anchor = 'top,right,bottom,left'
    $txtConsole.location = New-Object System.Drawing.Point(7, 81)
    $txtConsole.Font = 'Microsoft Sans Serif,10'
    $txtConsole.Scrollbars = "Vertical" 

    $frmGPOSearch.controls.AddRange(@($lblSearchString, $txtSearchString, $rdoFirstDomain, $rdoSecondDomain, $btnSearch, $btnExitGPOsearch, $txtConsole))

    $btnSearch.Add_Click( { FindGPOString } )
    $btnExitGPOsearch.Add_Click( { $frmGPOSearch.close() })


    function FindGPOString {
        if ($rdoSecondDomain.Checked -like "True") {
            $Domain = $SecondDomain
            $NearestDC = (Get-ADDomainController -domain $Domain -Discover -NextClosestSite -Service "ADWS").Name + ".$secondDomain" 
        }
        else {
            $Domain = $FirstDomain
            $NearestDC = (Get-ADDomainController -Discover -NextClosestSite).Name

        }
        $GPOs = Get-GPO -All -Domain $Domain -Server $NearestDC | Sort-Object DisplayName
        #Go through each Object and check its XML against $String
        $GPOmatches = @()
        Foreach ($GPO in $GPOs) {
            $txtConsole.Text = "Working on $($GPO.DisplayName)"
            $txtConsole.Text += "`r`n `r`nMatching Group Policy Objects:"
            foreach ($i in $GPOmatches) {
                $txtConsole.Text += "`r`n"
                $txtConsole.Text += "       $i"
            }
        
            #Get Current GPO Report (XML)
            $CurrentGPOReport = Get-GPOReport -Guid $GPO.Id -ReportType Xml -Domain $Domain -Server $NearestDC
            If ($CurrentGPOReport -match $txtSearchString.Text) {
                $GPOmatches += $GPO.DisplayName
            }
        }            

        $txtConsole.Text = "Matching Group Policy Objects:"
        foreach ($i in $GPOmatches) {
            $txtConsole.Text += "`r`n"
            $txtConsole.Text += "       $i"
        }
    }#This end function

    #Start the form
    $txtConsole.Text = " "
    $frmGPOSearch.ShowDialog()



}






# Prevent the console from being hidden if the script is dot sourced.

# If not dot sourced, then hide the underlying console window; the script will close it when exited. 
if ( $MyInvocation.InvocationName -eq '.') { exit }


#Hide PS Window
Enum ShowStates {
    Hide = 0
    Normal = 1
    Minimized = 2
    Maximized = 3
    ShowNoActivateRecentPosition = 4
    Show = 5
    MinimizeActivateNext = 6
    MinimizeNoActivate = 7
    ShowNoActivate = 8
    Restore = 9
    ShowDefault = 10
    ForceMinimize = 11
}
# the C#-style signature of an API function (see also www.pinvoke.net)
$code = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
# add signature as new type to PowerShell (for this session)
$type = Add-Type -MemberDefinition $code -Name myAPI -PassThru
# access a process
# (in this example, we are accessing the current PowerShell host
#  with its process ID being present in $pid, but you can use
#  any process ID instead)
$process = Get-Process -Id $PID
# get the process window handle
$hwnd = $process.MainWindowHandle
# apply a new window size to the handle, i.e. hide the window completely
$type::ShowWindowAsync($hwnd, [ShowStates]::Hide)
# restore the window handle again
#$type::ShowWindowAsync($hwnd, [ShowStates]::Show)






Invoke-GPOSearch

[System.Environment]::Exit(0)