# Connect to source and destination vCenter instances
$Cred = Get-Credential
$DestVC = "VCName"
Connect-VIServer $DestVC -Credential $cred

$cluster = Get-cluster "CLUSTERName"

$ESXiHosts = $Cluster | Get-VMHost
foreach ($ESXi in $ESXiHosts)
{
Get-VMhost ESXiHostIPName | Get-ScsiLun | Where-Object {$_.MultipathPolicy -like ‘RoundRobin’} | Set-ScsiLun -CommandsToSwitchPath 1
}