$VMs = Get-VM VMName
foreach ($VM in $VMs){
    $VMx = Get-View $VM.ID
     $HW = $VMx.guest.net
     foreach ($dev in $HW)
    {
        foreach ($ip in $dev.ipaddress)
        {
            $dev | select
            @{Name = "Name"; Expression = {$vm.name}},
            @{Name = "IP"; Expression = {$ip}},
            @{Name = "MAC"; Expression = {$dev.macaddress}}  |
            Export-CSV VM-IP-Info.csv -NoTypeInfo
           
 
        }
    }
}