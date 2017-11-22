$Cred = Get-Credential

Copy-VMGuestFile -Source "PathToFile" -Destination "PathToDestination" -VM "VMName" -localtoGuest -Guestcredential $CRed