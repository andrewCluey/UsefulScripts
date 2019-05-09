# Connection details 

# Check connection to main vCenter
$vCenter = "192.168.10.45"
$vcCred = get-credential -Message "Enter credentials to connect to $vCenter"
if ($DefaultVIServers.Name -ne $vCenter) {
    write-host -ForegroundColor DarkYellow "not connected to correct vCenter"
    VIServer = Connect-VIServer $vCenter -Credential $vcCred  | Out-Null
    }
else {
    write-host -ForegroundColor DarkYellow "Already connected to $vCenter"
    }

# Guest details
$guestCred = get-credential -Message "Enter credentials for guest VM"
$TestVM = "win-net-test"

# MAIN testing Section
# csv file should contain the portgroup and guest IP mappings. 
# Git repository contains an example file, modify to reflect your environment.
$nettests = Import-csv .\VM-Net-Test.csv
$testHost = "hostToTestIP"                                      # Enter the IP of the Host to test

# Construct log file for results ($DATE$UPLINK_VH$TESTHOST.log)
$date = (Get-Date).tostring(“yyyyMMdd_hhmm”)
$path = "E:\temp\Net-test\"                                     # Location where result log file should be saved.
$Uplink = "Uplink1"                                             # Which uplink is being tested.
$fileSuffix = $testhost.substring(10)
$logFile = ($path + $date + $uplink + "_VH-"+ $fileSuffix)

# run network tests
foreach ($netTest in $netTests) {
    $pingCommand = "Test-NetConnection $($nettest.pingIP) -InformationLevel Quiet"
    # Configure Guest network connection (dvPortgroup)
    $dvPortgroup = Get-VDPortgroup -Name $netTest.portgroup
    Get-VM $TestVM |Get-NetworkAdapter |Set-NetworkAdapter -Portgroup $dvPortgroup -Confirm:$false
    
    # Set  guest IP (invoke-script )
    $code = "Get-NetAdapter | new-NetIPAddress -IPAddress $($netTest.testSrcIP) -PrefixLength 24 -DefaultGateway $($netTest.gw)"
    Invoke-VMScript –VM $testVM -GuestCredential $cred -ScriptType Powershell -ScriptText $code
   
    # Run tests
    $result = Invoke-VMScript -VM $testVM -ScriptText $pingCommand -GuestCredential $cred
    $output = "Test of $($netTest.portgroup) Source IP of $($netTest.testSrcIP) to $($nettest.pingIP) = $result"
    $output |out-file -Append "$logFile.log"
    $resetIP = "Remove-netIPAddress -IPAddress $($netTest.testSrcIP) -DefaultGateway $($netTest.gw) -Confirm:`$false"
    Invoke-VMScript –VM $testVM -GuestCredential $cred -ScriptType Powershell -ScriptText $resetIP
    }
