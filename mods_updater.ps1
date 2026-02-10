# Get the directory of the script
$modsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Path to the configuration
$configPath = "$modsDir\config.json"
# Users can view their own API Keys by visiting https://www.nexusmods.com/users/myaccount?tab=api%20access.

# Load config.json
$config = Get-Content -Path $configPath | ConvertFrom-Json
$gameDomainName = $config.gameDomainName
$apiKey = $config.apiKey
$modTablePath = "$modsDir\$($config.modTableFile)"

# headers with api key for all nexus API calls
$headers = @{"apikey" = $config.apiKey }

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level,
        [string]$Message,
        [string]$ModId = ''
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $levelPadded = $Level.PadRight(5)
    $modTag = if ($ModId) { "[mod:$ModId]" } else { "[mod:-]" }
    Write-Host "[$timestamp] [$levelPadded] $modTag $Message"
}

# Load cookies from the JSON file
$cookiesJson = Get-Content -Path "$modsDir\cookies.json" | ConvertFrom-Json
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

# Function to get key and expire time from the download URL
function Get-KeyAndExpireTime {
    param (
        [string]$modId,
        [string]$fileId
    )
    Write-Log -Level 'INFO' -Message 'Requesting download token (Playwright)' -ModId $modId
    Write-Log -Level 'DEBUG' -Message "Args: $gameDomainName $modId $fileId"  -ModId $modId

    try {
        $tokenStart = [System.Diagnostics.Stopwatch]::StartNew()
        $rawOutput = .\nxm_key_getter.exe $gameDomainName $modId $fileId
        $tokenStart.Stop()
    }
    catch {
        Write-Log -Level 'ERROR' -Message 'Failed to execute Playwright script' -ModId $modId
        throw
    }

    if (-not $rawOutput) {
        Write-Log -Level 'ERROR' -Message 'Playwright returned empty output' -ModId $modId
        return $null
    }

    Write-Log -Level 'DEBUG' -Message "Raw output: $rawOutput" -ModId $modId
    # js should return null or completed token
    $nodeResult = $rawOutput | ConvertFrom-Json

    if (-not $nodeResult.key -or -not $nodeResult.expires) {
        Write-Log -Level 'ERROR' -Message 'Missing key or expires in Playwright result' -ModId $modId
        Write-Log -Level 'DEBUG' -Message 'Parsed object:' -ModId $modId
        $nodeResult | Format-List | Out-String | Write-Host
        return $null
    }

    $seconds = [Math]::Round($tokenStart.Elapsed.TotalSeconds, 1)
    Write-Log -Level 'INFO' -Message "Token acquired ($seconds s)" -ModId $modId

    return @{
        key     = $($nodeResult.key)
        expires = $($nodeResult.expires)
    }
    
}
	

# Load CSV data
$modList = Import-Csv -Path $modTablePath

# Loop through each mod, check for updates, download, and extract if needed
foreach ($mod in $modList) {
    $modId = $mod.modId
	$modStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	
    # Get the general infomation of the mod
    $generalInfoUrl = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId.json"    
    $generalInfoResponse = Invoke-RestMethod -Uri $generalInfoUrl -Headers $headers -Method Get
    $modName = $generalInfoResponse.name
 
    # Update the mod name
    $mod.modName = $modName

    # Check is the mod is available
    if (!$generalInfoResponse.available){
        Write-Log -Level 'INFO' -Message "This mod is no longer available"  -ModId $modId
        $modStopwatch.Stop()
        $elapsedMs = [Math]::Round($modStopwatch.Elapsed.TotalMilliseconds, 0)
        Write-Log -Level 'INFO' -Message "Done ($elapsedMs ms)" -ModId $modId
        Write-Host
        continue
    }

    Write-Log -Level 'INFO' -Message "$modName - start ..." -ModId $modId

    # Get the latest file mod information from Nexus Mods
    $latestModUrl = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId/files.json?category=main"
    $latestModResponse = Invoke-RestMethod -Uri $latestModUrl -Headers $headers -Method Get
    $latestModInfo = $latestModResponse.files | Sort-Object -Property "uploaded_timestamp" -Descending | Select-Object -First 1
    $latestVersion = $latestModInfo.version
    $latestFileId = $latestModInfo.file_id

    # Check if the mod is up to date
    if ($mod.modVersion -eq $latestVersion) {
        Write-Log -Level 'INFO' -Message "Status: up-to-date"  -ModId $modId
        $modStopwatch.Stop()
        $elapsedMs = [Math]::Round($modStopwatch.Elapsed.TotalMilliseconds, 0)
        Write-Log -Level 'INFO' -Message "Done ($elapsedMs ms)" -ModId $modId
        Write-Host
        continue
    }
    Write-Log -Level 'INFO' -Message "Update available: $($mod.modVersion) -> $latestVersion" -ModId $modId

    # Get the download key and expires time
    $downloadInfo = Get-KeyAndExpireTime -modId $modId -fileId $latestFileId
    if ($null -eq $downloadInfo) {
        Write-Log -Level 'ERROR' -Message "Failed to retrieve download info." -ModId $modId
        $modStopwatch.Stop()
        $elapsedMs = [Math]::Round($modStopwatch.Elapsed.TotalMilliseconds, 0)
        Write-Log -Level 'INFO' -Message "Done ($elapsedMs ms)" -ModId $modId        
        Write-Host
        continue
    }
	
    $key = $downloadInfo.key
    $expires = $downloadInfo.expires

    # Generate the download link using Nexus Mods API
    $downloadUrl = "https://api.nexusmods.com/v1/games/$gameDomainName/mods/$modId/files/$latestFileId/download_link.json?key=$key&expires=$expires"
    Write-Log -Level 'INFO' -Message 'Resolving download link' -ModId $modId    
    $downloadResponse = Invoke-RestMethod -Uri $downloadUrl -Headers $headers -Method Get
    $downloadLink = $downloadResponse.uri
    Write-Log -Level 'DEBUG' -Message "Download endpoint resolved: $downloadUrl"  -ModId $modId

    # Download the mod
    $zipFilePath = "$modsDir\$modName.zip"
    try {
        Invoke-WebRequest -Uri $downloadLink -OutFile $zipFilePath
        Write-Log -Level 'INFO' -Message 'Download completed' -ModId $modId
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Download failed: $($_.Exception.Message)" -ModId $modId
        $modStopwatch.Stop()
        $elapsedMs = [Math]::Round($modStopwatch.Elapsed.TotalMilliseconds, 0)
        Write-Log -Level 'INFO' -Message "Done ($elapsedMs ms)" -ModId $modId
        Write-Host
        continue
    }

    # Extract then remove zip File
    try {
        Expand-Archive -Path $zipFilePath -DestinationPath $modsDir -Force
        Remove-Item $zipFilePath
        Write-Log -Level 'INFO' -Message "Extracted successfully"  -ModId $modId
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Extraction failed: $($_.Exception.Message)" -ModId $modId
        $modStopwatch.Stop()
        $elapsedMs = [Math]::Round($modStopwatch.Elapsed.TotalMilliseconds, 0)
        Write-Log -Level 'INFO' -Message "Done ($elapsedMs ms)" -ModId $modId
        Write-Host
        continue
    }

    # update mod version
    $mod.modVersion = $latestVersion

    $modStopwatch.Stop()
    $elapsedSeconds = [Math]::Round($modStopwatch.Elapsed.TotalSeconds, 1)
    Write-Log -Level 'INFO' -Message "Done ($elapsedSeconds s)"  -ModId $modId
    Write-Host
}

# Save the updated versions file
$modList | Export-Csv -Path $modTablePath -NoTypeInformation

Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
