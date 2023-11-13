
param
(
	[string]$sLogPath,
	[string]$sIncidentMessage
)

#
if (-Not $sLogPath) {
	Write-Host "FAILED - Application needs further investigation - PARAMETER_MISSING empty Log Path"
	[Environment]::Exit(1)
}

if (-Not $sIncidentMessage) {
	Write-Host "FAILED - Application needs further investigation - PARAMETER_MISSING empty Incident Message"
	[Environment]::Exit(2)
}

#
if (-Not (Test-Path $sLogPath)) {
	Write-Host "FAILED - Application needs further investigation - LOG_FILE NOT FOUND :" $sLogPath
	[Environment]::Exit(3)
}

# 08:19:52,000 DEBUG RECV: (lf)+CMS ERROR: 515(lf)
$sIncidentTime = ""
$sErrorNumber = ""
try {
	if ($sIncidentMessage -match '^(?<incTime>\d\d:\d\d:\d\d)[,\s]\d+ DEBUG RECV: \(lf\)\+CM[SE] ERROR: (?<errNumber>\d+)\(lf\)$') {
		$sIncidentTime = $Matches.incTime
		$sErrorNumber = $Matches.errNumber
	}
	else {
		Write-Host "FAILED - Application needs further investigation - PARAMETER_BAD_FORMAT Incident Message :" $sIncidentMessage
		[Environment]::Exit(4)
	}
}
catch {
	Write-Host "FAILED - Application needs further investigation - PARAMETER_BAD_FORMAT Incident Message :" $sIncidentMessage
	[Environment]::Exit(5)
}

try {
	# Search "Incident Time" with the "Incident Number" in the logfile
	# Stop and exit if the search is unsuccessful, continue if successful
	$sErrorPattern = [String]::Format("CMS ERROR:\s+{0}\(lf\)", $sErrorNumber)
	$sSearchIncident = Get-Content $sLogPath |
		where { $_ | select-string -Pattern $sIncidentTime } |
		where { $_ | select-string -Pattern $sErrorPattern }

	if ($sSearchIncident -eq $null){
		Write-Host "FAILED - Application needs further investigation - Incident NOT FOUND in the log file"
		[Environment]::Exit(6)
	}
}
catch {
	Write-Host "FAILED - Application needs further investigation - Unable to retrieve the incident in the log file"
	[Environment]::Exit(7)
}

try {
	# Search last Recipient time (last message sent in the log)
	$sRecipient = Get-Content $sLogPath | Where {$_ | Select-String -Pattern 'recipient' } | Select-Object -last 1
	if ($sRecipient -eq $null){
		Write-Host "FAILED CLOSED COMPLETE - Messages are not being sent normally, Needs further investigation."
		[Environment]::Exit(8)
	}
}	
catch {
	Write-Host "FAILED - Application needs further investigation - Unable to search for recipient line"
	[Environment]::Exit(9)
}

#
$ExitCode = 0
try {
	# Capture the 8 first caracters from the string in $sRecipientTime
	$sRecipientTime = $sRecipient.Substring(0,8)
	if ($sRecipientTime -gt $sIncidentTime) {
		Write-Host "SUCCESSFUL - Messages are being sent again, No impact to the application."
	}
	else {
		Write-Host "FAILED CLOSED COMPLETE - Messages are not being sent normally, Needs further investigation."
		$ExitCode = 11
	}
}
catch {
	Write-Host "FAILED - Application needs further investigation - Unable to get the recipient line time part"
	$ExitCode = 12
}

[Environment]::Exit($ExitCode)
