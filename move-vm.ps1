# Script for cross vCenter vMotion.

# Connect to source and destination vCenter instances
#$Cred = Get-Credential
$DestVC = "vc-name"
$SourceVC = "SRC-VCName"
#Connect-VIServer $DestVC -Credential $cred
#Connect-VIServer $SourceVC -Credential $cred

# Variables

$SourceHost = "SRCHost-IPName"
$VM = "VM Name"
$DestHost = "DstHost-IPName"
$destination = Get-VMHost $DestHost
$networkAdapter = Get-NetworkAdapter -VM $vm
$SourceDatastore = Get-VM $VM -Location $SourceHost |Get-Datastore



<# PortGroup migration

The order that the Portgroups are added to this array must match the order of portgroups from the source VM. 
Use the command "Get-NetworkAdapter -VM $vm |FT -Autosize" to display the order of portgroups on the source VM.

#>

$DestinationPortGroup = @()
$DestinationPortGroup += Get-VirtualPortGroup -Name 'dvPortGroup' -VMHost $Desthost
$DestinationPortGroup += Get-VirtualPortGroup -Name 'dvPortGroup' -VMHost $Desthost

#$DestinationPortGroup +=  Get-VDPortGroup -Name 'VM Network' -Server $DestVC
#$DestinationPortGroup +=  Get-VDPortGroup -Name 'VM Network' -Server $DestVC


# use this command if destination network is a standard portgroup
#$DestinationPortGroup += Get-VirtualPortGroup -Name 'VM Network' -VMHost $Desthost

$Destinationdatastore = Get-vmhost $DestHost| Get-datastore 'DatastoreName'

# Command
Get-VM $VM -Location $SourceHost| Move-VM -Destination $destination -NetworkAdapter $networkAdapter -PortGroup $destinationPortGroup -Datastore $Destinationdatastore
