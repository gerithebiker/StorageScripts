<#

.SYNOPSIS
  Gets the free/used space on mount points on a local or remote Windows server, with disk IDs, and Symmetrix IDs.
  
.DESCRIPTION
  It displays information about all mount points that are listed in the Win32_MountPoint WMI class (which includes "regular" drives, but they're filtered out by default), and combines it with the information about size and used space in the Win32_Volume WMI class, based on the device ID (formats are slightly different, so a conversion is made). It also collect the information about the Symmetrix IDs, if there is powermt.exe installed on the given computer.
  
.PARAMETER Computers
  The script will query the provided list of computers. It can be one or more machines, devided by comma.
.PARAMETER SelectDrives
  The scirpt will select the drives that has the label provided. It can be more than one string, devided by comma, or part of the string you want to select. For example if you want to select all the drives for ADB database under drive "H", the you can use -SelectDrives H_ADB
.PARAMETER IncludeRootDrives
  The drives with drive letter will be displayed
.PARAMETER PromptForCredentials
  The script will ask for credentials to use for connecting to the given computer
.PARAMETER Progress
  During run-time, the script will display progress report. Querying a server that has lots of drives can take a long time
  
.LINK
https://jrich523.wordpress.com/2015/02/27/powershell-getting-the-disk-drive-from-a-volume-or-mount-point/
https://www.powershelladmin.com/wiki/PowerShell_Get-MountPointData_Cmdlet

.OUTPUTS
  Prints the result on screen or to the pipe
  
.NOTES
  Version:        	1.2
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


.EXAMPLE
  Get-MountPointData.ps1 MYSERVER01
	It will query the server MYSERVER01, and print out the information to the screen.
.EXAMPLE
  Get-MountPointData.ps1 -Computers MYSERVER01,MYSERVER02 -SelectDrives HDRV_01
	It will query the servers MYSERVER01 and MYSERVER02, and displays the drives that's label contains the string H_MP_AGMI.
.EXAMPLE
  Get-MountPointData.ps1 -Computers MYSERVER01,MYSERVER02 -SelectDrives HDRV_01,HDRV_02,HDRV_03 -Progress
	It will query the servers MYSERVER01 and MYSERVER02, and displays the drives with the labels HDRV_01, HDRV_02, HDRV_03. It will also show progress report.

#>

    [CmdletBinding(
        DefaultParameterSetName='NoPrompt'
    )]
    param(
        [Parameter(Mandatory=$true,Position=0)][string[]] $Computers,
		[Parameter()][string[]] $SelectDrives=".", #The default value is a dot, so if no parameter given, it will select all the drives
        [Parameter(ParameterSetName='Prompt')][switch] $PromptForCredentials,
        [Parameter(ParameterSetName='NoPrompt')][System.Management.Automation.Credential()] $Credential = [System.Management.Automation.PSCredential]::Empty,
        [switch] $IncludeRootDrives,
		[switch] $Progress
    )

# We put together a pattern for selecting the drives that were passed to the script. 
# The default value is '.', meaning all of the volumes will be selected, this is used as a regex
if ($SelectDrives -ne "."){
	$VerboseMessage="Creating search string out of: " + $SelectDrives
	Write-Verbose $VerboseMessage
	$drivesString=$SelectDrives[0]
	if ($SelectDrives.count -gt 1){
		for ($i=1; $i -lt $SelectDrives.count; $i++){
			$drivesString="$drivesString" + "|" + $SelectDrives[$i]
		}
	}
	$SelectDrives=$drivesString
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
    
}

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
"@
try {
    Add-Type -TypeDefinition $STGetDiskClass -ErrorAction Stop
}
catch {
    if (-not $Error[0].Exception -like '*The type name * already exists*') {
        Write-Warning -Message "Error adding [STGetDisk] class locally."
    }
}

    
    foreach ($Computer in $Computers) {
			<# 	We are going to collect all the mount points into the variable $mountPoints, 
				Because we need the object later
				Originally this big scriptblock was the whole script,
				Maybe it would make sense to move the SB to a function to make the Script more readable
			#>
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
						Select-Object Label, Caption, Capacity, FreeSpace, FileSystem, DeviceID, @{n='Computer';e={$Computer}} | Where-Object {$_.Label -Match "$SelectDrives"} )
				}
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
					}
				} | Sort-Object -Property 'Caption' | #, @{Descending=$true;e={$_.'Size (GB)'}}, Label, Caption |
					Select-Object -Property @{n='Computer'; e={$_.Computer}},
						@{n='Label';        e={$_.Label}},
						@{n='Caption';      e={$_.Caption}},
						@{n='FileSystem';   e={$_.FileSystem}},
						@{n='Size (GB)';    e={$_.'Size (GB)'.ToString('N')}},
						@{n='Free space';   e={$_.'Free space'.ToString('N')}},
						@{n='Percent free'; e={$_.'Percent free'.ToString('N')}},
						@{n='Disk Index'; e={
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
	$powermtOut=Invoke-Command -ComputerName $Computer -ScriptBlock {powermt display dev=all} -ErrorVariable PowerMTError 2>$null
	
	if ($PowerMTError){
		Write-Host "    + PowerMT Error         : There is no powermt.exe installed on $Computer" -ForegroundColor "red" -BackgroundColor "black"
		$mountPoints | Format-Table -AutoSize
		Continue
	}

	$powermtOut=$powermtOut | Select-String "Pseudo", "Symmetrix", "Logical"
	$powermtOut=[regex]::Replace($powermtOut, "`r`n", ",") | % {$_-replace "Pseudo name=", ";" -replace " Symmetrix ID=", "," -replace " Logical device ID=", " " -replace "harddisk", ""}
	
	# We need a hash table, easier to add the LUN ISs to the mount points
	# The hash's key is the drive number, the value is the Array ID and the LUN ID separated by a space
	$lunidHash=[ordered]@{}
	$powermtOut -split ";"| %{$tempString=$_ -split ",";$lunidHash.add($tempString[0],$tempstring[1])}
	
	Write-Verbose "Done reading LUN IDs, starting on combining the two."
	
	# Here is why we needed the hash, we loop through the mountpoints and add LUN IDs and Array ID.
	ForEach ($mntPoint in $mountPoints){ 
		$key=$mntPoint."Disk Index"
		$tempString=$lunidHash."$key" -split " "
		$mntPoint | Add-Member -NotePropertyName ArrayNumber -NotePropertyValue $tempString[0]
		$mntPoint | Add-Member -NotePropertyName lunID -NotePropertyValue $tempString[1]
	} # End of "for loop" to add the LUN IDs
		
	# Now we check if the "Computer" is part of a cluster. If yes, we print out some info, including the current owner node name
	# The error is redirected to null, to have a nicer output
	$NodeName=Get-ClusterGroup -Name $Computer -Cluster $Computer -ErrorVariable notClusterNode 2>$null
	
	if ($notClusterNode){
		$VerboseMessage=$Computer + " is not part of a cluster..."
		Write-Verbose "$VerboseMessage"
	} else {
		"`r`n"
		$WarningMessage=$Computer + " is member of a cluster, pls use the `"OwnerNode`" name in the Change Request!"
		Write-Warning  $WarningMessage
		$NodeName | Select-Object name,cluster,ownernode,state | Format-List
	}
	
	Write-Verbose "And now the result:"
	# I use Format-Table here, because this is the format I'd like to have the output. If I don't use it,
	#	and call the script with a pipe and then FT, then the output gets garbled...
	$mountPoints | Format-Table

}









