# win storage

#Additional use commands
Get-PhysicalDisk | Where CanPool -Eq True | Select UniqueId, MediaType, Size


#Set 2 * 10GB SSD
Set-PhysicalDisk -UniqueId <drive-id> -MediaType SSD

#Set 2 * 20GB HDD
Set-PhysicalDisk -UniqueId <drive-id> -MediaType HDD