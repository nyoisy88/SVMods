# Users can view their own API Keys by visiting https://www.nexusmods.com/users/myaccount?tab=api%20access.

# Get the directory of the script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Directory to store the mods
$modsDir = $scriptDir

# Path to the settingsFile file
$settingsFile = "$modsDir\settings.json"

# Load settings from settings.json
$settings = Get-Content -Path $settingsFile | ConvertFrom-Json
$gameDomainName = $settings.gameDomainName
$headers = @{"apikey" = $settings.apiKey}

# Load cookies from the JSON file
$cookiesJson = Get-Content -Path "$modsDir\cookies.json" | ConvertFrom-Json

# Load CSV data
$modsCsvPath = "$modsDir\mods.csv"
$mods = Import-Csv -Path $modsCsvPath

# Create a new session
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# Add cookies to the session
foreach ($cookieData in $cookiesJson.cookies) {
	$cookie = New-Object System.Net.Cookie
    $cookie.Domain = $cookieData.domain
    $cookie.HttpOnly = $cookieData.httpOnly
    $cookie.Name = $cookieData.name
    $cookie.Path = $cookieData.path
    $cookie.Secure = $cookieData.secure
    $cookie.Value = $cookieData.value
    
    $session.Cookies.Add($cookie)
}

# Function to get the general mod information from Nexus Mods
function Get-ModInfo {
    param (
        [string]$modId
    )
    
    $uri = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId.json"    
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    return $response
}

# Function to get key and expire time from the download URL
function Get-KeyAndExpireTime {
    param (
        [string]$modId,
        [string]$fileId
    )

    $downloadUrl = "https://www.nexusmods.com/$gameDomainName/mods/$($modId)?tab=files&file_id=$fileId&nmm=1"
	
	$response = Invoke-WebRequest -Uri $downloadUrl -WebSession $session

	$slowDownloadButton = $response.ParsedHtml.getElementById("slowDownloadButton")
    $dataDownloadUrl = $slowDownloadButton.GetAttribute("data-download-url")
	Write-Host "Data Download URL: $dataDownloadUrl"

    # Extract key and expires from the data-download-url
    $uri = [Uri]::new($dataDownloadUrl)
    $query = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
    $key = $query["key"]
    $expires = $query["expires"]
	Write-Host "Download Key: $key, Expires: $expires"

    return @{
        key = $key;
        expires = $expires
    }
}
	
# Loop through each mod, check for updates, download, and extract if needed
foreach ($mod in $mods) {
    $modId = $mod.modId
	
	
	# Get general mod information from Nexus mods
    $modInfo = Get-ModInfo -modId $modId
	$modName = $modInfo.name
	Write-Host "Processing $modName($modId) ..."
	
    # Get the latest file mod information from Nexus Mods
    $latestModUrl = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId/files.json?category=main"
    $latestModResponse = Invoke-RestMethod -Uri $latestModUrl -Headers $headers -Method Get
    $latestModInfo = $latestModResponse.files | Sort-Object -Property "uploaded_timestamp" -Descending | Select-Object -First 1
    $latestVersion = $latestModInfo.version
    $latestFileId = $latestModInfo.file_id

	# Check if modName is empty and update it
    if ([string]::IsNullOrEmpty($mod.modName)) {
        $mod.modName = $modName
    }

    # Check if the mod is up to date
    if ($mod.modVersion -eq $latestVersion) {
        Write-Host "$modName is up to date."
        continue
    }
	Write-Host " $($versions.$modName) -> $latestVersion"

    # Get the download key and expires time
    $downloadInfo = Get-KeyAndExpireTime -modId $modId -fileId $latestFileId
	if ($downloadInfo -eq $null) {
        Write-Host "Failed to retrieve download info for $modName."
        continue
    }
	
    $key = $downloadInfo.key
    $expires = $downloadInfo.expires

    # Generate the download link using Nexus Mods API
    $downloadUrl = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId/files/$latestFileId/download_link.json?key=$key&expires=$expires"
    $downloadResponse = Invoke-RestMethod -Uri $downloadUrl -Headers $headers -Method Get
    $downloadLink = $downloadResponse.uri
	Write-Host "Download URL: $downloadUrl"

    # Download the mod
    $zipFilePath = "$modsDir\$modName.zip"
    Invoke-WebRequest -Uri $downloadLink -OutFile $zipFilePath

    # Create a directory for the mod if it doesn't exist
    #if (-Not (Test-Path -Path "$modsDir\$modName")) {
    #    New-Item -ItemType Directory -Path "$modsDir\$modName"
    #}

    # Extract then remove zip File
    Expand-Archive -Path "$zipFilePath" -DestinationPath "$modsDir" -Force
    Remove-Item $zipFilePath

    # Update the version information
	$mod.modVersion = $latestVersion
}

# Save the updated versions file
$mods | Export-Csv -Path $modsCsvPath -NoTypeInformation

Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');