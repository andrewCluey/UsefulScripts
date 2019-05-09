param(
   [Parameter(Mandatory=$True)]
   [String]$vmName,
   [Parameter(Mandatory=$True)]
   [String]$vcenterServer,
   [Parameter(Mandatory=$True)]
   [String]$username,
   [Parameter(Mandatory=$True)]
   [String]$password,
   [Parameter(Mandatory=$True)]
   [String]$vmTemplate,
   [Parameter(Mandatory=$False)]
   [String]$StorageTier,
   [Parameter(Mandatory=$True)]
   [String]$vCPU,
   [Parameter(Mandatory=$True)]
   [String]$MemGB,
   [Parameter(Mandatory=$True)]
   [String]$portgroup,
   [Parameter(Mandatory=$True)]
   [String]$guestIP,
   [Parameter(Mandatory=$True)]
   [String]$guestMask,
   [Parameter(Mandatory=$True)]
   [String]$guestGW,
   [Parameter(Mandatory=$True)]
   [String]$guestDNS
)

Set-PowerCLIConfiguration -InvalidCertificateAction ignore -Confirm:$false
$secPasswd = ConvertTo-SecureString $password -AsPlainText -Force
$vcCredential = New-Object System.Management.Automation.PSCredential ($username, $secpasswd)
Connect-VIServer $vcenterServer -Credential $vcCredential | Out-Null

# SUGGESTION for next version!!! Use tags and filters to get the correct cust spec. Not hardcoded
Get-OSCustomizationSpec -Type NonPersistent | Remove-OSCustomizationSpec -Confirm:$false
$Spec = Get-OSCustomizationSpec 'Win2k12R2OSSpec' |  New-OSCustomizationSpec -Name 'PRSpec' -Type NonPersistent
$Spec = Get-OSCustomizationNicMapping -Spec 'PRSpec' | Set-OSCustomizationNicMapping -IPmode UseStaticIP -IpAddress $guestIP -SubnetMask $guestMask -DefaultGateway $guestGW -DNS $guestDNS
$osCust = Get-OSCustomizationSpec -Name 'PRSpec'

# SUGGESTION for future version!!! Add Run-Once script for different server types? Or use a standard for RUNONCE for ALL (Enable WINRM Remote for Ansible config; --> Anti-Virus; Security configuration & lockdowns)


# Select Datastore. New filter based on Datastore type selected in drop down (T2-Standard, T1-SSD etc)
# New section to select Datastore based on requested performance Tier (Param) or DS with most freespace
<#

$initialHost = "hostIP"                               # IP Address/Hostname of the host where initial deployment should be made.
if ($StorageTier -eq "T2-Standard") {
   $datastore = "BL-T2-OS-CLU-01"
}
else {
   $SharedDS = get-datastore |where {$_.Name -like "GPS-BL*"}| Sort-Object -Property FreeSpaceGB -Descending:$true
   $datastore=$SharedDS[0]
}
#>

# Clone the VM Template to create new VM
$cloneTask = New-VM -template $vmTEMPLATE -MemoryGB $memGB -NumCpu $vCPU -vmhost $initialHost -name $vmName -runasync -Datastore $Datastore -OSCustomizationSpec $osCust
Get-Task -Id $cloneTask.ID | Wait-Task




# Connect and assign network name. Currently only works for VMs with 1 NIC. Future change will allow for setting PG on multiple NICs.
Get-VM $VMname | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -StartConnected:$true -portgroup $portgroup -Confirm:$false

# Power on the new VM
start-vm $vmname | wait-tools


##### Wait for the VM to be powered on #####
Start-Sleep 20
$vm = Get-VM -Name $vmname
While ($vm.ExtensionData.Runtime.PowerState -ne 'poweredOn')
{
    Start-Sleep -Seconds 3
    $vm.ExtensionData.UpdateViewData('Runtime.PowerState')
}



function WaitVM-Customization {
 
[CmdletBinding()] 
param( 
   # VMs to monitor for OS customization completion 
   [Parameter(Mandatory=$true)] 
   [ValidateNotNullOrEmpty()] 
   [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine[]] $vm, 
   
   # timeout in seconds to wait 
   [int] $timeoutSeconds = 600 
)

<#

.SYNOPSIS 
Waits for customization process to complete.

.DESCRIPTION 
The script returns if customization process ends for all virtual machines or if the specified timeout elapses. 
The script returns PSObject for each specified VM. 
The output object has VM and CustomizationStatus properties.

.EXAMPLE 
$vm = 1..10 | foreach { New-VM -Template Windows2016Template -OSCustomizationSpec standardWin2016Customizaion -Name "server-$_" } 
.\WaitVmCustomization.ps1 -vmList $vm -timeoutSeconds 600

.NOTES 
The script is based on several vCenter events. 
* VmStarting event - this event is posted on power on operation 
* CustomizationStartedEvent event - this event is posted for VM when customiztion has started 
* CustomizationSucceeded event - this event is posted for VM when customization has successfully completed 
* CustomizationFailed - this event is posted for VM when customization has failed

Possible CustomizationStatus values are: 
* "VmNotStarted" - if it was not found VmStarting event for specific VM. 
* "CustomizationNotStarted" - if it was not found CustomizationStarterdEvent for specific VM. 
* "CustomizationStarted" - CustomizationStartedEvent was found, but Succeeded or Failed event were not found 
* "CustomizationSucceeded" - CustomizationSucceeded event was found for this VM 
* "CustomizationFailed" - CustomizationFailed event wass found for this VM

#>

# constants for status 
      $STATUS_VM_NOT_STARTED = "VmNotStarted" 
      $STATUS_CUSTOMIZATION_NOT_STARTED = "CustomizationNotStarted" 
      $STATUS_STARTED = "CustomizationStarted" 
      $STATUS_SUCCEEDED = "CustomizationSucceeded" 
      $STATUS_FAILED = "CustomizationFailed" 
      
      $STATUS_NOT_COMPLETED_LIST = @( $STATUS_CUSTOMIZATION_NOT_STARTED, $STATUS_STARTED ) 
      
# constants for event types      
      $EVENT_TYPE_CUSTOMIZATION_STARTED = "VMware.Vim.CustomizationStartedEvent" 
      $EVENT_TYPE_CUSTOMIZATION_SUCCEEDED = "VMware.Vim.CustomizationSucceeded" 
      $EVENT_TYPE_CUSTOMIZATION_FAILED = "VMware.Vim.CustomizationFailed" 
      $EVENT_TYPE_VM_START = "VMware.Vim.VmStartingEvent"

# seconds to sleep before next loop iteration 
      $WAIT_INTERVAL_SECONDS = 15 
      
function main($vm, $timeoutSeconds) { 
   # the moment in which the script has started 
   # the maximum time to wait is measured from this moment 
   $startTime = Get-Date 
   
   # we will check for "start vm" events 5 minutes before current moment 
   $startTimeEventFilter = $startTime.AddMinutes(-5) 
   
   # initializing list of helper objects 
   # each object holds VM, customization status and the last VmStarting event 
   $vmDescriptors = New-Object System.Collections.ArrayList 
   foreach($vm in $vm) { 
      Write-Host "Start monitoring customization process for vm '$vm'" 
      $obj = "" | select VM,CustomizationStatus,StartVMEvent 
      $obj.VM = $vm 
      # getting all events for the $vm, 
      #  filter them by type, 
      #  sort them by CreatedTime, 
      #  get the last one 
      $obj.StartVMEvent = Get-VIEvent -Entity $vm -Start $startTimeEventFilter | ` 
         where { $_ -is $EVENT_TYPE_VM_START } | 
         Sort CreatedTime | 
         Select -Last 1 
         
      if (-not $obj.StartVMEvent) { 
         $obj.CustomizationStatus = $STATUS_VM_NOT_STARTED 
      } else { 
         $obj.CustomizationStatus = $STATUS_CUSTOMIZATION_NOT_STARTED 
      } 
      
      [void]($vmDescriptors.Add($obj)) 
   }         
   
   # declaring script block which will evaulate whether 
   # to continue waiting for customization status update 
   $shouldContinue = { 
      # is there more virtual machines to wait for customization status update 
      # we should wait for VMs with status $STATUS_STARTED or $STATUS_CUSTOMIZATION_NOT_STARTED 
      $notCompletedVms = $vmDescriptors | ` 
         where { $STATUS_NOT_COMPLETED_LIST -contains $_.CustomizationStatus }

      # evaulating the time that has elapsed since the script is running 
      $currentTime = Get-Date 
      $timeElapsed = $currentTime - $startTime 
      
      $timoutNotElapsed = ($timeElapsed.TotalSeconds -lt $timeoutSeconds) 
      
      # returns $true if there are more virtual machines to monitor 
      # and the timeout is not elapsed 
      return ( ($notCompletedVms -ne $null) -and ($timoutNotElapsed) ) 
   } 
      
   while (& $shouldContinue) { 
      foreach ($vmItem in $vmDescriptors) { 
         $vmName = $vmItem.VM.Name 
         switch ($vmItem.CustomizationStatus) { 
            $STATUS_CUSTOMIZATION_NOT_STARTED { 
               # we should check for customization started event 
               $vmEvents = Get-VIEvent -Entity $vmItem.VM -Start $vmItem.StartVMEvent.CreatedTime 
               $startEvent = $vmEvents | where { $_ -is $EVENT_TYPE_CUSTOMIZATION_STARTED } 
               if ($startEvent) { 
                  $vmItem.CustomizationStatus = $STATUS_STARTED 
                  Write-Host "VI Event Generated - Customization for VM '$vmName' has started" -ForegroundColor Yellow -BackgroundColor Black
               } 
               break; 
            } 
            $STATUS_STARTED { 
               # we should check for customization succeeded or failed event 
               $vmEvents = Get-VIEvent -Entity $vmItem.VM -Start $vmItem.StartVMEvent.CreatedTime 
               $succeedEvent = $vmEvents | where { $_ -is $EVENT_TYPE_CUSTOMIZATION_SUCCEEDED } 
               $failedEvent = $vmEvents | where { $_ -is $EVENT_TYPE_CUSTOMIZATION_FAILED } 
               if ($succeedEvent) { 
                  $vmItem.CustomizationStatus = $STATUS_SUCCEEDED 
                  Write-Host "VI Event Generated - Customization for VM '$vmName' has successfully completed" -ForegroundColor Green -BackgroundColor Black
               } 
               if ($failedEvent) { 
                  $vmItem.CustomizationStatus = $STATUS_FAILED 
                  Write-Host "Customization for VM '$vmName' has failed" 
               } 
               break; 
            } 
            default { 
               # in all other cases there is nothing to do 
               #    $STATUS_VM_NOT_STARTED -> if VM is not started, there's no point to look for customization events 
               #    $STATUS_SUCCEEDED -> customization is already succeeded 
               #    $STATUS_FAILED -> customization 
               break; 
            } 
         } # enf of switch 
      } # end of the freach loop 
      
      Write-Host "Awaiting OS Customization VI Event, Sleeping for $WAIT_INTERVAL_SECONDS seconds" -BackgroundColor Black
            
      Sleep $WAIT_INTERVAL_SECONDS 
   } # end of while loop 
   
   # preparing result, without the helper column StartVMEvent 
   $result = $vmDescriptors | select VM,CustomizationStatus 
   return $result 
}

main $vm $timeoutSeconds

}

WaitVM-Customization -vm $vm
