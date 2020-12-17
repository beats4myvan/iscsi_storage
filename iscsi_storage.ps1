# Clone an existing virtual hard disk
cp 'C:\BAK\WIN-SRV-2K19-ST\VHD\WIN-SRV-2K19-ST.vhdx' C:\HV\HW-M2.vhdx

# Create a new virtual machine
New-VM -Name HW-M2 -MemoryStartupBytes 2gb -VHDPath C:\HV\HW-M2.vhdx -Generation 2 -SwitchName "Hyper-V Internal Switch"

# Create second disk
New-VHD -Path "C:\HV\HW-M2-DISK1.vhdx" -SizeBytes 10gb -Dynamic

# Attach the second disk
Add-VMHardDiskDrive -VMName HW-M2 -Path "C:\HV\HW-M2-DISK1.vhdx"

# Create third disk 
New-VHD -Path "C:\HV\HW-M2-DISK2.vhdx" -SizeBytes 10gb -Dynamic

# Attach the third disk
Add-VMHardDiskDrive -VMName HW-M2 -Path "C:\HV\HW-M2-DISK2.vhdx"

# Create fourth disk
New-VHD -Path "C:\HV\HW-M2-DISK3.vhdx" -SizeBytes 20gb -Dynamic

# Attach the fourth disk
Add-VMHardDiskDrive -VMName HW-M2 -Path "C:\HV\HW-M2-DISK3.vhdx"

# Create fifth disk
New-VHD -Path "C:\HV\HW-M2-DISK4.vhdx" -SizeBytes 20gb -Dynamic

# Attach the fifth disk
Add-VMHardDiskDrive -VMName HW-M2 -Path "C:\HV\HW-M2-DISK4.vhdx"

# Power on the VM
Start-VM -VMName HW-M2

# Rename the VM
Invoke-Command -VMName HW-M2 -ScriptBlock { Rename-Computer -NewName HW-M2 -Restart }

# Domain join
Invoke-Command -VMName HW-M2 -ScriptBlock { Add-Computer -DomainName Home.LAB -Restart }

# Add second network adapter to the second machine (HW-M1/HWM2)
Add-VMNetworkAdapter -VMName HW-M2 -SwitchName "Private Switch"

# Set the IP address
Invoke-Command -VMName HW-M2 -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.67.100" -PrefixLength 24 }

# Add second network adapter to the first machine (HW-DC/EM1)
Add-VMNetworkAdapter -VMName HW-DC -SwitchName "Private Switch"

# Set the IP address
Invoke-Command -VMName HW-DC -ScriptBlock { New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress "192.168.67.2" -PrefixLength 24 } 

# Switch session to the VM
Enter-PSSession -VMName HW-M2

# Set disk type of the two 10GB disks to SSD
Get-PhysicalDisk | Where DeviceID -In -Value 1,2 | Set-PhysicalDisk -MediaType SSD

# Set disk type of the two 20GB disks to HDD
Get-PhysicalDisk | Where DeviceID -In -Value 3,4 | Set-PhysicalDisk -MediaType HDD

# Create the pool
$PD = (Get-PhysicalDisk -CanPool $true); New-StoragePool -FriendlyName HomeworkPool -StorageSubsystemFriendlyName "Windows Storage*" -PhysicalDisks $PD -Verbose

# Define SSD tier
New-StorageTier -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "SSDTier" -MediaType SSD -Verbose

# Define HDD tier
New-StorageTier -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "HDDTier" -MediaType HDD -Verbose

# Create virtual hard drive 
New-Volume -StoragePoolFriendlyName "HomeworkPool" -FriendlyName "HomeworkDisk" -AccessPath "X:" -ResiliencySettingName "Mirror" -ProvisioningType "Fixed" -StorageTiers (Get-StorageTier -FriendlyName "*SSD*"), (Get-StorageTier -FriendlyName "*HDD*") -StorageTierSizes 6gb, 16gb -FileSystem NTFS -AllocationUnitSize 64KB

# Install iSCSI Target role component
Install-WindowsFeature FS-iSCSITarget-Server

# Create iSCSI target
New-IscsiServerTarget -TargetName "homework" -InitiatorId @("IPAddress:192.168.67.2")

# Create iSCSI virtual hard disk
New-IscsiVirtualDisk -Path "X:\homework-iscsi-disk.vhdx" -Size 10GB

# Attach iSCSI virtual hard disk to an iSCSI target
Add-IscsiVirtualDiskTargetMapping -TargetName "homework" -DevicePath "X:\homework-iscsi-disk.vhdx"

# Exit PowerShell session
exit

# Establish PowerShell session to the other machine (DC in our case)
Enter-PSSession -VMName HW-DC

# Start iSCSI initiator service
Start-Service msiscsi

# Set service start up type to automatic
Set-Service msiscsi -StartupType Automatic

# Create new iSCSI target portal
New-IscsiTargetPortal -TargetPortalAddress "192.168.67.100" -InitiatorPortalAddress "192.168.67.2" -InitiatorInstanceName "ROOT\ISCSIPRT\0000_0"

# Connect to an iSCSI target
$TARGET=Get-IscsiTarget
Connect-IscsiTarget -NodeAddress $TARGET.NodeAddress -TargetPortalAddress "192.168.67.100" -InitiatorPortalAddress "192.168.67.2" -IsPersistent $true

# Initialize and format the disk
Initialize-Disk -Number 1 -PartitionStyle GPT 
New-Volume -DiskNumber 1 -FriendlyName "iSCSIDisk" -FileSystem NTFS -DriveLetter S

# Create folder
New-Item -ItemType Directory -Path "S:\Shared Data"

# Set NTFS permissions
$ACL = Get-Acl -Path "S:\Shared Data"
$AR = New-Object System.Security.AccessControl.FileSystemAccessRule("Home\Domain Users", "Read", "Allow")
$ACL.SetAccessRule($AR)
$AR = New-Object System.Security.AccessControl.FileSystemAccessRule("Home\Domain Admins", "FullControl", "Allow")
$ACL.SetAccessRule($AR)
$ACL | Set-Acl -Path "S:\Shared Data"

# Share the folder
New-SmbShare -Name "Shared" -Path "S:\Shared Data" -FullAccess Everyone