<#
.SYNOPSIS
  Gets the remote Windows server's HBA port information

.DESCRIPTION
  It will display HBA information from the remote Windows server, and converts it to the format that can be used in fiber Switches

.PARAMETER ComputerName
    The name of the remote computer that will be queried

.INPUTS
  None

.OUTPUTS
  None

.NOTES
  Version:        1.0
  Author:         Geri
  Creation Date:  2019.09.25
  Purpose/Change: Initial script development

  I used my template for the script, did not remove the unused parts yet.

.EXAMPLE
  Get-ServerHBAPorts.ps1 Server01
  It will display the HBA info from Server01
#>

#-------------------------------------------------------[Parameter Handling]-------------------------------------------------------

    [CmdletBinding()] # For using the common parameters
    Param (
		[string]$ComputerName = "localhost"
	)



#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Dot Source required Function Libraries. It is not defined yet
#. "Path\Library.ps1"

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = "1.0"

#Log File Info
$sLogPath = "$env:homedrive$env:homepath\Temp"
<#
#Checking logpath
if(!(Test-Path -Path $sLogPath )){
    New-Item -ItemType directory -Path $sLogPath
}#>

$sLogName = $MyInvocation.MyCommand.Name.Split('.')[0]
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#
Function <FunctionName>{
  Param()

  Begin{
    Log-Write -LogPath $sLogFile -LineValue "<description of what is going on>..."
  }

  Process{
    Try{
      <code goes here>
    }

    Catch{
      Log-Error -LogPath $sLogFile -ErrorDesc $_.Exception -ExitGracefully $True
      Break
    }
  }

  End{
    If($?){
      Log-Write -LogPath $sLogFile -LineValue "Completed Successfully."
      Log-Write -LogPath $sLogFile -LineValue " "
    }
  }
}
#>

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Check the connection to remote system
if (Test-Connection -computername $ComputerName -count 1 -Quiet) {
	Write-Verbose "Successfully connected to $ComputerName"
	} else {
	Write-Verbose "Connection to $ComputerName was NOT successfull!!!"
					Write-Host "Connection Error: Failed to connect to $Computer" -ForegroundColor "red" -BackgroundColor "black"
					Write-Host "    + CategoryInfo:   Connection" -ForegroundColor "red" -BackgroundColor "black"
					Write-Host "    + ExceptionInfo:  Failed to connect to $Computer computer" -ForegroundColor "red" -BackgroundColor "black"
					exit
	} #End If "Test-Connection"

#This message displayed only if the script called with the "-Verbose" switch
Write-Verbose -Message "<Message comes here.>"


#Log-Start -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
#Script Execution goes here
$myPorts=Invoke-Command -ComputerName $ComputerName {get-initiatorport} | select PSComputerName,NodeAddress,PortAddress
foreach ($myPort in $myPorts) {
	$tempA=$myPort.portaddress
	$swithTPaddress=for ($i=2; $i -lt 22; $i += 3){$tempA=$tempA.Insert($i,":")}
	$myPort | Add-Member -NotePropertyName swithTPaddress -NotePropertyValue $tempA
}

$myPorts

#Log-Finish -LogPath $sLogFile
