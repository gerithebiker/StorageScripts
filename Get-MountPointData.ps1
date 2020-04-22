<#

.SYNOPSIS
  Gets the free/used space on mount points on a remote Windows server, with disk/Symmetrix IDs, partition types
  
.DESCRIPTION
  It displays information about mount points that are listed in the Win32_MountPoint WMI class (which includes "regular" drives, but they're filtered out by default), and combines it with the information with size and used space in the Win32_Volume WMI class, based on the device ID (formats are slightly different, so a conversion is made). It also collects Symmetrix IDs, if there is powermt.exe installed on the given computer.
  
.PARAMETER Computers
  The script will query the provided list of computers. It can be one or more machines, devided by comma. Mandatory parameter
.PARAMETER SelectDrives
  The scirpt will select the drives that have the paths provided. It can be more than one string, devided by comma, or part of the string you want to select. For example if you want to select all the drives for ADB database under drive "H", then you can use -SelectDrives H:\H_ADB
.PARAMETER IncludeRootDrives
  The drives with drive letter will be displayed
.PARAMETER PromptForCredentials
  The script will ask for credentials to use for connecting to the given computer
.PARAMETER Progress
  During run-time, the script will display progress report. Querying a server that has lots of drives can take a long time
.PARAMETER csv
  Output will be saved in the current user's Document folder
  
.LINK
https://jrich523.wordpress.com/2015/02/27/powershell-getting-the-disk-drive-from-a-volume-or-mount-point/
https://www.powershelladmin.com/wiki/PowerShell_Get-MountPointData_Cmdlet

.OUTPUTS
  Prints the result on screen or to the pipe
  If -csv was specified, it will create a csv file in the current user's "Documents" folder with the name composed form the passed "Computers" parameter
  
.NOTES
  Version:        	1.3.5
  Author:		  	Geri (mailto:gergely.laszlo@molinahealthcare.com)
  OriginalScript: 	Joakim Svendsen
  Creation Date:  	08/26/2019
  Copyright (c):  	Geri
  Purpose/Change: 	Initial script development
  Change history: 	1.0 (Geri) 08/20/2019
						Initial, first working  version 
					1.1 (Geri) 08/26/2019
						Added the switch Progress to show progress report only if requested
						Added the parameter SelectDrives, to display only the drives that are passed. If not provided, it will show all the drives found.
						Changed the parameter ComputerName to Computers, to be consistent
						Enhanced error checking
					1.2	(Geri) 09/18/2019
						Added the cluster resource to physical server logic
						Moved the volume selection to select the list before querying the server. Shortens the run-time
					1.2.1 (Geri) 10/9/2019
						Changed the cluster checking part to not use name, but check it directly
					1.3 (Geri) 10/18/2019
						Added switch csv to have the output saved in a file
						Added collecting the partition type (MBR or GPT)
					1.3.1 (Geri) 10/18/2019
						It turned out in some cases Get-Disk gives back the partition type as a number. Implemented a check, and if it is a number, then it is converted to the appropriate string.
					1.3.2 (Geri) 10/23/2019
						Use path name containing the drive letter also. So you have to start with X:\
					1.3.3 (Geri) 11/07/2019
						Bug fix. Finding MBR/GPT style partition for the drives were incorrect
					1.3.4 (Geri) 01/23/2020
						In case a drive inaccessible on the host, PowerMT can give error message. It is handled now, 
							the script gives a correct error message.
						The number of drive gave no number in case only one drive per server. It is correct now.
							It still gives no number in the same case when using -verbose at one of the verbose messages.
					1.3.4.1 (Geri) 01/24/2020
						The drive path can be passed with / instead of \. Now it is corrected if necessary.
					1.3.5 (Geri) 02/17/2020
						To prevent selecting mount points from under different drive letters, a drive selection string has to start with drive "letter-colon-back slash",
							like "x:\". This ensures that drives will be selected only from uder the specified drives.
					1.3.5.1 (Geri) 03/19/2020
						Bug fixes:
							- If powermt was not installed on a remote system, the rest of the loop did not run, but it can still collect useful info. It is fixed.
							- Get-ClusterGroup was running on the machine where the script was running, changed it to run on the remote system
						Updates:
							- Minor changes like output format.
					2.0 (Geri) 03/31/2020
						This is a new major version as I added the -Extend switch. It generates the output to extend the drives were found.
							-Extend is working in GB. It has some limitations: it can except only one extension size. So if different drives
							needs to be extended by different sizes, then the drives must be groupped by extension size, and run the script separetly
						Also added the function Write-HostInColor, it is able to print custom objects in color with leading 8 spaces
.EXAMPLE
  Get-MountPointData.ps1 Server1
	It will query the server Server1, and print out the information to the screen.
.EXAMPLE
  Get-MountPointData.ps1 -Computers Server1,Server2 -SelectDrives H:\MOUNT_POINT01
	It will query the servers Server1 and Server2, and displays the drives that's label contains the string H:\MOUNT_POINT01.
.EXAMPLE
  Get-MountPointData.ps1 -Computers Server1,Server2 -SelectDrives H:\MOUNT_POINT01,H:\MOUNT_POINT02,H:\MOUNT_POINT03 -Progress
	It will query the servers Server1 and Server2, and displays the drives with the labels MOUNT_POINT01, MOUNT_POINT02, MOUNT_POINT03. It will also show progress report. 
	In case one of the to be selected drives does not have the drive letter, the script throws an error message, and stops running.
#>

############################################
#               Parameters
############################################

    [CmdletBinding(
        DefaultParameterSetName='NoPrompt'
    )]
    param(
        [Parameter(Mandatory=$true,Position=0)][string[]] $Computers,
		[Parameter()][string[]] $SelectDrives=".", #The default value is a dot, so if no parameter given, it will select all the drives
        [Parameter(ParameterSetName='Prompt')][switch] $PromptForCredentials,
        [Parameter(ParameterSetName='NoPrompt')][System.Management.Automation.Credential()] $Credential = [System.Management.Automation.PSCredential]::Empty,
        [switch] $IncludeRootDrives,
		[switch] $Progress,
		[switch] $csv,
		[Parameter()][int] $Extend=0
    )
	
	# Max allowed lun size is 4096GB. If needed, replace the size here
	$MaxLUNSize = 4096

############################################
#                 Functions
############################################

Function Write-HostInColor ($data, $foreground, $background){
	$a=$data | Format-Table | Out-String -Stream | Where-Object { $_ -match '\S' }
	for ($i = 0; $i -lt $a.Count; $i++) {
		if ($foreground){
			$host.ui.RawUI.ForegroundColor = $foreground
			if ($background){
				$host.ui.RawUI.BackgroundColor = $background
			}
		}
		Write-Host "       "$a[$i]  
		[Console]::ResetColor()
	} 
} # End of Write-HostInColor

############################################
#                 Main
############################################

# Hastable for hosts
$AdminHosts = @{ 	"000111111111" = "Server1"
					"000222222222" = "Server2"
					# You can list your admin hosts here, left side is array serial number, right side is server name
					# This is used only for to create the change order part
				}

$SelectDriveIssue=0 # General counter for checking the select string parameters
if ($SelectDrives -ne "."){ # This "if" runs only if the parameter was provided
	$First=0
	# Replace "/" with "\" in case the path was provided incorrectly
	$SelectDrives=$SelectDrives.replace("/","\")
	foreach ($Drive in $SelectDrives){ # To avoid selecting dirves from different mount drives, the path must start with drive letter, colon, \
		$WriteDrive=0
		if ($Drive.substring(0,1) -notmatch "[a-zA-Z]") {
			$SelectDriveIssue++
			$WriteDrive++
		}
		if ($Drive.substring(1,2) -ne ":\") {
			$SelectDriveIssue++
			$WriteDrive++
		}
		if ($WriteDrive -ne 0) { 
			if ($First -eq 0){
				Write-Host "Search-String Error: A search path has to contain drive letter and `":\`"" -ForegroundColor "red" -BackgroundColor "black"
				Write-Host "+         The following path(s) do not have correct format:" -ForegroundColor "red" -BackgroundColor "black"
				$First++
			}
			Write-Host "+        " $Drive "" -ForegroundColor "red" -BackgroundColor "black"
		}
	} # End of foreach
} # End of if $SelectDrives

if ($SelectDriveIssue -ne 0) {
	Write-Host "`n`rAt least on of the provided path is not a full path with drive letter." -ForegroundColor "red" -BackgroundColor "black"
	Write-Host "+         Please check, and re-run the script!!!" -ForegroundColor "red" -BackgroundColor "black"
	Write-Host "+         Exiting..." -ForegroundColor "red" -BackgroundColor "black"
	Exit
} # End of if $SelectDriveIssue

Write-Host "The drive(s) " -ForegroundColor Yellow -NoNewLine
Write-Host "`"$SelectDrives`"" -ForegroundColor Yellow -BackgroundColor "black" -NoNewLine
Write-Host " will be used for selecting drives." -ForegroundColor Yellow 

# We put together a pattern for selecting the drives that were passed to the script. 
# The default value is '.', meaning all of the volumes will be selected, this is used as a regex
if ($SelectDrives -ne "."){
	$VerboseMessage="Creating search string out of: " + $SelectDrives
	Write-Verbose $VerboseMessage
	$drivesString=$SelectDrives[0] #-replace '\\$',''
	if ($SelectDrives.count -gt 1){
		for ($i=1; $i -lt $SelectDrives.count; $i++){
			$drivesString="$drivesString" + "|" + $SelectDrives[$i] #-replace '\\$',''
		}
	}
	
	# We have to replace "\" in a drive string to "\\", because it is used as a regex, so need to be "escaped"
	$SelectDrives=$drivesString.replace('\','\\')
	Write-Verbose "`"$SelectDrives`" to be selected"
} else {
	Write-Verbose "No `"SelectDrives`" parameter was passed, working on all the drives, may take a long time!"
}# end of "if selectdrives" 

# Convert from one device ID format to another.
function Get-DeviceIDFromMP {
    param([Parameter(Mandatory=$true)][string] $VolumeString,
          [Parameter(Mandatory=$true)][string] $Directory)
    
    if ($VolumeString -imatch '^\s*Win32_Volume\.DeviceID="([^"]+)"\s*$') {
        # Return it in the wanted format.
        $Matches[1] -replace '\\{2}', '\'
    }
    else {
        # Return a presumably unique hashtable key if there's no match.
        "Unknown device ID for " + $Directory
    }
} # End of Get-DeviceIDFromMP function

# Thanks to Justin Rich (jrich523) for this C# snippet. More info in the help section
$STGetDiskClass = @"
using System;
using Microsoft.Win32.SafeHandles;
using System.IO;
using System.Runtime.InteropServices;

public class STGetDisk
{
    private const uint IoctlVolumeGetVolumeDiskExtents = 0x560000;

    [StructLayout(LayoutKind.Sequential)]
    public struct DiskExtent
    {
        public int DiskNumber;
        public Int64 StartingOffset;
        public Int64 ExtentLength;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DiskExtents
    {
        public int numberOfExtents;
        public DiskExtent first;
    }

    [DllImport("Kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern SafeFileHandle CreateFile(
    string lpFileName,
    [MarshalAs(UnmanagedType.U4)] FileAccess dwDesiredAccess,
    [MarshalAs(UnmanagedType.U4)] FileShare dwShareMode,
    IntPtr lpSecurityAttributes,
    [MarshalAs(UnmanagedType.U4)] FileMode dwCreationDisposition,
    [MarshalAs(UnmanagedType.U4)] FileAttributes dwFlagsAndAttributes,
    IntPtr hTemplateFile);

    [DllImport("Kernel32.dll", SetLastError = false, CharSet = CharSet.Auto)]
    private static extern bool DeviceIoControl(
    SafeFileHandle hDevice,
    uint IoControlCode,
    [MarshalAs(UnmanagedType.AsAny)] [In] object InBuffer,
    uint nInBufferSize,
    ref DiskExtents OutBuffer,
    int nOutBufferSize,
    ref uint pBytesReturned,
    IntPtr Overlapped
    );

    public static string GetPhysicalDriveString(string path)
    {
        //clean path up
        path = path.TrimEnd('\\');
        if (!path.StartsWith(@"\\.\"))
            path = @"\\.\" + path;

        SafeFileHandle shwnd = CreateFile(path, FileAccess.Read, FileShare.Read | FileShare.Write, IntPtr.Zero, FileMode.Open, 0, IntPtr.Zero);
        if (shwnd.IsInvalid)
        {
            //Marshal.ThrowExceptionForHR(Marshal.GetLastWin32Error());
            Exception e = Marshal.GetExceptionForHR(Marshal.GetLastWin32Error());
        }

        uint bytesReturned = new uint();
        DiskExtents de1 = new DiskExtents();
        bool result = DeviceIoControl(shwnd, IoctlVolumeGetVolumeDiskExtents, IntPtr.Zero, 0, ref de1, Marshal.SizeOf(de1), ref bytesReturned, IntPtr.Zero);
        shwnd.Close();

        if (result)
            return @"\\.\PhysicalDrive" + de1.first.DiskNumber;
        return null;
    }
}
"@ #End of $STGetDiskClass

try {
    Add-Type -TypeDefinition $STGetDiskClass -ErrorAction Stop
}
catch {
    if (-not $Error[0].Exception -like '*The type name * already exists*') {
        Write-Warning -Message "Error adding [STGetDisk] class locally."
    }
}

if ($csv) {
	$outPath=[Environment]::GetFolderPath("Desktop") + "\"

	$VerboseMessage="Creating file name out of: " + $Computers
	Write-Verbose $VerboseMessage
	$outFile=$Computers[0]
	if ($Computers.count -gt 1){
		for ($i=1; $i -lt $Computers.count; $i++){
			$outFile="$outFile" + "_" + $Computers[$i]
		}
	}
	$outFile=$outFile + ".txt"
	Write-Verbose "The results will be in `"$outFile`" file on your Desktop"
	if (Test-Path $outPath$outFile){
		Remove-Item $outPath$outFile #2>$null
	}
} # EndIf csv

    foreach ($Computer in $Computers) {
			
			# We have to check if the given name is the "A" record of the server. If not, have to swap name
			if ($Progress){Write-Progress -CurrentOperation "Checking DNS name of $Computer." ("DNS Check")}
			$isServerNameOK=Resolve-DNSname $Computer -type A
			if ($isServerNameOK.namehost.count -gt 0){
				$isServerNameOK=$isServerNameOK.namehost | %{$_.Split('.')[0]} #make sure it is only the server name
				if ($isServerNameOK -ne $Computername) {
					Write-Verbose "Passed name and DNS name is not the same, swapping!!!"
					Write-Host "You will see $isServerNameOK instead of $Computer, because of DNS name." -ForegroundColor "red" -BackgroundColor "black"
					Write-Host " "
					$Computer=$isServerNameOK
				}
			}
			$mountPoints=invoke-command -scriptblock {
				if ($Progress){Write-Progress -CurrentOperation "Working on $Computer computer." ("Collecting disk information")}
				#Check the connection to remote system
				if (Test-Connection $Computer -count 1 -Quiet) {
					Write-Verbose "Connection to $Computer successfull"
				} else {
					Write-Verbose "Connection to $Computer was NOT successfull!!!"
					#Write-Error -Message $Computer -Category "Connection" -Exception "Failed connecting to computer!!"
					#Write-Error gives a weird output, for now I replace it
					Write-Host "Connection Error: Failed to connect to $Computer" -ForegroundColor "red" -BackgroundColor "black"
					Write-Host "    + CategoryInfo:   Connection" -ForegroundColor "red" -BackgroundColor "black"
					Write-Host "    + ExceptionInfo:  Failed to connect to $Computer computer" -ForegroundColor "red" -BackgroundColor "black"
					Continue
				} #End If "Test-Connection"
				
				$WmiHash = @{
					Computer = $Computer
					ErrorAction  = 'Stop'
				}
				
				#	If specified, then asking for credentials
				if ($PSCmdlet.ParameterSetName -eq 'Prompt') {
					$WmiHash.Credential = Get-Credential
				}
				elseif ($Credential.Username) {
					$WmiHash.Credential = $Credential
				}
				
				try {
					# Collect mount point device IDs and populate a hashtable with IDs as keys
					if ($Progress){Write-Progress -CurrentOperation "Collecting mount-point data from $Computer computer." ("Collecting disk information")}
					Write-Verbose "Collecting mount-point data"
					$MountPointData = @{}
					Get-WmiObject @WmiHash -Class Win32_MountPoint | 
						Where-Object {
							if ($IncludeRootDrives) {
								$true
							}
							else {
								$_.Directory -NotMatch '^\s*Win32_Directory\.Name="[a-z]:\\{2}"\s*$'
							}
						} |
						ForEach-Object {
							$MountPointData.(Get-DeviceIDFromMP -VolumeString $_.Volume -Directory $_.Directory) = $_.Directory
					}
					# Querying the volumes, and with the Where-Object we select only the requested drives
					$Volumes = @(Get-WmiObject @WmiHash -Class Win32_Volume | Where-Object {
							if ($IncludeRootDrives) { $true } else { -not $_.DriveLetter }
						} | 
						Select-Object Label, Caption, Capacity, FreeSpace, FileSystem, DeviceID, @{n='Computer';e={$Computer}} | Where-Object {$_.Caption -Match "$SelectDrives"} )
				} # End try
				catch {
					Write-Error "${Computer}: Terminating WMI error (skipping): $_"
					continue
				}
				
				if (-not $Volumes.Count) {
					Write-Error "${Computer}: No mount points found. Skipping."
					continue
				}
				
				#if ($PSBoundParameters['IncludeDiskInfo']) {
				$DiskDriveWmiInfo = Get-WmiObject @WmiHash -Class Win32_DiskDrive
				#}
				$VerboseMessage="Volumes: " + $Volumes.label
				Write-Verbose $VerboseMessage
				
				$Volumes | ForEach-Object {
				
					if ($MountPointData.ContainsKey($_.DeviceID)) {
						# Let's avoid dividing by zero, it's so disruptive.
						if ($_.Capacity) {
							$PercentFree = $_.FreeSpace*100/$_.Capacity
						}
						else {
							$PercentFree = 0
						}
						$_ | Select-Object -Property DeviceID, Computer, Label, Caption, FileSystem, @{n='Size (GB)';e={$_.Capacity/1GB}},
							@{n='Free space';e={$_.FreeSpace/1GB}}, @{n='Percent free';e={$PercentFree}}
					} # End if $MountPointData
				} | Sort-Object -Property 'Caption' | #, @{Descending=$true;e={$_.'Size (GB)'}}, Label, Caption |
					Select-Object -Property @{n='Computer'; e={$_.Computer}},
						@{n='Label';        e={$_.Label}},
						@{n='Caption';      e={$_.Caption}},
						@{n='FileSystem';   e={$_.FileSystem}},
						@{n='Size_GB';    e={$_.'Size (GB)'.ToString('N')}},
						@{n='Free_space';   e={$_.'Free space'.ToString('N')}},
						@{n='Percent_free'; e={$_.'Percent free'.ToString('N')}},
						@{n='Disk_Index'; e={
								try {
									$ToDisplay=$_.Label
									if ($Progress){Write-Progress -CurrentOperation "Working on $ToDisplay volume in computer $Computer" ( "Collecting information about the volumes..." )}
									$ScriptBlock = {
										param($GetDiskClass, $DriveString)
										try {
											Add-Type -TypeDefinition $GetDiskClass -ErrorAction Stop
										}
										catch {
											#Write-Error -Message "${Computer}: Error creating class [STGetDisk]"
											return "Error creating [STGetDisk] class: $_"
										}
										return [STGetDisk]::GetPhysicalDriveString($DriveString)
									} 
									if ($Credential.Username) {
										$PhysicalDisk = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $STGetDiskClass, $(if ($_.Caption -imatch '\A[a-z]:\\\z') { $_.Caption } else { $_.DeviceID.TrimStart('\?') })
									}
									else {
										$PhysicalDisk = Invoke-Command -ComputerName $Computer -ScriptBlock $ScriptBlock -ArgumentList $STGetDiskClass, $(if ($_.Caption -imatch '\A[a-z]:\\\z') { $_.Caption } else { $_.DeviceID.TrimStart('\?') })
									}
									if ($PhysicalDisk -like 'Error*') {
										"Error: $PhysicalDisk"
									}
									else {
										($DiskDriveWmiInfo | Where-Object { $PhysicalDisk } | Where-Object { $PhysicalDisk.Trim() -eq $_.Name } | Select-Object -ExpandProperty Index) -join '; '
									}
								} # end of try of disk index expression
								catch {
									"Error: $_"
								}
							} # end of disk index expression
						} # end of if disk index hashtable 
	} # End of mount point collection
	
	$VerboseMessage="Number of drives found: " + $mountPoints.count
	Write-Verbose "$VerboseMessage"
	Write-Verbose "Done collecting mount points, starting LUN IDs."
	if($Progress){Write-Progress -CurrentOperation "Working on $Computer computer." ("Collecting LUN ID information")}
	
	# Now we collect all the LUN IDs from the server, and put them into the powermtOut variable
	Write-Verbose "Collecting Storage info using powermt.exe on the remote computer"
	$powermtOut=Invoke-Command -ComputerName $Computer -ScriptBlock {powermt display dev=all} -ErrorVariable PowerMTError 2>$null
	
	if ($PowerMTError){
		Write-Verbose "PowerMT is NOT installed, see error message:"
		Write-Host "powermt.exe                 : The tool 'powermt.exe' is missing."  -ForegroundColor "red" -BackgroundColor "black"
		Write-Host "    + PowerMT Error         : There is no powermt.exe installed on $Computer" -ForegroundColor "red" -BackgroundColor "black" # If "powermt.exe" does not exist on the remote system, there is no point running the remaining powermt commands
		"`r`n" # To scatter the output we need an empty line
	} else {
		Write-Verbose "PowerMT is installed, getting the storage info from the remote system."
		$powermtOut=$powermtOut | Select-String "Pseudo", "Symmetrix", "Logical"
		$powermtOut=[regex]::Replace($powermtOut, "`r`n", ",") | % {$_-replace "Pseudo name=", ";" -replace " Symmetrix ID=", "," -replace " Logical device ID=", " " -replace "harddisk", ""}
		
		# We need a hash table, easier to add the LUN IDs to the mount points
		# The hash's key is the drive number, the value is the Array ID and the LUN ID separated by a space
		$lunidHash=[ordered]@{}
		$powerMTIssue=0
		
		$powermtOut -split ";"| %{
			$tempString=$_ -split ","
			if ($tempString[0] -eq "??") {
				$powerMTIssue=$powerMTIssue+1
				if ($powerMTIssue -lt 10){
					$tempString[0]="     Error0" + $powerMTIssue
				} else {
					$tempString[0]="     Error" + $powerMTIssue
				}
				if ($powerMTIssue -gt 0){
					if ($powerMTIssue -eq 1){
						Write-Host "There is an issue with the following drive(s):" -ForegroundColor "red" -BackgroundColor "black"
					}
					$DriveError=$tempString[0] + ": " + $tempString[1]
					Write-Host $DriveError -ForegroundColor "red" -BackgroundColor "black"
				}
			}
			$lunidHash.add($tempString[0],$tempString[1])
		}
		
		if ($powerMTIssue -gt 0){Write-Host "Please have the server $Computer checked out!!!"  -ForegroundColor "red" -BackgroundColor "black"}
	} # End of "if ($PowerMTError)"
	
	Write-Verbose "Done reading LUN IDs."
	
	# Now we collect the partition type (MBR vs GPT). Create another hashtable
	$myPartitionType=Invoke-Command -ComputerName $Computer -ScriptBlock {Get-Disk} -ErrorVariable IsGetDisk 2>null | Select-Object PartitionStyle,Number
	$partitionHash=[ordered]@{}
	$myPartitionType | %{$tmpString=$_; $partitionHash.add($tmpString.number,$tmpString.PartitionStyle)}
	#$myPartitionType=Get-WmiObject Win32_DiskPartition -computer $Computer | select diskindex,type
	
	Write-Verbose "Done reading partition types, combining LUN IDs, partition type with the mount points."
	$mntPointCounter=0
	# Here is why we needed the hash, we loop through the mountpoints and add LUN IDs and Array ID.
	ForEach ($mntPoint in $mountPoints){ 
		$key=$mntPoint."Disk_Index"
		$tempString=$lunidHash."$key" -split " "
		$mntPoint | Add-Member -NotePropertyName ArrayNumber -NotePropertyValue $tempString[0]
		$mntPoint | Add-Member -NotePropertyName lunID -NotePropertyValue $tempString[1]
		if ($IsGetDisk) {
			$VerboseMessage=$IsGetDisk.FullyQualifiedErrorId
			$VerboseMessage=$VerboseMessage + " error on $Computer"
			Write-Verbose $VerboseMessage
			
		} else {
			Write-Verbose "Switching..."
			# In some reason the hash table is not working in a way I expected with $partitionHash
			# So I had to loop through it to find the correct value
			foreach($partitionKey in $partitionHash.keys){
				if ($key -eq $partitionKey) {
					$myPartition=$partitionHash[$partitionKey]
				} # End if ($key -eq $partitionKey)
			} # End foreach($partitionKey in $partitionHash.keys)
			switch ($myPartition){
				"1" {$myPartitionStyle="MBR"}
				"2" {$myPartitionStyle="GPT"}
				default {$myPartitionStyle=$myPartition}
			}
			$mntPoint | Add-Member -NotePropertyName PartitionStyle -NotePropertyValue $myPartitionStyle
		} # End if ($IsGetDisk)
		$mntPointCounter++
	} # End of "for loop" to add the LUN IDs
		
	# Now we check if the "Computer" is part of a cluster. If yes, we print out some info, including the current owner node name
	# The error is redirected to null, to have a nicer output
	$NodeName=Invoke-Command -ComputerName $Computer -ScriptBlock {Get-ClusterGroup} -ErrorVariable notClusterNode 2>$null
	#Get-ClusterGroup -Name $Computer -Cluster $Computer -ErrorVariable notClusterNode 2>$null
	
	if ($notClusterNode){
		$VerboseMessage=$Computer + " is not part of a cluster..."
		Write-Verbose "$VerboseMessage"
	} else {
		"`r`n" # To scatter the output we need an empty line
		$WarningMessage=$Computer + " is member of a cluster, pls use the `"OwnerNode`" name in the Change Request!"
		Write-Warning  $WarningMessage
		$NodeName | Select-Object name,cluster,ownernode,state | Format-Table
	}
	
	Write-Verbose "And now the result:"
	if ($IsGetDisk) {Write-Host "`r`nThe Get-Disk command let is  missing from $Computer, I cannot provide `"partition type`" info...`r`nPlease check manually!!" -ForegroundColor "red" -BackgroundColor "black"}
	# I use Format-Table here, because this is the format I'd like to have the output. If I don't use it,
	#	and call the script with a pipe and then FT, then the output gets garbled...
	if ($csv){
		Write-Verbose "Creating text file in csv format."
		$mountPoints | Export-Csv $outPath$outFile -append
	}
	
	# Here we start the CO creation part. Now we only print the text on screen, later if there is any chance, this can be used for creating a CO directly in iServe
	# If Extend is defined, the "if" part creates the CO text. Extend has to have a size, by how much the LUN should be extended.
	# If Extend not provided, the found drives are going to be printed on screen
	if ($Extend){
		# Get the necessary variables from mountPoints. It should be the same for all LUNs
		$myArray=$mountPoints[0].ArrayNumber
		
		# First we have to check if a LUN can be expanded by the provided size
		# We collect the oversized LUNs into 2 arrays, and the correct ones to a third
		$bigMBR=@()
		$bigGPT=@()
		$okLUN=@()
		$mntPointCounter=0
		
		ForEach ($mntPoint in $mountPoints){
			$newSize=$Extend + $mntPoint.Size_GB
			if ($newSize -gt $MaxLUNSize) {
				# Bigger than allowed max size
				$bigGPT += $mntPoint
			} else {
				if ($newSize -gt 2048 -and $mntPoint.PartitionStyle -eq "MBR"){
					# MBR disks cannot be bigger than 2T
					$bigMBR += $mntPoint
				} else {
					# This is the correct size LUNs after increase. We also need a new counter for the number of LUNs
					$okLUN += $mntPoint
					$mntPointCounter++
				}
			}
		} # End of ForEach mountpoint selection
		#$okLUN | ft *
		if ($bigMBR.count -gt 0) {
			"`r`n"
			$WarningMessage="The following mountpoints are MBR, and cannot be extended by " + $Extend + ", because size would be bigger than 2TB!!"
			Write-Warning $WarningMessage
			Write-HostInColor $bigMBR "yellow" "black"
		} # EndIf bigMBR
		if ($bigGPT.count -gt 0) {
			"`r`n"
			$WarningMessage="The following mountpoints are GPT, and cannot be extended by " + $Extend + ", because size would be bigger than 4TB!!"
			Write-Warning $WarningMessage
			Write-HostInColor $bigGPT "yellow" "black"
		} # EndIf bigGPT
		
		$mountPoints=$okLUN # We put back the correct LUNs to the mountPoints variable
		$OverallSize=$Extend * $mountPoints.count
		
		# From here we print out the necessary commands and text for a change order
		"`r`n`r`n"
		Write-Host "Now the Change Order"  -ForegroundColor "yellow" -BackgroundColor "black"
		"`r`n"
		Write-Host "Short Description:" -ForegroundColor "yellow" -BackgroundColor "black"
		"	LUN extension for $Computer, $OverallSize GB`r`n`r`n"
		Write-Host "Description:" -ForegroundColor "yellow" -BackgroundColor "black"
		"	LUN expansion for $Computer, adding " + $mountPoints.count + " x $Extend GB to the following LUN(s):`r`n"
		Write-HostInColor $mountPoints  
		"`r`n	Number of mount points: " + $mntPointCounter  + "`r`n"
		"	Additional capacity needed, as the datastores are running out of space.`r`n`r`n"
		
		Write-Host "Pre-Production Testing:" -ForegroundColor "yellow" -BackgroundColor "black"
		"	# Login to array " + $myArray + " symcli management server " + $AdminHosts[$myArray] + ":"
		"	# Check the symapi database is in sync
	symcfg -sid " + $myArray + " sync 
	
	# Verify the ACLX database in the array  is consistent. 
	symaccess -sid " + $myArray + " verify

	# Verify symconfigure can be performed 
	symconfigure -sid " + $myArray + " verify

	# Always backup the symapi database before performing any configuration operations.
	symaccess -sid " + $myArray + " -f SymAPI_DB_Backup_<chg#>.txt backup  
	
	# Pre-Validations:
	symcfg -sid " + $myArray + " list -srp -v -tb
	
	#To verify the capacity of the LUNs:"
	
	# We have to put together the LUN IDs to a comma separated string for the size command
	$lunList=""
	ForEach ($mntPoint in $mountPoints){
		if ($lunList -eq ""){
			$lunList=$mntPoint.lunID
		} else {
			$lunList="$lunList" + "," + $mntPoint.lunID
		} #>
	}
		
	"	symdev -sid " + $myArray + " list -devs " + $lunList + " -gb"
	"`r`n`r`n"
	
	Write-Host "Implementation Plan and Resources:"  -ForegroundColor "yellow" -BackgroundColor "black"
	"	#To increase the size of the LUN(s):"
	ForEach ($mntPoint in $mountPoints){
		$newSize=$Extend + $mntPoint.Size_GB
		"        symdev -sid " + $myArray + " -devs " + $mntPoint.lunID + " modify -tdev -cap " + $newSize + " -captype gb -v" 
	}
	
	"`r`n`r`n"
	Write-Host "Rollback Plan:"  -ForegroundColor "yellow" -BackgroundColor "black"
	"	#Once a LUN increased, it cannot be shrinked back. New LUN(s) have to be created, copy the data to the new LUN, and mount to the original location.
	#If that happens, an outage bridge has to be created. Here are the commands for the storage side work:
	symconfigure -sid <sid#> -cmd `"create dev size=<originalCapacity> gb,count=1,emulation=FBA,config=TDEV;`" preview
	symconfigure -sid <sid#> -cmd `"create dev size=<originalCapacity> gb,count=1,emulation=FBA,config=TDEV;`" prepare
	symconfigure -sid <sid#> -cmd `"create dev size=<originalCapacity> gb,count=1,emulation=FBA,config=TDEV;`" commit
	
	#Add back the new LUN to the original storage group:
	symaccess -sid <sid#> -name <storageGroupName> -type storage add dev xxxxx 
	
	#Check the result
	symaccess -sid <sid#> list assignment -dev xxxxx 
	
	#At this point the LUNs are ready for rollback. Compute team has to mount the new LUNs, copy the data back, and mount the new LUNs to the original location"
	
	} else {
		# If no change order commands was requested, we print out the drive info
		$mountPoints | Format-Table *
		"Number of mount points: " + $mntPointCounter  + "`r`n" 
	}
}






