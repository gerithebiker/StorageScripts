#This script converts VMAX NAA number to LUN ID very basic, downloaded from the web, this is not my script
param ([Parameter(Mandatory=$true)][string]$naaID)

#Function Convert-naaIDIdToVmaxDeviceId ($naaID) {
  if ($naaID.length -ne 36) { "naaID value must be 36 characters"; break }
  $deviceString = $naaID.ToCharArray()
  $device = [char][Convert]::ToInt32("$($deviceString[26])$($deviceString[27])", 16)
  $device += [char][Convert]::ToInt32("$($deviceString[28])$($deviceString[29])", 16)
  $device += [char][Convert]::ToInt32("$($deviceString[30])$($deviceString[31])", 16)
  $device += [char][Convert]::ToInt32("$($deviceString[32])$($deviceString[33])", 16)
  $device += [char][Convert]::ToInt32("$($deviceString[34])$($deviceString[35])", 16)
  "$naaID,  $device"
 # return $device
#}
