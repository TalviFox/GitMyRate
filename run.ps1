<#
.SYNOPSIS
    GitMyRate - Zero-Install GitHub Conversion Rates, Traffic Radar and Lifetime Analytics
    Hosted IEX Suite with Local DPAPI Hardware-Locked Encryption and Desktop Shortcut
.DESCRIPTION
    Pulls visitor traffic, release asset downloads, clone velocity, and audience conversion
    metrics from GitHub. Bypasses GitHub's 14-day deletion limit by archiving historical stats
    locally in %LOCALAPPDATA%\GitMyRate.
.EXAMPLE
    irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$TargetUsername,

  [string]$Token,
  [switch]$Force,
  [switch]$NoBrowser,
  [switch]$CreateShortcut,
  [switch]$Reset,
  [switch]$ResetToken
)

$ErrorActionPreference = 'Stop'

# Define persistent storage in LocalAppData
$appDataDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "GitMyRate"
if (-not (Test-Path -Path $appDataDir)) {
  New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
}

$configFile = Join-Path -Path $appDataDir -ChildPath "config.json"
$tokenFile = Join-Path -Path $appDataDir -ChildPath "token.enc"
$historyFile = Join-Path -Path $appDataDir -ChildPath "stats-history.json"
$yearlyFile = Join-Path -Path $appDataDir -ChildPath "yearly-traffic.json"
$reportFile = Join-Path -Path $appDataDir -ChildPath "dashboard.html"
$avatarIco = Join-Path -Path $appDataDir -ChildPath "avatar.ico"
$launcherPs1 = Join-Path -Path $appDataDir -ChildPath "launcher.ps1"
$migratedMarker = Join-Path -Path $appDataDir -ChildPath ".migrated"

$ScriptVersion = "1.2.0"

Write-Host ""
Write-Host "   ======================================================" -ForegroundColor Cyan
Write-Host "        GitMyRate v$ScriptVersion - Audience, Radar & Vitals     " -ForegroundColor White
Write-Host "   ======================================================" -ForegroundColor Cyan
Write-Host ""

# Handle --ResetToken switch
if ($ResetToken) {
  if (Test-Path $tokenFile) {
    Remove-Item $tokenFile -Force -ErrorAction SilentlyContinue
  }
  Write-Host "  [+] Stored GitHub token removed. You will be prompted for a new token." -ForegroundColor Green
}

# Handle --Reset switch
if ($Reset) {
  Write-Host "  [*] Wiping all GitMyRate local cache, history, and credentials..." -ForegroundColor Yellow
  if (Test-Path $appDataDir) {
    Remove-Item "$appDataDir\*" -Recurse -Force -ErrorAction SilentlyContinue
  }
  # Create migrated marker so it doesn't auto-resurrect old deleted credentials
  Set-Content -Path $migratedMarker -Value "migrated" -Encoding UTF8
  Write-Host "  [+] GitMyRate cache completely wiped from $appDataDir." -ForegroundColor Green
  return
}

# Load saved configuration if available
$config = @{}
if (Test-Path -Path $configFile) {
  try {
    $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json -AsHashtable
  }
  catch {
    $config = @{}
  }
}

# Auto-discover existing local dashboard data (Desktop migration - ONE TIME ONLY)
if (-not (Test-Path -Path $migratedMarker) -and -not (Test-Path -Path $configFile)) {
  $possibleLegacyDirs = @(
    (Get-Location).Path
  ) | Select-Object -Unique

  foreach ($ld in $possibleLegacyDirs) {
    if (Test-Path $ld) {
      # Check for legacy token
      $legToken = Join-Path $ld "github-token.txt"
      if ((Test-Path $legToken) -and (-not (Test-Path $tokenFile))) {
        $rawToken = (Get-Content $legToken -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($rawToken)) {
          $sec = ConvertTo-SecureString $rawToken -AsPlainText -Force
          $enc = ConvertFrom-SecureString $sec
          Set-Content -Path $tokenFile -Value $enc -Encoding UTF8
          Write-Host "  [+] Discovered and encrypted existing GitHub token from '$ld'." -ForegroundColor Green
        }
      }
      # Check for history
      $legHist = Join-Path $ld "stats-history.json"
      if ((Test-Path $legHist) -and (-not (Test-Path $historyFile))) {
        Copy-Item $legHist $historyFile -Force
        Write-Host "  [+] Migrated historical stats-history.json into GitMyRate." -ForegroundColor Green
      }
      # Check for yearly traffic
      $legYear = Join-Path $ld "yearly-traffic.json"
      if ((Test-Path $legYear) -and (-not (Test-Path $yearlyFile))) {
        Copy-Item $legYear $yearlyFile -Force
        Write-Host "  [+] Migrated yearly-traffic.json archive into GitMyRate." -ForegroundColor Green
      }
    }
  }
  Set-Content -Path $migratedMarker -Value "migrated" -Encoding UTF8
}

# Resolve Token (DPAPI-encrypted local storage)
$resolvedToken = ""
if (-not [string]::IsNullOrWhiteSpace($Token)) {
  $resolvedToken = $Token
  try {
    $sec = ConvertTo-SecureString $resolvedToken -AsPlainText -Force
    $enc = ConvertFrom-SecureString $sec
    Set-Content -Path $tokenFile -Value $enc -Encoding UTF8 -NoNewline
    Write-Host "  [+] New token encrypted and saved to Windows DPAPI storage." -ForegroundColor Green
  }
  catch {}
}
elseif (Test-Path -Path $tokenFile) {
  try {
    $rawEnc = Get-Content -Path $tokenFile -Raw
    $enc = if ($rawEnc) { $rawEnc.Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($enc)) {
      $sec = ConvertTo-SecureString $enc
      $resolvedToken = [System.Net.NetworkCredential]::new('', $sec).Password
    }
  }
  catch {
    Write-Host "  [!] Could not decrypt saved token. Continuing in public mode." -ForegroundColor DarkYellow
  }
}
else {
  # Check if legacy token exists in working directory
  $legacyTokenPath = Join-Path (Get-Location) "github-token.txt"
  if (Test-Path $legacyTokenPath) {
    $resolvedToken = (Get-Content $legacyTokenPath -Raw).Trim()
    try {
      $sec = ConvertTo-SecureString $resolvedToken -AsPlainText -Force
      $enc = ConvertFrom-SecureString $sec
      Set-Content -Path $tokenFile -Value $enc -Encoding UTF8 -NoNewline
      Write-Host "  [+] Imported and encrypted existing token into Windows DPAPI storage." -ForegroundColor Green
    }
    catch {}
  }
  else {
    Write-Host ""
    Write-Host "  [Key Setup] Optional GitHub Personal Access Token" -ForegroundColor Gray
    Write-Host "  - Private visitor views, clones, and referrers require a token." -ForegroundColor DarkGray
    Write-Host "  - Token will be encrypted with Windows DPAPI (locked to your user account) and masked." -ForegroundColor DarkGray
    Write-Host "  - Press Enter to skip and continue in public mode (60 requests/hr)." -ForegroundColor DarkGray
    Write-Host ""
    try {
      $secInput = Read-Host -Prompt "  Paste GitHub Token (hidden, press Enter to skip)" -AsSecureString
      $plain = [System.Net.NetworkCredential]::new('', $secInput).Password
            
      if (-not [string]::IsNullOrWhiteSpace($plain)) {
        $enc = ConvertFrom-SecureString $secInput
        Set-Content -Path $tokenFile -Value $enc -Encoding UTF8 -NoNewline
        $resolvedToken = $plain.Trim()
        Write-Host "  [+] Token encrypted and saved safely to LocalAppData." -ForegroundColor Green
      }
    }
    catch {}
  }
}

# Determine GitHub Username
$Username = $TargetUsername
if ([string]::IsNullOrWhiteSpace($Username)) {
  if ($config.ContainsKey('Username') -and -not [string]::IsNullOrWhiteSpace($config['Username'])) {
    $Username = $config['Username']
  }
  else {
    # Try to auto-detect from token if available
    $tokenUser = ""
    if (-not [string]::IsNullOrWhiteSpace($resolvedToken)) {
      try {
        $testAuth = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers @{
          "User-Agent"    = "GitMyRate-Analytics/1.0"
          "Accept"        = "application/vnd.github.v3+json"
          "Authorization" = "Bearer $resolvedToken"
        } -Method Get -TimeoutSec 4
        if ($testAuth -and -not [string]::IsNullOrWhiteSpace($testAuth.login)) {
          $tokenUser = $testAuth.login
        }
      }
      catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($tokenUser)) {
      $Username = $tokenUser
      Write-Host "  [+] Detected GitHub username from token: '$Username'" -ForegroundColor Green
    }
    else {
      $detectedUser = ""
      try {
        $detectedUser = (git config --get github.user) 2>$null
        if ([string]::IsNullOrWhiteSpace($detectedUser)) {
          $detectedUser = (git config --get user.name) 2>$null
        }
      }
      catch {}

      if (-not [string]::IsNullOrWhiteSpace($detectedUser)) {
        Write-Host -NoNewline "  ? Enter GitHub Username [default: $detectedUser]: " -ForegroundColor Yellow
        $inputUser = [Console]::ReadLine()
        $Username = if ([string]::IsNullOrWhiteSpace($inputUser)) { $detectedUser } else { $inputUser.Trim() }
      }
      else {
        while ([string]::IsNullOrWhiteSpace($Username)) {
          Write-Host -NoNewline "  ? Enter GitHub Username: " -ForegroundColor Yellow
          $Username = [Console]::ReadLine()
          if ($null -ne $Username) { $Username = $Username.Trim() }
        }
      }
    }
  }
}

# Save resolved username
$config['Username'] = $Username
$config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

# Setup GitHub headers and validate
$headers = @{
  "User-Agent" = "GitMyRate-Analytics/1.0"
  "Accept"     = "application/vnd.github.v3+json"
}
$isAuthenticated = $false
if (-not [string]::IsNullOrWhiteSpace($resolvedToken)) {
  $headers["Authorization"] = "Bearer $resolvedToken"
  try {
    $rateCheck = Invoke-RestMethod -Uri "https://api.github.com/rate_limit" -Headers $headers -Method Get -TimeoutSec 6
    if ($rateCheck.rate.limit -gt 60) {
      $isAuthenticated = $true
      Write-Host "  [+] Authenticated mode (GitHub Token active - $($rateCheck.rate.remaining)/$($rateCheck.rate.limit) req remaining)" -ForegroundColor Green
    }
    else {
      Write-Host "  [i] Token recognized but rate limit is standard public limit." -ForegroundColor Yellow
      $isAuthenticated = $true
    }
  }
  catch {
    Write-Host "  [!] Token provided failed GitHub authentication: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      Tip: Run with -ResetToken or -Token 'ghp_...' to set a fresh token." -ForegroundColor Yellow
    $headers.Remove("Authorization")
    $isAuthenticated = $false
  }
}
else {
  Write-Host "  [i] Running in public mode (Rate Limit: 60 req/hr)" -ForegroundColor DarkGray
}

# Daily cache check
$alreadyScannedToday = $false
if ((Test-Path -Path $reportFile) -and -not $Force) {
  $lastScanTime = (Get-Item -Path $reportFile).LastWriteTime
  if ($lastScanTime.Date -eq (Get-Date).Date) {
    $alreadyScannedToday = $true
  }
}

if ($alreadyScannedToday -and -not $Force -and -not $CreateShortcut) {
  Write-Host "  [i] Already scanned GitHub today at $($lastScanTime.ToString('h:mm tt'))." -ForegroundColor Yellow
  Write-Host "      GitHub traffic stats (views/clones) only batch once every 24h at 00:00 UTC." -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "  [Enter]  Open cached dashboard instantly" -ForegroundColor Cyan
  Write-Host "  [R]      Force re-scan GitHub now" -ForegroundColor Gray
  Write-Host ""

  $shouldRescan = $false
  $canReadKeys = $false
  try {
    if ([Environment]::UserInteractive) {
      $canReadKeys = [Console]::KeyAvailable -or $true
    }
  }
  catch {
    $canReadKeys = $false
  }

  if ($canReadKeys) {
    Write-Host -NoNewline "  Auto-opening cached dashboard in " -ForegroundColor DarkGray
    for ($sec = 4; $sec -gt 0; $sec--) {
      Write-Host -NoNewline "$sec... " -ForegroundColor DarkGray
      for ($sub = 0; $sub -lt 10; $sub++) {
        if ([Console]::KeyAvailable) {
          $key = [Console]::ReadKey($true)
          if ($key.Key -eq [ConsoleKey]::R -or $key.Key -eq [ConsoleKey]::Y) {
            $shouldRescan = $true
            break
          }
          if ($key.Key -eq [ConsoleKey]::Enter -or $key.Key -eq [ConsoleKey]::Spacebar) {
            $shouldRescan = $false
            break
          }
        }
        Start-Sleep -Milliseconds 100
      }
      if ($shouldRescan) { break }
    }
    Write-Host ""
  }
  else {
    $shouldRescan = $false
  }

  if (-not $shouldRescan) {
    Write-Host "  [+] Opening cached dashboard in browser..." -ForegroundColor Green
    if (-not $NoBrowser) {
      Start-Process -FilePath $reportFile
    }
    return
  }
}

Write-Host "  [1/4] Fetching profile for '$Username'..." -ForegroundColor Cyan
try {
  $user = Invoke-RestMethod -Uri "https://api.github.com/users/$Username" -Headers $headers -Method Get
}
catch {
  Write-Host "  [X] Failed to fetch GitHub user '$Username': $($_.Exception.Message)" -ForegroundColor Red
  return
}

# Fetch Repositories
Write-Host "  [2/4] Fetching public repositories..." -ForegroundColor Cyan
$repos = [System.Collections.Generic.List[PSObject]]::new()
$page = 1
while ($true) {
  $url = "https://api.github.com/users/$Username/repos?per_page=100&page=$page&sort=updated"
  try {
    $batch = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    if ($null -eq $batch -or $batch.Count -eq 0) { break }
    foreach ($item in $batch) { $repos.Add($item) }
    if ($batch.Count -lt 100) { break }
    $page++
  }
  catch {
    Write-Host "  [!] Error fetching repos page ${page}: $($_.Exception.Message)" -ForegroundColor Yellow
    break
  }
}

# License detection helper
function Get-DetailedLicense {
  param([string]$owner, [string]$repoName, [string]$spdx)
  $candidates = @("LICENSE", "LICENSE.md", "license", "license.txt")
  foreach ($c in $candidates) {
    try {
      $raw = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$owner/$repoName/main/$c" -Headers $headers -Method Get
      if ($raw -match "PolyForm Noncommercial") { return "PolyForm Noncommercial" }
      if ($raw -match "PolyForm Perimeter") { return "PolyForm Perimeter" }
      if ($raw -match "PolyForm Strict") { return "PolyForm Strict" }
      if ($raw -match "PolyForm Small Business") { return "PolyForm Small Business" }
      if ($raw -match "PolyForm") { return "PolyForm" }
      if ($raw -match "CC BY-NC 4.0" -or $raw -match "Attribution-NonCommercial 4.0") { return "CC BY-NC 4.0" }
      if ($raw -match "Creative Commons") { return "Creative Commons" }
      if ($raw -match "MIT License") { return "MIT" }
    }
    catch {}
  }
  if ($spdx -and $spdx -ne "NOASSERTION") { return $spdx } else { return "Custom" }
}

# Load existing permanent yearly archive
$archive = @{}
if (Test-Path -Path $yearlyFile) {
  try {
    $loaded = Get-Content -Path $yearlyFile -Raw | ConvertFrom-Json
    foreach ($prop in $loaded.psobject.Properties) {
      $archive[$prop.Name] = $prop.Value
    }
  }
  catch {}
}

# Initialize 14-day rolling timeline
$today = (Get-Date).Date
$timelineDays = [System.Collections.Generic.List[string]]::new()
for ($i = 13; $i -ge 0; $i--) {
  $timelineDays.Add($today.AddDays(-$i).ToString("yyyy-MM-dd"))
}

# Analyze Repositories
Write-Host "  [3/4] Analyzing $($repos.Count) repositories (releases, downloads, clones, views)..." -ForegroundColor Cyan
$analyzedRepos = [System.Collections.Generic.List[PSObject]]::new()
$allReleases = [System.Collections.Generic.List[PSObject]]::new()
$trafficReferrers = [System.Collections.Generic.List[PSObject]]::new()
$dailyTrafficByRepo = @{}

$totalStars = 0
$totalDownloads = 0
$totalForks = 0
$total14DayViews = 0
$total14DayClones = 0
$total14DayUniqueClones = 0
$trafficPermissionBlocked = $false

foreach ($repo in $repos) {
  $repoName = $repo.name
  $stars = [int]$repo.stargazers_count
  $forks = [int]$repo.forks_count
  $issues = [int]$repo.open_issues_count
  $isFork = [bool]$repo.fork

  $totalStars += $stars
  $totalForks += $forks

  # Release Downloads
  $repoDownloads = 0
  $releaseCount = 0
  $latestReleaseTag = ""
  try {
    $releasesUrl = "https://api.github.com/repos/$Username/$repoName/releases?per_page=50"
    $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get
    if ($releases -and $releases.Count -gt 0) {
      $releaseCount = $releases.Count
      $latestReleaseTag = $releases[0].tag_name
      foreach ($rel in $releases) {
        $relDownloads = 0
        $assetList = [System.Collections.Generic.List[PSObject]]::new()
        if ($rel.assets) {
          foreach ($asset in $rel.assets) {
            $dlCount = [int]$asset.download_count
            $relDownloads += $dlCount
            $assetList.Add([PSCustomObject]@{
                name      = $asset.name
                downloads = $dlCount
                size      = [int]$asset.size
              })
          }
        }
        $repoDownloads += $relDownloads
        $pubDate = if ($rel.published_at) { ([DateTime]::Parse($rel.published_at)).ToString("yyyy-MM-dd") } else { "" }
        $allReleases.Add([PSCustomObject]@{
            repo      = $repo.name
            tag       = $rel.tag_name
            name      = if ($rel.name) { $rel.name } else { $rel.tag_name }
            date      = $pubDate
            downloads = $relDownloads
            assets    = $assetList
          })
      }
    }
  }
  catch {}
  $totalDownloads += $repoDownloads

  # Check 14-day private traffic/referrers/clones if authenticated
  $repo14DayViews = 0
  $repo14DayUniques = 0
  $repo14DayClones = 0
  $repo14DayUniqueClones = 0
  $repoDailyData = @{}
  foreach ($day in $timelineDays) {
    $repoDailyData[$day] = @{ views = 0; uniques = 0 }
  }

  if ($isAuthenticated -and -not $isFork) {
    try {
      $viewsData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$($repo.name)/traffic/views" -Headers $headers -Method Get
      $repo14DayViews = [int]$viewsData.count
      $repo14DayUniques = [int]$viewsData.uniques
      $total14DayViews += $repo14DayViews

      if ($viewsData.views) {
        foreach ($v in $viewsData.views) {
          $dayKey = if ($v.timestamp.Length -ge 10) { $v.timestamp.Substring(0, 10) } else { ([DateTime]::Parse($v.timestamp)).ToUniversalTime().ToString("yyyy-MM-dd") }
          $vCount = [int]$v.count
          $vUniq = [int]$v.uniques

          $repoDailyData[$dayKey] = @{
            views   = $vCount
            uniques = $vUniq
          }

          # Merge into permanent yearly archive
          if (-not $archive.ContainsKey($dayKey)) {
            $archive[$dayKey] = [PSCustomObject]@{
              views   = [PSCustomObject]@{}
              uniques = [PSCustomObject]@{}
            }
          }
          $archive[$dayKey].views | Add-Member -MemberType NoteProperty -Name $repo.name -Value $vCount -Force
          $archive[$dayKey].uniques | Add-Member -MemberType NoteProperty -Name $repo.name -Value $vUniq -Force
        }
      }

      $refData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$($repo.name)/traffic/popular/referrers" -Headers $headers -Method Get
      if ($refData) {
        foreach ($ref in $refData) {
          $trafficReferrers.Add([PSCustomObject]@{
              Repo     = $repo.name
              Referrer = $ref.referrer
              Count    = $ref.count
              Uniques  = $ref.uniques
            })
        }
      }

      $clonesData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$($repo.name)/traffic/clones" -Headers $headers -Method Get
      $repo14DayClones = [int]$clonesData.count
      $repo14DayUniqueClones = [int]$clonesData.uniques
      $total14DayClones += $repo14DayClones
      $total14DayUniqueClones += $repo14DayUniqueClones

      if ($clonesData.clones) {
        foreach ($c in $clonesData.clones) {
          $dayKey = if ($c.timestamp.Length -ge 10) { $c.timestamp.Substring(0, 10) } else { ([DateTime]::Parse($c.timestamp)).ToUniversalTime().ToString("yyyy-MM-dd") }
          $cCount = [int]$c.count
          if (-not $archive.ContainsKey($dayKey)) {
            $archive[$dayKey] = [PSCustomObject]@{
              views   = [PSCustomObject]@{}
              uniques = [PSCustomObject]@{}
              clones  = [PSCustomObject]@{}
            }
          }
          if (-not $archive[$dayKey].clones) {
            $archive[$dayKey] | Add-Member -MemberType NoteProperty -Name clones -Value ([PSCustomObject]@{}) -Force
          }
          $archive[$dayKey].clones | Add-Member -MemberType NoteProperty -Name $repo.name -Value $cCount -Force
        }
      }
    }
    catch {
      if ($_.ToString() -match "403" -or $_.ToString() -match "Resource not accessible") {
        $trafficPermissionBlocked = $true
      }
    }
  }

  $dailyTrafficByRepo[$repo.name] = $repoDailyData

  # Format size
  $sizeKb = [int]$repo.size
  $formattedSize = if ($sizeKb -gt 1024) { "{0:N1} MB" -f ($sizeKb / 1024) } else { "$sizeKb KB" }

  # Detect license
  $rawSpdx = if ($repo.license -and $repo.license.spdx_id) { $repo.license.spdx_id } else { "" }
  $detectedLicense = Get-DetailedLicense -owner $Username -repoName $repo.name -spdx $rawSpdx

  # Normalize Language
  $lang = if ($repo.language) { $repo.language } else { "General" }
  if ($lang -eq "PowerShell") { $lang = "PoSH" }

  # Detect Today's activity
  $repoTodayViews = 0
  $repoTodayUniques = 0
  $localTodayKey = (Get-Date).ToString("yyyy-MM-dd")
  $utcTodayKey = ([DateTime]::UtcNow).ToString("yyyy-MM-dd")
  if ($repoDailyData.ContainsKey($localTodayKey)) {
    $repoTodayViews = [int]$repoDailyData[$localTodayKey].views
    $repoTodayUniques = [int]$repoDailyData[$localTodayKey].uniques
  } elseif ($repoDailyData.ContainsKey($utcTodayKey)) {
    $repoTodayViews = [int]$repoDailyData[$utcTodayKey].views
    $repoTodayUniques = [int]$repoDailyData[$utcTodayKey].uniques
  }

  $analyzedRepos.Add([PSCustomObject]@{
      Name               = $repo.name
      FullName           = $repo.full_name
      Description        = if ($repo.description) { $repo.description } else { "No description provided." }
      HtmlUrl            = $repo.html_url
      Language           = $lang
      Stars              = $stars
      Forks              = $forks
      Watchers           = [int]$repo.watchers_count
      OpenIssues         = $issues
      IsFork             = $isFork
      Downloads          = $repoDownloads
      ReleaseCount       = $releaseCount
      LatestReleaseTag   = $latestReleaseTag
      Topics             = if ($repo.topics) { @($repo.topics) } else { @() }
      CreatedAt          = $repo.created_at
      PushedAt           = $repo.pushed_at
      SizeFormatted      = $formattedSize
      License            = $detectedLicense
      Views14Days        = $repo14DayViews
      Uniques14Days      = $repo14DayUniques
      ViewsToday         = $repoTodayViews
      UniquesToday       = $repoTodayUniques
      Clones14Days       = $repo14DayClones
      UniqueClones14Days = $repo14DayUniqueClones
    })
}

if ($trafficPermissionBlocked) {
  Write-Host "  [!] Note: Traffic metrics returned 403 on some repositories." -ForegroundColor DarkYellow
  Write-Host "      Ensure your token has repository Administration/Metadata read permissions." -ForegroundColor DarkGray
}

# Save permanent yearly archive to disk
$archive | ConvertTo-Json -Depth 5 | Set-Content -Path $yearlyFile -Encoding UTF8

# Attach AllTime cumulative traffic to analyzed repositories from archive
foreach ($r in $analyzedRepos) {
  $cumV = 0
  $cumU = 0
  foreach ($dKey in $archive.Keys) {
    if ($archive[$dKey].views -and $archive[$dKey].views.psobject.Properties[$r.Name]) {
      $cumV += [int]$archive[$dKey].views.psobject.Properties[$r.Name].Value
    }
    if ($archive[$dKey].uniques -and $archive[$dKey].uniques.psobject.Properties[$r.Name]) {
      $cumU += [int]$archive[$dKey].uniques.psobject.Properties[$r.Name].Value
    }
  }
  $allV = [Math]::Max([int]$r.Views14Days, $cumV)
  $allU = [Math]::Max([int]$r.Uniques14Days, $cumU)
  $r | Add-Member -MemberType NoteProperty -Name "AllTimeViews" -Value $allV -Force
  $r | Add-Member -MemberType NoteProperty -Name "AllTimeUniques" -Value $allU -Force
}

# Build Rolling 14-day list
$chartRolling14List = [System.Collections.Generic.List[PSObject]]::new()
foreach ($day in $timelineDays) {
  $sumViews = 0
  $sumUniques = 0
  $dObj = [DateTime]::Parse($day)
  $label = $dObj.ToString("MMM dd")

  foreach ($rName in $dailyTrafficByRepo.Keys) {
    $rDay = $dailyTrafficByRepo[$rName][$day]
    if ($rDay) {
      $sumViews += $rDay.views
      $sumUniques += $rDay.uniques
    }
  }

  $chartRolling14List.Add([PSCustomObject]@{
      date    = $day
      label   = $label
      views   = $sumViews
      uniques = $sumUniques
    })
}

# Build Permanent Cumulative Year Timeline
$allDatesSet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($k in $archive.Keys) { $allDatesSet.Add($k) | Out-Null }
foreach ($rel in $allReleases) {
  if ($rel.date) { $allDatesSet.Add($rel.date) | Out-Null }
}
$sortedDates = $allDatesSet | Sort-Object

$chartCumulativeList = [System.Collections.Generic.List[PSObject]]::new()
$runningCombinedViews = 0
$runningCombinedUniques = 0
$runningCombinedDownloads = 0

$runningPerRepoViews = @{}
$runningPerRepoUniques = @{}
$runningPerRepoDownloads = @{}
foreach ($repo in $repos) {
  $runningPerRepoViews[$repo.name] = 0
  $runningPerRepoUniques[$repo.name] = 0
  $runningPerRepoDownloads[$repo.name] = 0
}

$releasesByDate = @{}
foreach ($rel in $allReleases) {
  if ($rel.date) {
    if (-not $releasesByDate.ContainsKey($rel.date)) {
      $releasesByDate[$rel.date] = [System.Collections.Generic.List[PSObject]]::new()
    }
    $releasesByDate[$rel.date].Add($rel)
  }
}

foreach ($dateKey in $sortedDates) {
  $dayViewsCombined = 0
  $dayUniquesCombined = 0
  $dayDownloadsCombined = 0

  $dayRepoViews = @{}
  $dayRepoUniques = @{}
  $dayRepoDownloads = @{}
  $dayCumRepoViews = @{}
  $dayCumRepoUniques = @{}
  $dayCumRepoDownloads = @{}

  foreach ($repo in $repos) {
    $dayRepoViews[$repo.name] = 0
    $dayRepoUniques[$repo.name] = 0
    $dayRepoDownloads[$repo.name] = 0
  }

  if ($archive.ContainsKey($dateKey)) {
    if ($archive[$dateKey].views) {
      foreach ($prop in $archive[$dateKey].views.psobject.Properties) {
        $val = [int]$prop.Value
        $dayViewsCombined += $val
        $dayRepoViews[$prop.Name] = $val
        $runningPerRepoViews[$prop.Name] = ([int]$runningPerRepoViews[$prop.Name]) + $val
      }
    }
    if ($archive[$dateKey].uniques) {
      foreach ($prop in $archive[$dateKey].uniques.psobject.Properties) {
        $val = [int]$prop.Value
        $dayUniquesCombined += $val
        $dayRepoUniques[$prop.Name] = $val
        $runningPerRepoUniques[$prop.Name] = ([int]$runningPerRepoUniques[$prop.Name]) + $val
      }
    }
  }

  if ($releasesByDate.ContainsKey($dateKey)) {
    foreach ($rel in $releasesByDate[$dateKey]) {
      $dl = [int]$rel.downloads
      $dayDownloadsCombined += $dl
      $dayRepoDownloads[$rel.repo] = ([int]$dayRepoDownloads[$rel.repo]) + $dl
      $runningPerRepoDownloads[$rel.repo] = ([int]$runningPerRepoDownloads[$rel.repo]) + $dl
    }
  }

  foreach ($repo in $repos) {
    $dayCumRepoViews[$repo.name] = [int]$runningPerRepoViews[$repo.name]
    $dayCumRepoUniques[$repo.name] = [int]$runningPerRepoUniques[$repo.name]
    $dayCumRepoDownloads[$repo.name] = [int]$runningPerRepoDownloads[$repo.name]
  }

  $runningCombinedViews += $dayViewsCombined
  $runningCombinedUniques += $dayUniquesCombined
  $runningCombinedDownloads += $dayDownloadsCombined

  $chartCumulativeList.Add([PSCustomObject]@{
      date               = $dateKey
      label              = ([DateTime]::Parse($dateKey)).ToString("MMM dd")
      month              = ([DateTime]::Parse($dateKey)).ToString("MMM yyyy")
      dayViews           = $dayViewsCombined
      dayUniques         = $dayUniquesCombined
      dayDownloads       = $dayDownloadsCombined
      cumViews           = $runningCombinedViews
      cumUniques         = $runningCombinedUniques
      cumDownloads       = $runningCombinedDownloads
      byRepoDayViews     = $dayRepoViews
      byRepoDayUniques   = $dayRepoUniques
      byRepoDayDownloads = $dayRepoDownloads
      byRepoCumViews     = $dayCumRepoViews
      byRepoCumUniques   = $dayCumRepoUniques
      byRepoCumDownloads = $dayCumRepoDownloads
    })
}

# ----------------- JSON History Tracking -----------------
$history = @()
if (Test-Path -Path $historyFile) {
  try {
    $jsonRaw = Get-Content -Path $historyFile -Raw
    if ($jsonRaw -and $jsonRaw.Trim()) {
      $parsed = $jsonRaw | ConvertFrom-Json
      if ($parsed -is [System.Array]) { $history = $parsed } else { $history = @($parsed) }
    }
  }
  catch {
    $history = @()
  }
}

# Fallback: if live traffic returned 0 because of unauthenticated mode, recover previous known metrics
if ($total14DayViews -eq 0 -and $history.Count -gt 0) {
  $lastSnap = $history[-1]
  if ($lastSnap.totalViews14d -gt 0) {
    $total14DayViews = [int]$lastSnap.totalViews14d
    $total14DayClones = [int]$lastSnap.totalClones14d
    $total14DayUniqueClones = [int]$lastSnap.totalUniqueClones14d
  }
}

$deltaStars = 0
$deltaDownloads = 0
if ($history.Count -gt 0) {
  $lastSnap = $history[-1]
  $deltaStars = [Math]::Max(0, $totalStars - [int]$lastSnap.totalStars)
  $deltaDownloads = [Math]::Max(0, $totalDownloads - [int]$lastSnap.totalDownloads)
}

$currentSnapshot = [PSCustomObject]@{
  timestamp            = (Get-Date).ToString("o")
  dateDisplay          = (Get-Date).ToString("yyyy-MM-dd HH:mm")
  totalStars           = $totalStars
  totalDownloads       = $totalDownloads
  totalForks           = $totalForks
  totalRepos           = $analyzedRepos.Count
  totalViews14d        = $total14DayViews
  totalClones14d       = $total14DayClones
  totalUniqueClones14d = $total14DayUniqueClones
  yearCumulativeViews  = $runningCombinedViews
  repos                = ($analyzedRepos | Select-Object Name, Stars, Downloads, Forks, Views14Days, AllTimeViews, AllTimeUniques, License, Language)
}

$historyList = [System.Collections.Generic.List[PSObject]]::new()
foreach ($item in $history) { $historyList.Add($item) }

$todayDateStr = (Get-Date).ToString("yyyy-MM-dd")
$lastSnapDateStr = ""
if ($history.Count -gt 0 -and $history[-1].timestamp) {
  try {
    $lastSnapDateStr = ([DateTime]::Parse($history[-1].timestamp)).ToString("yyyy-MM-dd")
  }
  catch {}
}

if ($lastSnapDateStr -eq $todayDateStr -and $historyList.Count -gt 0) {
  $historyList[$historyList.Count - 1] = $currentSnapshot
}
else {
  $historyList.Add($currentSnapshot)
}

if ($historyList.Count -gt 300) {
  $historyList = [System.Collections.Generic.List[PSObject]]::new($historyList[($historyList.Count - 300)..($historyList.Count - 1)])
}

$historyJson = if ($historyList.Count -eq 1) { "[ " + ($historyList[0] | ConvertTo-Json -Depth 5) + " ]" } else { $historyList | ConvertTo-Json -Depth 5 }
Set-Content -Path $historyFile -Value $historyJson -Encoding UTF8
$historyCompressed = if ($historyList.Count -eq 1) { "[ " + ($historyList[0] | ConvertTo-Json -Depth 5 -Compress) + " ]" } else { $historyList | ConvertTo-Json -Depth 5 -Compress }

# Handle Avatar & Desktop Shortcut
$avatarUrl = $user.avatar_url
$avatarDataUri = $avatarUrl

try {
  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add("User-Agent", "GitMyRate-Setup")
  $avatarBytes = $wc.DownloadData($avatarUrl)
  $wc.Dispose()

  $b64 = [Convert]::ToBase64String($avatarBytes)
  $avatarDataUri = "data:image/png;base64,$b64"

  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $ms = [System.IO.MemoryStream]::new($avatarBytes)
    $srcBmp = [System.Drawing.Bitmap]::FromStream($ms)

    # Build 5-Resolution 32-bit TrueColor ARGB ICO (32, 48, 64, 128 DIB + 256 PNG)
    $sizes = @(32, 48, 64, 128, 256)
    $frames = [System.Collections.Generic.List[byte[]]]::new()

    foreach ($sz in $sizes) {
      $thumb = New-Object System.Drawing.Bitmap $sz, $sz, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
      $gt = [System.Drawing.Graphics]::FromImage($thumb)
      $gt.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $gt.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $gt.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $gt.DrawImage($srcBmp, 0, 0, $sz, $sz)
      $gt.Dispose()

      if ($sz -eq 256) {
        $pMs = New-Object System.IO.MemoryStream
        $thumb.Save($pMs, [System.Drawing.Imaging.ImageFormat]::Png)
        $frames.Add($pMs.ToArray())
        $pMs.Dispose()
      }
      else {
        $rect = New-Object System.Drawing.Rectangle 0, 0, $sz, $sz
        $bData = $thumb.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = $bData.Stride
        $px = New-Object byte[] ($stride * $sz)
        [System.Runtime.InteropServices.Marshal]::Copy($bData.Scan0, $px, 0, $px.Length)
        $thumb.UnlockBits($bData)

        $dib = New-Object byte[] ($stride * $sz)
        for ($y = 0; $y -lt $sz; $y++) {
          [Array]::Copy($px, ($sz - 1 - $y) * $stride, $dib, $y * $stride, $stride)
        }
        $mask = New-Object byte[] ([int]([Math]::Ceiling($sz / 32.0) * 4 * $sz))

        $fMs = New-Object System.IO.MemoryStream
        $fBw = New-Object System.IO.BinaryWriter $fMs
        $fBw.Write([UInt32]40)
        $fBw.Write([Int32]$sz)
        $fBw.Write([Int32]($sz * 2))
        $fBw.Write([UInt16]1)
        $fBw.Write([UInt16]32)
        $fBw.Write([UInt32]0)
        $fBw.Write([UInt32]($dib.Length + $mask.Length))
        $fBw.Write([Int32]0)
        $fBw.Write([Int32]0)
        $fBw.Write([UInt32]0)
        $fBw.Write([UInt32]0)
        $fBw.Write($dib)
        $fBw.Write($mask)
        $fBw.Flush()
        $frames.Add($fMs.ToArray())
        $fBw.Dispose()
        $fMs.Dispose()
      }
      $thumb.Dispose()
    }
    $srcBmp.Dispose()
    $ms.Dispose()

    $icoMs = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $icoMs
    $bw.Write([UInt16]0) # Reserved
    $bw.Write([UInt16]1) # Icon type
    $bw.Write([UInt16]$sizes.Count)

    $offset = 6 + (16 * $sizes.Count)
    for ($i = 0; $i -lt $sizes.Count; $i++) {
      $sz = $sizes[$i]
      $bSz = if ($sz -eq 256) { [Byte]0 } else { [Byte]$sz }
      $dataLen = $frames[$i].Length
      $bw.Write($bSz)
      $bw.Write($bSz)
      $bw.Write([Byte]0)
      $bw.Write([Byte]0)
      $bw.Write([UInt16]1)
      $bw.Write([UInt16]32)
      $bw.Write([UInt32]$dataLen)
      $bw.Write([UInt32]$offset)
      $offset += $dataLen
    }
    for ($i = 0; $i -lt $sizes.Count; $i++) {
      $bw.Write($frames[$i])
    }
    $bw.Flush()

    $icoBytes = $icoMs.ToArray()
    $bw.Dispose()
    $icoMs.Dispose()

    # Save primary avatar.ico + content-hashed filename to bypass Windows Explorer's locked IconCache.db
    [System.IO.File]::WriteAllBytes($avatarIco, $icoBytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $icoHash = [BitConverter]::ToString($sha.ComputeHash($icoBytes)).Replace("-", "").Substring(0, 8).ToLower()
    $sha.Dispose()
    Get-ChildItem -Path $appDataDir -Filter "avatar-*.ico" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $avatarIco = Join-Path -Path $appDataDir -ChildPath "avatar-$icoHash.ico"
    [System.IO.File]::WriteAllBytes($avatarIco, $icoBytes)
  }
  catch {}
}
catch {}

# Create / Update Desktop Shortcut & Offline Launcher
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutFile = Join-Path -Path $desktopPath -ChildPath "GitMyRate ($Username).lnk"

$launcherContent = @"
try {
    if ([System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
        return
    }
} catch {
    Write-Host "  [-] Live sync encountered an error: `$_" -ForegroundColor Yellow
}

`$report = "$reportFile"
if (Test-Path `$report) {
    Write-Host "  [*] Opening offline cached dashboard..." -ForegroundColor Cyan
    Start-Process -FilePath `$report
} else {
    Write-Host "  [-] No cached dashboard found at `$report" -ForegroundColor Red
}
"@
Set-Content -Path $launcherPs1 -Value $launcherContent -Encoding UTF8

try {
  if (Test-Path $shortcutFile) {
    Remove-Item $shortcutFile -Force -ErrorAction SilentlyContinue
  }
  $wsh = New-Object -ComObject WScript.Shell
  $sc = $wsh.CreateShortcut($shortcutFile)
  $sc.TargetPath = "powershell.exe"
  $sc.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$launcherPs1`""
  $sc.Description = "GitMyRate - GitHub Audience & Conversion Rates Dashboard"
  $sc.WorkingDirectory = $appDataDir
  $targetIcon = if (Test-Path $avatarIco) {
    $avatarIco
  } else {
    $existingIcon = Get-ChildItem -Path $appDataDir -Filter "avatar-*.ico" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingIcon) { $existingIcon.FullName } else { $null }
  }
  if ($targetIcon) {
    $sc.IconLocation = "$targetIcon,0"
  } else {
    $sc.IconLocation = "$env:SystemRoot\System32\shell32.dll,22"
  }
  $sc.Save()
  Start-Process -FilePath "$env:SystemRoot\System32\ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
  Write-Host "  [+] Desktop Shortcut saved: 'GitMyRate ($Username).lnk'" -ForegroundColor Green
}
catch {}

Write-Host "  [4/4] Rendering GitMyRate HTML Dashboard..." -ForegroundColor Cyan

# Prepare radar queries (exclude forks so generic repos like android/winget-pkgs don't pollute queries)
$searchTerms = @($analyzedRepos | Where-Object { -not $_.IsFork } | ForEach-Object { $_.Name }) + @($Username) | Select-Object -Unique
$radarQueryQuoted = ($searchTerms | ForEach-Object { "%22" + [System.Web.HttpUtility]::UrlEncode($_) + "%22" }) -join "+OR+"
$radarQueryPlain = ($searchTerms | ForEach-Object { [System.Web.HttpUtility]::UrlEncode($_) }) -join "+OR+"
$radarTermsDisplay = ($searchTerms | ForEach-Object { "<code>$_</code>" }) -join ", "

# Prepare Referrers / Traffic Block
$trafficHtml = ""
if ($isAuthenticated) {
  $refRows = ""
  if ($trafficReferrers.Count -gt 0) {
    foreach ($tr in $trafficReferrers) {
      $refRows += "<tr><td><strong>$($tr.Repo)</strong></td><td>$($tr.Referrer)</td><td>$($tr.Count)</td><td>$($tr.Uniques)</td></tr>"
    }
  }
  else {
    $refRows = "<tr><td colspan='4' style='color:var(--text-muted); text-align:center;'>No external referral domains detected in the last 14 days.</td></tr>"
  }

  $cloneRows = ""
  $reposWithClones = $analyzedRepos | Where-Object { -not $_.IsFork } | Sort-Object -Descending Clones14Days
  foreach ($r in $reposWithClones) {
    $allTimeViewsDisplay = if ($r.AllTimeViews -gt $r.Views14Days) { "$($r.AllTimeViews) total" } else { "$($r.Views14Days) views" }
    $cloneRows += "<tr><td><strong>$($r.Name)</strong></td><td style='color:#34d399; font-weight:700;'>$($r.Clones14Days)</td><td style='color:var(--text-muted);'>$($r.Views14Days) (14d) &bull; $allTimeViewsDisplay</td></tr>"
  }

  $trafficHtml = @"
    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1.25rem; margin-top: 1.5rem;">
      <div class="traffic-box" style="margin-top: 0;">
        <div class="traffic-title">&#x1F4C8; Inbound Referrers (Past 14 Days)</div>
        <table class="traffic-table">
          <thead>
            <tr><th>Repository</th><th>Referrer Source</th><th>Total Views</th><th>Unique Visitors</th></tr>
          </thead>
          <tbody>$refRows</tbody>
        </table>
      </div>

      <div class="traffic-box" style="margin-top: 0;">
        <div class="traffic-title" style="color: #34d399;">&#x1F680; Git Clones &amp; Adoption (Past 14 Days: $total14DayClones total)</div>
        <table class="traffic-table">
          <thead>
            <tr><th>Repository</th><th>14d Clones</th><th>Views (14d &bull; Lifetime)</th></tr>
          </thead>
          <tbody>$cloneRows</tbody>
        </table>
      </div>
    </div>
"@
}
else {
  $trafficHtml = @"
    <div class="traffic-box" style="display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.75rem; margin-top: 1.5rem;">
      <div style="font-size: 0.84rem; color: var(--text-muted); line-height: 1.4;">
        <strong style="color: #f1f5f9;">Unlock Private Referrers, Clones &amp; Visitor Retention:</strong><br>
        Run <code>irm ... | iex</code> and paste a fine-grained GitHub token (Administration: Read-only) to unlock inbound domains and human dev clone tracking.
      </div>
      <a class="btn" style="font-size: 0.78rem; padding: 0.4rem 0.8rem;" href="https://github.com/settings/tokens" target="_blank" rel="noopener noreferrer">Get Token &nearr;</a>
    </div>
"@
}

$deltaStarsHtml = if ($deltaStars -gt 0) { "<span class='kpi-delta'>+$deltaStars</span>" } else { "" }
$deltaDownloadsHtml = if ($deltaDownloads -gt 0) { "<span class='kpi-delta'>+$deltaDownloads</span>" } else { "" }
$bio = if ($user.bio) { $user.bio } else { "Open Source Creator & Developer" }
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$reposJson = $analyzedRepos | ConvertTo-Json -Depth 5 -Compress
$rolling14Json = $chartRolling14List | ConvertTo-Json -Depth 5 -Compress
$cumulativeYearJson = $chartCumulativeList | ConvertTo-Json -Depth 5 -Compress
$byRepoDailyJson = $dailyTrafficByRepo | ConvertTo-Json -Depth 5 -Compress
$allReleasesJson = $allReleases | ConvertTo-Json -Depth 6 -Compress

# Build HTML template
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GitMyRate - __USER_LOGIN__ Audience, Traffic & Vitals</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #090d16;
      --card-bg: rgba(20, 27, 45, 0.78);
      --card-border: rgba(255, 255, 255, 0.08);
      --card-hover: rgba(29, 39, 65, 0.95);
      --text-main: #f8fafc;
      --text-muted: #94a3b8;
      --accent-primary: #38bdf8;
      --accent-secondary: #818cf8;
      --star-color: #fbbf24;
      --download-color: #34d399;
      --fork-color: #c084fc;
      --issue-color: #f87171;
      --views-color: #38bdf8;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      background: radial-gradient(circle at 10% 10%, #152037 0%, var(--bg) 55%),
                  radial-gradient(circle at 90% 90%, #171b30 0%, var(--bg) 65%);
      color: var(--text-main);
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      padding: 2.5rem 1.5rem 4rem 1.5rem;
    }

    .container { max-width: 1280px; margin: 0 auto; }

    /* Profile Header */
    .profile-banner {
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
      gap: 1.5rem; background: var(--card-bg); backdrop-filter: blur(16px);
      border: 1px solid var(--card-border); border-radius: 20px; padding: 1.75rem 2rem;
      margin-bottom: 2rem; box-shadow: 0 12px 35px rgba(0, 0, 0, 0.4);
    }
    .profile-info { display: flex; align-items: center; gap: 1.25rem; }
    .avatar {
      width: 76px; height: 76px; border-radius: 20px; border: 2px solid #38bdf8;
      box-shadow: 0 0 25px rgba(56, 189, 248, 0.35); object-fit: cover; background: #090d16;
    }
    .profile-title {
      font-size: 1.65rem; font-weight: 800; letter-spacing: -0.02em;
      background: linear-gradient(135deg, #ffffff 40%, #94a3b8);
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    }
    .profile-handle {
      color: var(--accent-primary); text-decoration: none; font-weight: 600;
      font-size: 0.95rem; display: inline-flex; align-items: center; gap: 0.35rem; margin-top: 0.3rem;
    }
    .profile-handle:hover { text-decoration: underline; }
    .brand-badge {
      display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.4rem 0.85rem;
      border-radius: 9999px; background: rgba(56, 189, 248, 0.12); color: var(--accent-primary);
      border: 1px solid rgba(56, 189, 248, 0.25); font-size: 0.8rem; font-weight: 700;
    }
    .btn {
      display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.65rem 1.15rem;
      border-radius: 10px; font-weight: 600; font-size: 0.88rem; text-decoration: none;
      cursor: pointer; transition: all 0.2s ease; border: 1px solid var(--card-border);
      background: rgba(255, 255, 255, 0.05); color: var(--text-main);
    }
    .btn:hover { background: rgba(255, 255, 255, 0.12); transform: translateY(-2px); }

    /* KPIs */
    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
    .kpi-card {
      background: var(--card-bg); backdrop-filter: blur(16px); border: 1px solid var(--card-border);
      border-radius: 16px; padding: 1.25rem 1.5rem; display: flex; align-items: center; gap: 1.25rem;
      transition: transform 0.2s ease, border-color 0.2s ease;
    }
    .kpi-card:hover { transform: translateY(-2px); border-color: rgba(255, 255, 255, 0.18); }
    .kpi-icon { font-size: 2rem; }
    .kpi-value { font-size: 1.85rem; font-weight: 800; font-family: 'JetBrains Mono', monospace; }
    .kpi-label { font-size: 0.82rem; color: var(--text-muted); text-transform: uppercase; font-weight: 600; letter-spacing: 0.05em; margin-top: 0.2rem; }
    .kpi-delta { font-size: 0.72rem; padding: 0.15rem 0.45rem; border-radius: 9999px; background: rgba(52, 211, 153, 0.15); color: #34d399; font-weight: 700; margin-left: 0.35rem; }

    /* Funnel Section */
    .funnel-section {
      background: var(--card-bg); backdrop-filter: blur(16px); border: 1px solid var(--card-border);
      border-radius: 20px; padding: 1.75rem 2rem; margin-bottom: 2rem; box-shadow: 0 8px 30px rgba(0,0,0,0.3);
    }
    .funnel-header { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 0.75rem; margin-bottom: 1.25rem; }
    .funnel-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
    .funnel-card {
      background: rgba(15, 23, 42, 0.55); border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 14px; padding: 1.15rem; display: flex; flex-direction: column; justify-content: space-between;
    }
    .funnel-card-header { display: flex; justify-content: space-between; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }
    .funnel-card-label { font-size: 0.82rem; font-weight: 600; color: #94a3b8; }
    .funnel-pill {
      font-size: 0.7rem; font-weight: 700; padding: 0.2rem 0.6rem; border-radius: 9999px;
      text-align: center; white-space: nowrap; flex-shrink: 0; display: inline-flex; align-items: center; justify-content: center;
    }
    .funnel-card-val { font-size: 1.65rem; font-weight: 800; font-family: 'JetBrains Mono', monospace; }
    .funnel-card-formula { font-size: 0.72rem; color: #64748b; margin-top: 0.25rem; }
    .funnel-card-desc { font-size: 0.78rem; color: #cbd5e1; margin-top: 0.6rem; line-height: 1.35; }
    .funnel-flow {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 0.45rem;
      align-items: center;
      padding: 0.75rem 0.85rem;
      background: rgba(15, 23, 42, 0.45);
      border: 1px solid rgba(255, 255, 255, 0.05);
      border-radius: 12px;
      width: 100%;
      box-sizing: border-box;
    }
    .stage-pill {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 0.3rem;
      padding: 0.45rem 0.3rem;
      border-radius: 8px;
      font-size: 0.76rem;
      font-weight: 600;
      background: rgba(255, 255, 255, 0.03);
      white-space: nowrap;
      transition: transform 0.15s ease;
      box-sizing: border-box;
      width: 100%;
      text-align: center;
    }
    .stage-pill:hover { transform: translateY(-1px); }
    .stage-pill.pill-visitors { border: 1px solid rgba(56, 189, 248, 0.3); color: #bae6fd; }
    .stage-pill.pill-devs { border: 1px solid rgba(56, 189, 248, 0.3); color: #38bdf8; }
    .stage-pill.pill-downloads { border: 1px solid rgba(52, 211, 153, 0.3); color: #34d399; }
    .stage-pill.pill-stars { border: 1px solid rgba(251, 191, 36, 0.3); color: #fbbf24; }
    .stage-pill.pill-bots { border: 1px solid rgba(248, 113, 113, 0.3); color: #f87171; }

    /* Interactive Chart */
    .chart-section {
      background: var(--card-bg); backdrop-filter: blur(16px); border: 1px solid var(--card-border);
      border-radius: 20px; padding: 1.75rem 2rem; margin-bottom: 2rem; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.3);
    }
    .chart-header { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 1rem; margin-bottom: 1.5rem; }
    .chart-controls { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: center; }
    .view-mode-group {
      display: inline-flex; background: rgba(15, 23, 42, 0.75); border: 1px solid var(--card-border);
      border-radius: 10px; padding: 3px; gap: 2px;
    }
    .view-mode-btn {
      background: transparent; border: none; color: var(--text-muted); font-size: 0.78rem;
      font-weight: 600; padding: 0.4rem 0.85rem; border-radius: 7px; cursor: pointer; transition: all 0.2s ease;
    }
    .view-mode-btn.active { background: #38bdf8; color: #090d16; font-weight: 700; }
    .chart-select {
      background: rgba(15, 23, 42, 0.8); border: 1px solid var(--card-border); color: var(--text-main);
      padding: 0.45rem 0.85rem; border-radius: 8px; font-size: 0.8rem; font-weight: 600;
    }
    .chart-metric-btn {
      background: rgba(255, 255, 255, 0.05); border: 1px solid var(--card-border); color: var(--text-muted);
      padding: 0.4rem 0.75rem; border-radius: 8px; font-size: 0.78rem; font-weight: 600; cursor: pointer;
    }
    .chart-metric-btn.active { background: rgba(56, 189, 248, 0.2); border-color: #38bdf8; color: #38bdf8; font-weight: 700; }

    .chart-viewport {
      display: flex;
      margin-top: 0.75rem;
      position: relative;
    }
    .chart-y-axis {
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      align-items: flex-end;
      width: 32px;
      padding-right: 8px;
      height: 185px;
      color: var(--text-muted);
      font-size: 0.68rem;
      font-family: 'JetBrains Mono', monospace;
      user-select: none;
      padding-bottom: 2px;
    }
    .chart-stage {
      flex: 1;
      position: relative;
      display: flex;
      flex-direction: column;
      min-width: 0;
    }
    .chart-grid-lines {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 185px;
      pointer-events: none;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }
    .chart-grid-line {
      width: 100%;
      border-bottom: 1px dashed rgba(255, 255, 255, 0.07);
    }
    .chart-grid-line:last-child {
      border-bottom: 1px solid rgba(255, 255, 255, 0.14);
    }
    .bars-container {
      display: flex;
      align-items: flex-end;
      gap: 8px;
      height: 185px;
      padding: 0 0.5rem;
      position: relative;
      z-index: 1;
    }
    .bar-col {
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      height: 100%;
      justify-content: flex-end;
      position: relative;
      cursor: pointer;
    }
    .bar-val {
      font-size: 0.75rem;
      font-weight: 800;
      color: #38bdf8;
      font-family: 'JetBrains Mono', monospace;
      margin-bottom: 4px;
      text-shadow: 0 2px 4px rgba(0, 0, 0, 0.6);
      white-space: nowrap;
      pointer-events: none;
      transition: transform 0.15s ease, color 0.15s ease;
    }
    .bar-col:hover .bar-val {
      transform: translateY(-2px);
      color: #fff;
    }
    .bar-val.today-live {
      color: #34d399;
      font-size: 0.78rem;
    }
    .bar-val.today-zero {
      color: rgba(148, 163, 184, 0.45);
      font-size: 0.65rem;
      font-weight: 600;
    }
    .bar-fill {
      width: 100%;
      border-radius: 6px 6px 0 0;
      background: linear-gradient(180deg, #38bdf8 0%, #0284c7 100%);
      transition: height 0.4s cubic-bezier(0.16, 1, 0.3, 1), background 0.2s ease, box-shadow 0.2s ease;
    }
    .bar-col:hover .bar-fill {
      background: linear-gradient(180deg, #7dd3fc 0%, #0369a1 100%);
      box-shadow: 0 0 12px rgba(56, 189, 248, 0.4);
    }
    .bar-col.is-today .bar-fill {
      background: linear-gradient(180deg, #34d399 0%, #059669 100%);
      box-shadow: 0 0 10px rgba(52, 211, 153, 0.4);
    }
    .bar-col.is-zero .bar-fill {
      display: none;
    }
    .zero-baseline-dot {
      width: 4px;
      height: 4px;
      border-radius: 50%;
      background: rgba(255, 255, 255, 0.15);
      margin-bottom: 2px;
      transition: transform 0.15s ease, background 0.15s ease;
    }
    .bar-col:hover .zero-baseline-dot {
      background: rgba(255, 255, 255, 0.6);
      transform: scale(1.4);
    }
    .bar-col.is-today .zero-baseline-dot {
      background: #34d399;
      box-shadow: 0 0 6px rgba(52, 211, 153, 0.6);
    }
    .bars-x-axis {
      display: flex;
      gap: 8px;
      padding: 0.5rem 0.5rem 0 0.5rem;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
      position: relative;
      z-index: 1;
    }
    .x-label {
      flex: 1;
      text-align: center;
      font-size: 0.72rem;
      color: var(--text-muted);
      font-family: 'JetBrains Mono', monospace;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 2px;
    }
    .x-label.is-today {
      color: #34d399;
      font-weight: 700;
    }
    .today-badge {
      display: inline-block;
      font-size: 0.55rem;
      font-weight: 800;
      color: #0f172a;
      background: #34d399;
      padding: 1px 4px;
      border-radius: 3px;
      letter-spacing: 0.03em;
    }

    /* Heatmap Styles */
    .heatmap-container {
      padding: 0.5rem 0.25rem 0 0.25rem;
    }
    .heatmap-wrap {
      display: flex;
      flex-direction: column;
      overflow-x: auto;
      padding-bottom: 0.5rem;
    }
    .heatmap-body {
      display: flex;
      gap: 8px;
      align-items: flex-start;
    }
    .heatmap-days-legend {
      display: flex;
      flex-direction: column;
      gap: 3px;
      font-size: 0.65rem;
      color: var(--text-muted);
      font-family: 'JetBrains Mono', monospace;
      user-select: none;
      width: 24px;
    }
    .heatmap-days-legend span {
      display: flex;
      align-items: center;
      height: 12px;
      line-height: 12px;
      box-sizing: border-box;
    }
    .heatmap-grid {
      display: flex;
      gap: 3px;
    }
    .heatmap-week {
      display: flex;
      flex-direction: column;
      gap: 3px;
    }
    .heatmap-cell {
      width: 12px;
      height: 12px;
      border-radius: 2px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.02);
      cursor: pointer;
      transition: transform 0.15s ease, outline 0.15s ease;
      box-sizing: border-box;
    }
    .heatmap-cell:hover {
      transform: scale(1.4);
      z-index: 10;
      outline: 2px solid #fff;
    }
    .heatmap-cell.is-today {
      outline: 1.5px solid #34d399;
    }
    .heat-lvl-0 { background: rgba(255, 255, 255, 0.04); }
    .heat-lvl-1 { background: #0369a1; }
    .heat-lvl-2 { background: #0284c7; }
    .heat-lvl-3 { background: #38bdf8; box-shadow: 0 0 4px rgba(56, 189, 248, 0.4); }
    .heat-lvl-4 { background: #7dd3fc; box-shadow: 0 0 8px rgba(125, 211, 252, 0.6); }

    .heatmap-footer {
      display: flex;
      justify-content: flex-end;
      align-items: center;
      gap: 6px;
      margin-top: 0.85rem;
      font-size: 0.72rem;
      color: var(--text-muted);
      padding-right: 0.5rem;
      font-family: 'JetBrains Mono', monospace;
    }
    .heatmap-legend-cells {
      display: flex;
      gap: 3px;
    }
    .heatmap-legend-cells .heatmap-cell {
      cursor: default;
    }
    .heatmap-legend-cells .heatmap-cell:hover {
      transform: none;
      outline: none;
    }

    .chart-summary-bar {
      display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem;
      padding-top: 1rem; margin-top: 0.5rem; border-top: 1px solid rgba(255, 255, 255, 0.06); font-size: 0.82rem;
    }
    .chart-stat-item { display: flex; gap: 0.4rem; align-items: baseline; }
    .chart-stat-val { font-weight: 800; color: #38bdf8; font-family: 'JetBrains Mono', monospace; }

    /* History Drawer */
    .history-card {
      display: none; background: rgba(15, 23, 42, 0.9); border: 1px solid var(--card-border);
      border-radius: 16px; padding: 1.5rem; margin-bottom: 2rem;
    }
    .history-table { width: 100%; border-collapse: collapse; font-size: 0.84rem; }
    .history-table th, .history-table td { padding: 0.65rem 0.75rem; text-align: left; border-bottom: 1px solid rgba(255, 255, 255, 0.06); }
    .history-table th { color: var(--text-muted); font-size: 0.75rem; text-transform: uppercase; }

    /* Web Buzz Radar */
    .hubbub-section {
      background: var(--card-bg); backdrop-filter: blur(16px); border: 1px solid var(--card-border);
      border-radius: 20px; padding: 1.75rem 2rem; margin-bottom: 2rem; box-shadow: 0 8px 30px rgba(0, 0, 0, 0.3);
    }
    .hubbub-header { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; }
    .hubbub-badge { font-size: 0.72rem; padding: 0.2rem 0.6rem; border-radius: 9999px; background: rgba(56, 189, 248, 0.15); color: #38bdf8; font-weight: 700; }
    .radar-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 0.85rem; margin: 1.25rem 0; }
    .radar-btn {
      display: flex; align-items: center; gap: 0.85rem; padding: 0.85rem 1rem; background: rgba(15, 23, 42, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.06); border-radius: 12px; text-decoration: none; transition: all 0.2s ease;
    }
    .radar-btn:hover { background: rgba(30, 41, 59, 0.8); border-color: rgba(56, 189, 248, 0.4); transform: translateY(-2px); }
    .radar-icon { font-size: 1.5rem; }
    .radar-meta-title { display: block; font-size: 0.86rem; font-weight: 700; color: #f1f5f9; }
    .radar-meta-sub { display: block; font-size: 0.72rem; color: #94a3b8; margin-top: 0.15rem; }

    /* Inbound Referrers / Traffic */
    .traffic-box { background: rgba(15, 23, 42, 0.6); border: 1px solid var(--card-border); border-radius: 14px; padding: 1.25rem; overflow-x: auto; min-width: 0; }
    .traffic-title { font-size: 0.95rem; font-weight: 700; color: #38bdf8; margin-bottom: 0.5rem; }
    .traffic-table { width: 100%; border-collapse: collapse; font-size: 0.84rem; }
    .traffic-table th, .traffic-table td { padding: 0.6rem; text-align: left; border-bottom: 1px solid rgba(255, 255, 255, 0.06); }
    .traffic-table th { color: var(--text-muted); font-size: 0.75rem; text-transform: uppercase; }

    /* Filter & Sort Toolbar */
    .toolbar {
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
      gap: 1rem; margin-bottom: 1.5rem;
    }
    .filter-btn {
      background: rgba(255, 255, 255, 0.04); border: 1px solid var(--card-border); color: var(--text-muted);
      padding: 0.5rem 1rem; border-radius: 8px; font-weight: 600; cursor: pointer; font-size: 0.85rem;
    }
    .filter-btn.active { background: rgba(56, 189, 248, 0.15); border-color: #38bdf8; color: #38bdf8; }
    .search-box, .sort-select {
      background: rgba(15, 23, 42, 0.8); border: 1px solid var(--card-border); color: var(--text-main);
      padding: 0.55rem 0.9rem; border-radius: 8px; font-size: 0.86rem;
    }

    /* Repo Cards */
    .repo-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 1.25rem; }
    .repo-card {
      background: var(--card-bg); backdrop-filter: blur(16px); border: 1px solid var(--card-border);
      border-radius: 16px; padding: 1.35rem; display: flex; flex-direction: column; justify-content: space-between;
      transition: all 0.2s ease;
    }
    .repo-card:hover { transform: translateY(-3px); border-color: rgba(56, 189, 248, 0.4); }
    .repo-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 0.5rem; }
    .repo-name { font-size: 1.15rem; font-weight: 700; color: #bae6fd; text-decoration: none; }
    .badge-release {
      font-size: 0.7rem; font-weight: 700; padding: 0.15rem 0.45rem; border-radius: 9999px;
      background: rgba(52, 211, 153, 0.15); color: #34d399; border: 1px solid rgba(52, 211, 153, 0.3); margin-left: 0.35rem;
    }
    .badge-source { font-size: 0.7rem; font-weight: 700; padding: 0.15rem 0.45rem; border-radius: 9999px; background: rgba(56, 189, 248, 0.12); color: #38bdf8; }
    .badge-fork { font-size: 0.7rem; font-weight: 700; padding: 0.15rem 0.45rem; border-radius: 9999px; background: rgba(192, 132, 252, 0.15); color: #c084fc; }

    /* Health Strip */
    .repo-health-strip { margin: 0.65rem 0 0.5rem 0; cursor: help; }
    .health-meta { display: flex; align-items: center; justify-content: space-between; font-size: 0.75rem; font-weight: 700; margin-bottom: 0.3rem; }
    .health-bar-bg { height: 5px; border-radius: 3px; background: rgba(255, 255, 255, 0.08); overflow: hidden; }
    .health-bar-fill { height: 100%; border-radius: 3px; }

    .repo-desc { font-size: 0.84rem; color: var(--text-muted); margin: 0.5rem 0; min-height: 2.4rem; line-height: 1.4; }
    .topic-tag { font-size: 0.7rem; color: #38bdf8; background: rgba(56, 189, 248, 0.08); padding: 0.15rem 0.4rem; border-radius: 4px; display: inline-block; margin: 0.15rem; }

    .metrics-bar { display: flex; gap: 0.75rem; flex-wrap: wrap; margin-top: 0.85rem; padding-top: 0.75rem; border-top: 1px solid rgba(255, 255, 255, 0.06); }
    .metric-item { display: flex; flex-direction: column; }
    .metric-val { font-size: 0.88rem; font-weight: 700; font-family: 'JetBrains Mono', monospace; }
    .metric-lbl { font-size: 0.68rem; color: var(--text-muted); text-transform: uppercase; }

    .repo-conv-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem; margin-top: 0.65rem; }
    .conv-tag {
      font-size: 0.68rem; padding: 0.2rem 0.45rem; border-radius: 4px; font-weight: 600;
      background: rgba(255, 255, 255, 0.04); color: #64748b; border: 1px solid rgba(255, 255, 255, 0.06);
      display: inline-flex; align-items: center; gap: 0.25rem; line-height: 1.2;
    }
    .conv-tag-today { border-color: rgba(255, 255, 255, 0.08); color: #64748b; background: rgba(255, 255, 255, 0.03); }
    .conv-tag-today.active { border-color: rgba(52, 211, 153, 0.45); color: #34d399; background: rgba(52, 211, 153, 0.12); font-weight: 700; box-shadow: 0 0 8px rgba(52, 211, 153, 0.2); }
    .conv-tag-star.active { border-color: rgba(251, 191, 36, 0.35); color: #fbbf24; background: rgba(251, 191, 36, 0.1); }
    .conv-tag-dl.active { border-color: rgba(52, 211, 153, 0.35); color: #34d399; background: rgba(52, 211, 153, 0.1); }
    .conv-tag-dev.active { border-color: rgba(56, 189, 248, 0.35); color: #38bdf8; background: rgba(56, 189, 248, 0.1); }
    .conv-persona { font-weight: 700; color: #c084fc; border-color: rgba(192, 132, 252, 0.35); background: rgba(192, 132, 252, 0.1); }

    .repo-footer { display: flex; justify-content: space-between; align-items: center; margin-top: 0.75rem; font-size: 0.75rem; color: var(--text-muted); }

    .footer { text-align: center; color: var(--text-muted); font-size: 0.8rem; margin-top: 4rem; line-height: 1.6; }

    /* Responsive Layout for Half-Screen / Compact Displays */
    @media (max-width: 960px) {
      .funnel-arrow {
        display: none !important;
      }
      .profile-banner, .funnel-section, .chart-section {
        padding: 1.25rem 1.25rem;
      }
      .chart-header {
        flex-direction: column;
        align-items: flex-start;
        gap: 0.75rem;
      }
      .chart-controls {
        width: 100%;
        justify-content: flex-start;
      }
    }

    @media (max-width: 768px) {
      .funnel-flow {
        grid-template-columns: 1fr;
        gap: 0.5rem;
      }
    }

    @media (max-width: 600px) {
      .container {
        padding: 1rem 0.75rem;
      }
      .profile-banner {
        flex-direction: column;
        align-items: flex-start;
        gap: 1rem;
      }
      .kpi-grid {
        grid-template-columns: 1fr 1fr;
      }
      .funnel-grid {
        grid-template-columns: 1fr;
      }
      .view-mode-group {
        flex-wrap: wrap;
        width: 100%;
      }
      .view-mode-btn {
        flex: 1 1 auto;
        text-align: center;
      }
    }
  </style>
</head>
<body>
  <div class="container">
    <header class="profile-banner">
      <div class="profile-info">
        <img class="avatar" src="__USER_AVATAR__" alt="__USER_LOGIN__">
        <div>
          <h1 class="profile-title">__USER_LOGIN__</h1>
          <p style="color: var(--text-muted); font-size: 0.88rem; margin-top: 0.2rem;">__USER_BIO__</p>
          <a class="profile-handle" href="https://github.com/__USER_LOGIN__" target="_blank" rel="noopener noreferrer">
            github.com/__USER_LOGIN__ &nearr;
          </a>
        </div>
      </div>
      <div style="display: flex; gap: 0.75rem; align-items: center;">
        <span class="brand-badge">&#x26A1; GitMyRate v__SCRIPT_VERSION__</span>
        <button class="btn" onclick="toggleHistory()">&#x1F4DC; History Log</button>
      </div>
    </header>

    <!-- Top KPIs -->
    <section class="kpi-grid">
      <div class="kpi-card">
        <div class="kpi-icon">&#x2B50;</div>
        <div>
          <div class="kpi-value" style="color: var(--star-color);">__TOTAL_STARS____DELTA_STARS_HTML__</div>
          <div class="kpi-label">Total Stars</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F4E5;</div>
        <div>
          <div class="kpi-value" style="color: var(--download-color);">__TOTAL_DOWNLOADS____DELTA_DOWNLOADS_HTML__</div>
          <div class="kpi-label">Release Downloads</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F441;&#xFE0F;</div>
        <div>
          <div class="kpi-value" style="color: var(--views-color);">__TOTAL_VIEWS_14D__</div>
          <div class="kpi-label">14-Day Views</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F500;</div>
        <div>
          <div class="kpi-value" style="color: var(--fork-color);">__TOTAL_FORKS__</div>
          <div class="kpi-label">Forks Count</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F4E6;</div>
        <div>
          <div class="kpi-value">__TOTAL_REPOS__</div>
          <div class="kpi-label">Public Repos</div>
        </div>
      </div>
    </section>

    <!-- Funnel Section -->
    <section class="funnel-section">
      <div class="funnel-header">
        <div>
          <h2 style="font-size: 1.2rem; font-weight: 700;">&#x1F3AF; Git Conversion Rates &amp; Funnel Health</h2>
          <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.2rem;">
            Measuring how effectively repository discovery turns into stars, clones, and downloads
          </p>
        </div>
        <span class="brand-badge" style="font-size: 0.72rem;">&#x1F4CA; Engagement Analytics</span>
      </div>

      <div class="funnel-grid" id="funnel-cards-container"></div>
      <div class="funnel-flow" id="funnel-flow-container"></div>
    </section>

    <!-- 14-Day & Lifetime Cumulative Bar Chart -->
    <section class="chart-section">
      <div class="chart-header">
        <div>
          <h2 style="font-size: 1.2rem; font-weight: 700;" id="main-chart-title">Traffic &amp; Views Activity</h2>
          <p style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.2rem;" id="main-chart-subtitle">
            Interactive 14-day rolling and lifetime cumulative counts
          </p>
        </div>

        <div class="chart-controls">
          <div class="view-mode-group">
            <button class="view-mode-btn active" id="btn-mode-rolling" onclick="setChartMode('rolling')">14-Day Rolling</button>
            <button class="view-mode-btn" id="btn-mode-cumulative" onclick="setChartMode('cumulative')">&#x1F4C8; Lifetime Cumulative</button>
            <button class="view-mode-btn" id="btn-mode-monthly" onclick="setChartMode('monthly')">Monthly</button>
            <button class="view-mode-btn" id="btn-mode-heatmap" onclick="setChartMode('heatmap')">&#x1F7E9; Heatmap</button>
          </div>

          <select id="chart-repo-select" class="chart-select">
            <option value="combined">&#x1F310; Combined (All Repositories)</option>
          </select>

          <div style="display: flex; gap: 0.35rem;">
            <button class="chart-metric-btn active" id="btn-chart-views" onclick="setChartMetric('views')">Views</button>
            <button class="chart-metric-btn" id="btn-chart-uniques" onclick="setChartMetric('uniques')">Uniques</button>
            <button class="chart-metric-btn" id="btn-chart-downloads" onclick="setChartMetric('downloads')">&#x1F4E5; DLs</button>
          </div>
        </div>
      </div>

      <!-- Bar Chart Viewport -->
      <div class="chart-viewport" id="chart-viewport">
        <div class="chart-y-axis" id="chart-y-axis"></div>
        <div class="chart-stage">
          <div class="chart-grid-lines" id="chart-grid-lines"></div>
          <div class="bars-container" id="bars-track"></div>
          <div class="bars-x-axis" id="bars-axis"></div>
        </div>
      </div>

      <!-- Heatmap Viewport (hidden by default) -->
      <div class="heatmap-container" id="heatmap-view" style="display: none;"></div>

      <div class="chart-summary-bar">
        <div style="display: flex; gap: 1.5rem; flex-wrap: wrap;">
          <div class="chart-stat-item">
            <span id="chart-sum-total-lbl">Period Total:</span>
            <span class="chart-stat-val" id="chart-sum-total">0</span>
          </div>
          <div class="chart-stat-item">
            <span id="chart-sum-avg-lbl">Daily Average:</span>
            <span class="chart-stat-val" id="chart-sum-avg">0</span>
          </div>
          <div class="chart-stat-item">
            <span id="chart-sum-peak-lbl">Peak Day:</span>
            <span class="chart-stat-val" id="chart-sum-peak">-</span>
          </div>
        </div>
        <div style="font-size: 0.78rem; color: #94a3b8;" id="chart-repo-note">
          Showing combined metrics across all projects
        </div>
      </div>
    </section>

    <!-- History Drawer -->
    <section class="history-card" id="history-drawer">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem;">
        <h3 style="font-size: 1rem; font-weight: 700; color: #bae6fd;">&#x1F4DC; Historical Growth Log (Local JSON Tracker)</h3>
        <span style="font-size: 0.75rem; color: var(--text-muted);">Saved in <code>%LOCALAPPDATA%\GitMyRate\stats-history.json</code></span>
      </div>
      <div style="max-height: 240px; overflow-y: auto;">
        <table class="history-table">
          <thead>
            <tr><th>Snapshot Date</th><th>Total Stars</th><th>Downloads</th><th>14d Views</th><th>Lifetime Total</th></tr>
          </thead>
          <tbody id="history-rows"></tbody>
        </table>
      </div>
    </section>

    <!-- Universal Web Buzz Radar -->
    <section class="hubbub-section">
      <div class="hubbub-header">
        <div style="display: flex; align-items: center; gap: 0.5rem;">
          <span style="font-size: 1.4rem;">&#x1F4E1;</span>
          <h2 style="font-size: 1.15rem; font-weight: 700;">Web &amp; Community Buzz Radar</h2>
          <span class="hubbub-badge">Live Scanner</span>
        </div>
        <span style="font-size: 0.8rem; color: var(--text-muted);">
          1-Click discovery for web discussions, threads &amp; inbound links
        </span>
      </div>

      <p style="font-size: 0.85rem; color: var(--text-muted); line-height: 1.5;">
        Monitor where tech communities are discussing your projects (__RADAR_TERMS_DISPLAY__):
      </p>

      <div class="radar-grid">
        <a class="radar-btn" href="https://github.com/search?q=__RADAR_QUERY_PLAIN__&type=discussions" target="_blank" rel="noopener noreferrer">
          <div class="radar-icon" style="color: #c084fc;">&#x1F419;</div>
          <div class="radar-meta">
            <span class="radar-meta-title">GitHub Global Mentions</span>
            <span class="radar-meta-sub">Discussions &amp; issues across GitHub</span>
          </div>
        </a>

        <a class="radar-btn" href="https://hn.algolia.com/?q=__RADAR_QUERY_PLAIN__&sort=byDate" target="_blank" rel="noopener noreferrer">
          <div class="radar-icon" style="color: #ff6600;">&#x1F4E2;</div>
          <div class="radar-meta">
            <span class="radar-meta-title">Hacker News</span>
            <span class="radar-meta-sub">Posts &amp; comment threads</span>
          </div>
        </a>

        <a class="radar-btn" href="https://www.reddit.com/search/?q=__RADAR_QUERY_QUOTED__&sort=new" target="_blank" rel="noopener noreferrer">
          <div class="radar-icon" style="color: #ff4500;">&#x1F4AC;</div>
          <div class="radar-meta">
            <span class="radar-meta-title">Reddit Discussions</span>
            <span class="radar-meta-sub">r/programming, r/opensource &amp; forums</span>
          </div>
        </a>

        <a class="radar-btn" href="https://www.google.com/search?q=__RADAR_QUERY_QUOTED__&tbs=qdr:m" target="_blank" rel="noopener noreferrer">
          <div class="radar-icon" style="color: #38bdf8;">&#x1F50E;</div>
          <div class="radar-meta">
            <span class="radar-meta-title">Google (Past 30d)</span>
            <span class="radar-meta-sub">Recent indexed articles, blogs &amp; links</span>
          </div>
        </a>

        <a class="radar-btn" href="https://www.google.com/alerts#create:q=__RADAR_QUERY_QUOTED__" target="_blank" rel="noopener noreferrer">
          <div class="radar-icon" style="color: #34d399;">&#x1F514;</div>
          <div class="radar-meta">
            <span class="radar-meta-title">Google Alerts</span>
            <span class="radar-meta-sub">Instant email notification when mentioned</span>
          </div>
        </a>
      </div>

      <!-- Inbound Referrers / Traffic Data -->
      __TRAFFIC_HTML__
    </section>

    <!-- Filter & Sort Toolbar -->
    <div class="toolbar">
      <div class="filter-group">
        <button class="filter-btn active" data-filter="all">All Projects (<span id="count-all">0</span>)</button>
        <button class="filter-btn" data-filter="source">Original (<span id="count-src">0</span>)</button>
        <button class="filter-btn" data-filter="fork">Forks (<span id="count-fork">0</span>)</button>
      </div>

      <div style="display: flex; gap: 0.75rem; align-items: center;">
        <input type="text" id="search-input" class="search-box" placeholder="Search repos, topics, license...">
        <select id="sort-select" class="sort-select">
          <option value="downloads">Sort by Downloads</option>
          <option value="health">Sort by Health Score &#x1F49A;</option>
          <option value="starRate">Sort by Star Conv % &#x2B50;</option>
          <option value="views">Sort by 14-Day Views</option>
          <option value="stars">Sort by Stars</option>
          <option value="pushed">Sort by Recently Pushed</option>
          <option value="name">Sort by Name</option>
        </select>
      </div>
    </div>

    <!-- Repository Cards Container -->
    <main class="repo-grid" id="repo-container"></main>

    <!-- Footer -->
    <footer class="footer">
      Generated automatically by <strong>GitMyRate v__SCRIPT_VERSION__</strong> &bull; Last refreshed: __GENERATED_AT__<br>
      <span style="opacity: 0.75; font-size: 0.78rem;">Historical snapshots archived in <code>%LOCALAPPDATA%\GitMyRate\stats-history.json</code> (bypassing GitHub's 14-day limit).</span>
    </footer>
  </div>

  <script>
    const repos = __REPOS_JSON__;
    const rolling14Data = __ROLLING_14_JSON__;
    const cumulativeYearData = __CUMULATIVE_YEAR_JSON__;
    const byRepoDaily = __BY_REPO_DAILY_JSON__;
    const allReleases = __RELEASES_JSON__;
    const rawHistory = __HISTORY_JSON__;
    const historyData = Array.isArray(rawHistory) ? rawHistory : (rawHistory ? [rawHistory] : []);

    if (Array.isArray(repos)) {
      repos.forEach(r => {
        r.Topics = (Array.isArray(r.Topics) ? r.Topics : [])
          .filter(t => typeof t === 'string' && t.trim().length > 0 && t !== '[object Object]');
        r.Description = r.Description || '';
        r.Language = r.Language || 'General';
        r.License = r.License || '';
        r.Downloads = r.Downloads || 0;
        r.Stars = r.Stars || 0;
        r.Views14Days = r.Views14Days || 0;
        r.Uniques14Days = r.Uniques14Days || 0;
        r.ViewsToday = r.ViewsToday || 0;
        r.UniquesToday = r.UniquesToday || 0;
        r.Clones14Days = r.Clones14Days || 0;
        r.UniqueClones14Days = r.UniqueClones14Days || 0;
        r.Forks = r.Forks || 0;
        r.OpenIssues = r.OpenIssues || 0;
      });
    }

    const languageColors = {
      'C#': '#178600',
      'PoSH': '#012456',
      'HTML': '#e34c26',
      'JavaScript': '#f1e05a',
      'Python': '#3572A5',
      'TypeScript': '#3178c6',
      'General': '#64748b'
    };

    let currentFilter = 'all';
    let currentSort = 'downloads';
    let searchQuery = '';

    let chartMode = 'rolling'; // 'rolling', 'cumulative', 'monthly'
    let chartRepo = 'combined'; // 'combined' or repo name
    let chartMetric = 'views';  // 'views', 'uniques', 'downloads'

    function formatDate(isoStr) {
      if (!isoStr) return 'N/A';
      const d = new Date(isoStr);
      return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    function timeAgo(isoStr) {
      if (!isoStr) return '';
      const seconds = Math.floor((new Date() - new Date(isoStr)) / 1000);
      let interval = Math.floor(seconds / 86400);
      if (interval >= 1) return interval === 1 ? '1 day ago' : interval + ' days ago';
      interval = Math.floor(seconds / 3600);
      if (interval >= 1) return interval === 1 ? '1 hr ago' : interval + ' hrs ago';
      interval = Math.floor(seconds / 60);
      if (interval >= 1) return interval === 1 ? '1 min ago' : interval + ' mins ago';
      return 'just now';
    }

    function toggleHistory() {
      const drawer = document.getElementById('history-drawer');
      const isVisible = drawer.style.display === 'block';
      drawer.style.display = isVisible ? 'none' : 'block';
      if (!isVisible) renderHistoryRows();
    }

    function renderHistoryRows() {
      const tbody = document.getElementById('history-rows');
      if (!historyData || historyData.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: #94a3b8;">No previous history records yet.</td></tr>';
        return;
      }
      const reversed = [...historyData].reverse().slice(0, 20);
      tbody.innerHTML = reversed.map(h => `
        <tr>
          <td><strong>${h.dateDisplay || formatDate(h.timestamp)}</strong></td>
          <td style="color: var(--star-color);">&#x2B50; ${h.totalStars}</td>
          <td style="color: var(--download-color);">&#x1F4E5; ${h.totalDownloads}</td>
          <td style="color: var(--views-color);">&#x1F441;&#xFE0F; ${h.totalViews14d || 0}</td>
          <td style="color: #34d399; font-weight: 600;">&#x1F4C8; ${h.yearCumulativeViews || h.totalViews14d || 0}</td>
        </tr>
      `).join('');
    }

    /* ------------------- INTERACTIVE CHART RENDERING ------------------- */
    function updateChartTitles() {
      const title = document.getElementById('main-chart-title');
      const sub = document.getElementById('main-chart-subtitle');
      const btnRolling = document.getElementById('btn-mode-rolling');
      const btnCum = document.getElementById('btn-mode-cumulative');
      const btnMonthly = document.getElementById('btn-mode-monthly');
      const btnHeatmap = document.getElementById('btn-mode-heatmap');

      if (btnHeatmap) btnHeatmap.innerText = '\u{1F7E9} Heatmap';

      if (chartMetric === 'downloads') {
        if (chartRepo === 'combined') {
          btnRolling.innerText = '\u{1F4E6} By Repository';
          btnCum.innerText = '\u{1F4C8} Lifetime Cumulative';
          btnMonthly.innerText = '\u{1F4C5} Monthly';

          if (chartMode === 'rolling') {
            title.innerText = '\u{1F4E6} Repository Download Totals';
            sub.innerText = 'Total release package downloads aggregated per repository';
          } else if (chartMode === 'cumulative') {
            title.innerText = '\u{1F4C8} Lifetime Downloads (Milestone Growth)';
            sub.innerText = 'Milestone progression tracking all-time downloads as versions were released (counting up)';
          } else if (chartMode === 'monthly') {
            title.innerText = '\u{1F4C5} Monthly Package Downloads';
            sub.innerText = 'Aggregated downloads grouped by release publication timeline';
          } else if (chartMode === 'heatmap') {
            title.innerText = '\u{1F7E9} Package Download Activity Heatmap';
            sub.innerText = '365-day package downloads (daily deltas tracked + release baselines)';
          }
        } else {
          btnRolling.innerText = '\u{1F4E6} By Release Package';
          btnCum.innerText = '\u{1F4C8} Lifetime Cumulative';
          btnMonthly.innerText = '\u{1F4C5} Monthly';

          if (chartMode === 'rolling') {
            title.innerText = `\u{1F4E6} ${chartRepo} Release Packages`;
            sub.innerText = `Downloads breakdown across published versions of ${chartRepo}`;
          } else if (chartMode === 'cumulative') {
            title.innerText = `\u{1F4C8} ${chartRepo} Cumulative Milestone Growth`;
            sub.innerText = `All-time download milestone progression for ${chartRepo}`;
          } else if (chartMode === 'monthly') {
            title.innerText = `\u{1F4C5} ${chartRepo} Monthly Releases`;
            sub.innerText = `Downloads for ${chartRepo} grouped by version release timeline`;
          } else if (chartMode === 'heatmap') {
            title.innerText = `\u{1F7E9} ${chartRepo} Download Activity Heatmap`;
            sub.innerText = `365-day download activity for ${chartRepo} (daily deltas tracked + release baselines)`;
          }
        }
      } else {
        btnRolling.innerText = '14-Day Rolling';
        btnCum.innerText = '\u{1F4C8} Lifetime Cumulative';
        btnMonthly.innerText = 'Monthly';

        const metricName = chartMetric === 'views' ? 'Page Views' : 'Unique Visitors';
        if (chartMode === 'rolling') {
          title.innerText = `${metricName} (14-Day Rolling)`;
          sub.innerText = 'Interactive day-by-day activity for the last two weeks';
        } else if (chartMode === 'cumulative') {
          title.innerText = `\u{1F4C8} Lifetime Cumulative ${metricName} (Counting Up)`;
          sub.innerText = 'Continuous all-time growth timeline preserved permanently in local JSON archive';
        } else if (chartMode === 'monthly') {
          title.innerText = `Monthly ${metricName}`;
          sub.innerText = 'Calendar month aggregations across all recorded days';
        } else if (chartMode === 'heatmap') {
          title.innerText = `\u{1F7E9} ${chartRepo === 'combined' ? 'Combined' : chartRepo} ${metricName} Heatmap`;
          sub.innerText = '365-day rolling activity matrix — daily visitor volume and traffic intensity';
        }
      }

      const note = document.getElementById('chart-repo-note');
      if (chartMode === 'heatmap') {
        const scope = chartRepo === 'combined' ? 'Showing 365-day annual matrix across all projects' : `Filtered specifically to ${chartRepo} annual history`;
        const noteDetail = chartMetric === 'downloads'
          ? ' \u2022 Tracks daily download activity & release milestone deltas'
          : ' \u2022 Rolling 365-day archive (bypasses GitHub\'s 14-day limit)';
        note.innerText = scope + noteDetail;
      } else if (chartRepo === 'combined') {
        note.innerText = 'Showing combined metrics across all projects';
      } else {
        note.innerText = `Filtered specifically to ${chartRepo}`;
      }
    }

    function populateRepoSelect() {
      const select = document.getElementById('chart-repo-select');
      const prevVal = chartRepo;
      select.innerHTML = '<option value="combined">&#x1F310; Combined (All Repositories)</option>';
      
      let eligibleRepos = repos.filter(r => !r.IsFork);
      if (chartMetric === 'downloads') {
        eligibleRepos = eligibleRepos.filter(r => (r.ReleaseCount && r.ReleaseCount > 0) || (r.Downloads && r.Downloads > 0));
      } else {
        eligibleRepos = eligibleRepos.filter(r => (r.Views14Days && r.Views14Days > 0) || (byRepoDaily && byRepoDaily[r.Name]));
      }

      eligibleRepos.forEach(r => {
        const opt = document.createElement('option');
        opt.value = r.Name;
        opt.innerText = r.Name;
        select.appendChild(opt);
      });

      if (prevVal !== 'combined' && !eligibleRepos.some(r => r.Name === prevVal)) {
        chartRepo = 'combined';
        select.value = 'combined';
      } else {
        select.value = chartRepo;
      }
    }

    function initChartControls() {
      populateRepoSelect();
      const select = document.getElementById('chart-repo-select');
      select.addEventListener('change', (e) => {
        chartRepo = e.target.value;
        renderChart();
      });
    }

    function setChartMode(mode) {
      chartMode = mode;
      document.querySelectorAll('.view-mode-btn').forEach(b => b.classList.remove('active'));
      const activeBtn = document.getElementById(`btn-mode-${mode}`);
      if (activeBtn) activeBtn.classList.add('active');
      renderChart();
    }

    function setChartMetric(metric) {
      chartMetric = metric;
      document.querySelectorAll('.chart-metric-btn').forEach(b => b.classList.remove('active'));
      const activeBtn = document.getElementById(`btn-chart-${metric}`);
      if (activeBtn) activeBtn.classList.add('active');
      populateRepoSelect();
      renderChart();
    }

    function getByRepoDaily(repoName) {
      if (!byRepoDaily || !repoName) return null;
      if (byRepoDaily[repoName]) return byRepoDaily[repoName];
      const lower = repoName.toLowerCase();
      for (const k in byRepoDaily) {
        if (k.toLowerCase() === lower) return byRepoDaily[k];
      }
      return null;
    }

    function getRepoDayVal(d, repoName, metric) {
      if (!d || !repoName) return 0;
      const map = metric === 'views' ? d.byRepoDayViews : d.byRepoDayUniques;
      if (map) {
        if (map[repoName] !== undefined) return map[repoName] || 0;
        const lower = repoName.toLowerCase();
        for (const k in map) {
          if (k.toLowerCase() === lower) return map[k] || 0;
        }
      }
      const daily = getByRepoDaily(repoName);
      if (daily && daily[d.date]) {
        return (metric === 'views' ? daily[d.date].views : daily[d.date].uniques) || 0;
      }
      return 0;
    }

    function renderChart() {
      updateChartTitles();
      const chartViewport = document.getElementById('chart-viewport');
      const heatmapContainer = document.getElementById('heatmap-view');

      if (chartMode === 'heatmap') {
        if (chartViewport) chartViewport.style.display = 'none';
        if (heatmapContainer) heatmapContainer.style.display = 'block';
        renderHeatmap();
        return;
      }

      if (chartViewport) chartViewport.style.display = 'flex';
      if (heatmapContainer) heatmapContainer.style.display = 'none';

      const totalLbl = document.getElementById('chart-sum-total-lbl');
      const avgLbl = document.getElementById('chart-sum-avg-lbl');
      const peakLbl = document.getElementById('chart-sum-peak-lbl');
      if (totalLbl) totalLbl.innerText = chartMode === 'monthly' ? 'Period Total:' : (chartMode === 'cumulative' ? 'Cumulative Total:' : 'Period Total:');
      if (avgLbl) avgLbl.innerText = chartMode === 'monthly' ? 'Monthly Average:' : (chartMode === 'rolling' ? 'Daily Average:' : 'Average:');
      if (peakLbl) peakLbl.innerText = chartMode === 'monthly' ? 'Peak Month:' : (chartMode === 'rolling' ? 'Peak Day:' : 'Peak:');

      const track = document.getElementById('bars-track');
      const axis = document.getElementById('bars-axis');
      const yAxis = document.getElementById('chart-y-axis');
      const gridLines = document.getElementById('chart-grid-lines');
      let dataPoints = [];

      if (chartMetric === 'downloads') {
        if (chartRepo === 'combined') {
          if (chartMode === 'rolling') {
            const reposWithDls = repos
              .filter(r => !r.IsFork && ((r.Downloads && r.Downloads > 0) || (r.ReleaseCount && r.ReleaseCount > 0)))
              .sort((a, b) => (b.Downloads || 0) - (a.Downloads || 0));

            dataPoints = reposWithDls.map(r => ({
              label: r.Name,
              value: r.Downloads || 0,
              tooltip: `${r.Name}: ${r.Downloads || 0} total downloads (${r.ReleaseCount || 0} releases)`
            }));
          } else if (chartMode === 'cumulative') {
            const rels = [...allReleases].sort((a, b) => new Date(a.date) - new Date(b.date));
            let runningDl = 0;
            dataPoints = rels.map(r => {
              runningDl += r.downloads;
              return {
                label: r.tag,
                value: runningDl,
                tooltip: `${r.repo} ${r.tag}: +${r.downloads} DLs &rarr; ${runningDl} cumulative all-time (${r.date})`
              };
            });
            if (dataPoints.length > 20) dataPoints = dataPoints.slice(-20);
          } else if (chartMode === 'monthly') {
            const monthMap = {};
            allReleases.forEach(r => {
              const m = r.date.substring(0, 7);
              monthMap[m] = (monthMap[m] || 0) + r.downloads;
            });
            dataPoints = Object.keys(monthMap).sort().map(m => ({
              label: m,
              value: monthMap[m],
              tooltip: `${m}: ${monthMap[m]} downloads across published releases`
            }));
          }
        } else {
          const rels = allReleases
            .filter(r => r.repo.toLowerCase() === chartRepo.toLowerCase())
            .sort((a, b) => new Date(a.date) - new Date(b.date));

          if (chartMode === 'rolling') {
            dataPoints = rels.map(r => ({
              label: r.tag,
              value: r.downloads,
              tooltip: `${r.repo} ${r.tag}: ${r.downloads} downloads (${r.date})`
            }));
          } else if (chartMode === 'cumulative') {
            let runningDl = 0;
            dataPoints = rels.map(r => {
              runningDl += r.downloads;
              return {
                label: r.tag,
                value: runningDl,
                tooltip: `${r.repo} ${r.tag} Milestone: ${runningDl} cumulative downloads (${r.date})`
              };
            });
            if (dataPoints.length > 20) dataPoints = dataPoints.slice(-20);
          } else if (chartMode === 'monthly') {
            const monthMap = {};
            rels.forEach(r => {
              const m = r.date.substring(0, 7);
              monthMap[m] = (monthMap[m] || 0) + r.downloads;
            });
            dataPoints = Object.keys(monthMap).sort().map(m => ({
              label: m,
              value: monthMap[m],
              tooltip: `${m}: ${monthMap[m]} downloads for ${chartRepo}`
            }));
          }
        }
      } else {
        if (chartMode === 'rolling') {
          dataPoints = rolling14Data.map(d => {
            let val = 0;
            if (chartRepo === 'combined') {
              val = chartMetric === 'views' ? d.views : d.uniques;
            } else {
              const repoDaily = getByRepoDaily(chartRepo);
              if (repoDaily && repoDaily[d.date]) {
                val = chartMetric === 'views' ? (repoDaily[d.date].views || 0) : (repoDaily[d.date].uniques || 0);
              }
            }
            const dt = new Date(d.date + 'T00:00:00');
            const lbl = dt.toLocaleDateString('en-US', { month: 'numeric', day: 'numeric' });
            return {
              label: lbl,
              value: val,
              tooltip: `${d.date}: ${val} ${chartMetric === 'views' ? 'views' : 'unique visitors'}`
            };
          });
        } else if (chartMode === 'cumulative') {
          let running = 0;
          dataPoints = cumulativeYearData.map(d => {
            let dayVal = 0;
            if (chartRepo === 'combined') {
              dayVal = chartMetric === 'views' ? d.dayViews : d.dayUniques;
            } else {
              dayVal = getRepoDayVal(d, chartRepo, chartMetric);
            }
            running += dayVal;
            const dt = new Date(d.date + 'T00:00:00');
            const lbl = dt.toLocaleDateString('en-US', { month: 'numeric', day: 'numeric' });
            return {
              label: lbl,
              value: running,
              tooltip: `${d.date}: ${running} cumulative ${chartMetric === 'views' ? 'views' : 'uniques'} (counting up)`
            };
          });
          if (dataPoints.length > 25) {
            const step = Math.ceil(dataPoints.length / 20);
            dataPoints = dataPoints.filter((_, i) => i % step === 0 || i === dataPoints.length - 1);
          }
        } else if (chartMode === 'monthly') {
          const monthMap = {};
          cumulativeYearData.forEach(d => {
            const m = d.date.substring(0, 7);
            let dayVal = 0;
            if (chartRepo === 'combined') {
              dayVal = chartMetric === 'views' ? d.dayViews : d.dayUniques;
            } else {
              dayVal = getRepoDayVal(d, chartRepo, chartMetric);
            }
            monthMap[m] = (monthMap[m] || 0) + dayVal;
          });
          if (chartRepo !== 'combined') {
            const rDaily = getByRepoDaily(chartRepo) || {};
            Object.keys(rDaily).forEach(dt => {
              const m = dt.substring(0, 7);
              if (!cumulativeYearData.some(c => c.date === dt)) {
                const val = chartMetric === 'views' ? (rDaily[dt].views || 0) : (rDaily[dt].uniques || 0);
                monthMap[m] = (monthMap[m] || 0) + val;
              }
            });
          }
          dataPoints = Object.keys(monthMap).sort().map(m => ({
            label: m,
            value: monthMap[m],
            tooltip: `${m}: ${monthMap[m]} ${chartMetric === 'views' ? 'views' : 'uniques'}`
          }));
        }
      }

      if (dataPoints.length === 0) {
        track.innerHTML = '<div style="margin: auto; color: #94a3b8; font-size: 0.85rem;">No activity data recorded yet for this view.</div>';
        axis.innerHTML = '';
        if (yAxis) yAxis.innerHTML = '';
        if (gridLines) gridLines.innerHTML = '';
        document.getElementById('chart-sum-total').innerText = '0';
        document.getElementById('chart-sum-avg').innerText = '0';
        document.getElementById('chart-sum-peak').innerText = '-';
        return;
      }

      const maxVal = Math.max(...dataPoints.map(d => d.value), 1);
      const sumVal = dataPoints.reduce((acc, d) => acc + d.value, 0);
      const avgVal = (sumVal / dataPoints.length).toFixed(1);
      const peakItem = dataPoints.reduce((max, d) => d.value > max.value ? d : max, dataPoints[0]);

      document.getElementById('chart-sum-total').innerText = sumVal.toLocaleString();
      document.getElementById('chart-sum-avg').innerText = avgVal;
      document.getElementById('chart-sum-peak').innerText = `${peakItem.value} (${peakItem.label})`;

      // Calculate nice Y-axis ticks
      let ticks = [];
      if (maxVal <= 3) {
        ticks = [3, 2, 1, 0];
      } else if (maxVal <= 6) {
        ticks = [maxVal, Math.ceil(maxVal / 2), 0];
      } else if (maxVal <= 12) {
        ticks = [maxVal, Math.round(maxVal / 2), 0];
      } else {
        const step = Math.ceil(maxVal / 3);
        ticks = [maxVal, step * 2, step, 0];
      }

      const scaleMax = (ticks && ticks.length > 0 && ticks[0] > 0) ? ticks[0] : maxVal;

      if (yAxis) {
        yAxis.innerHTML = ticks.map(t => `<span>${t >= 1000 ? (t / 1000).toFixed(1) + 'k' : t}</span>`).join('');
      }
      if (gridLines) {
        gridLines.innerHTML = ticks.map(() => '<div class="chart-grid-line"></div>').join('');
      }

      const isRollingMode = (chartMode === 'rolling' && chartMetric !== 'downloads');

      track.innerHTML = dataPoints.map((d, idx) => {
        const isToday = isRollingMode && (idx === dataPoints.length - 1);
        const isZero = (d.value === 0);
        const pct = isZero ? 0 : Math.max(Math.round((d.value / scaleMax) * 100), 6);

        let valLabel = '';
        if (!isZero) {
          const liveClass = isToday ? 'today-live' : '';
          valLabel = `<span class="bar-val ${liveClass}">${d.value}</span>`;
        } else if (isToday) {
          valLabel = `<span class="bar-val today-zero" title="0 activity so far today">0</span>`;
        }

        const todayClass = isToday ? 'is-today' : '';
        const zeroClass = isZero ? 'is-zero' : '';

        return `
          <div class="bar-col ${todayClass} ${zeroClass}" title="${d.tooltip}">
            ${valLabel}
            <div class="bar-fill" style="height: ${pct}%;"></div>
            ${isZero ? '<div class="zero-baseline-dot"></div>' : ''}
          </div>
        `;
      }).join('');

      axis.innerHTML = dataPoints.map((d, idx) => {
        const isToday = isRollingMode && (idx === dataPoints.length - 1);
        if (isToday) {
          return `<span class="x-label is-today">${d.label}<span class="today-badge">TODAY</span></span>`;
        }
        return `<span class="x-label">${d.label}</span>`;
      }).join('');
    }

    /* ------------------- 365-DAY ACTIVITY HEATMAP ------------------- */
    function renderHeatmap() {
      const heatmapContainer = document.getElementById('heatmap-view');
      if (!heatmapContainer) return;

      const activityMap = {};
      if (chartMetric === 'downloads') {
        // Group historical snapshots by calendar day (taking the latest snapshot for each date)
        const dailySnapshots = {};
        const sortedHist = [...historyData].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
        sortedHist.forEach(s => {
          const dt = (s.timestamp || '').substring(0, 10);
          if (dt) dailySnapshots[dt] = s;
        });

        const dailyDeltas = {};
        const recordedRepoDeltas = {};
        let recordedCombinedDelta = 0;

        const sortedDays = Object.keys(dailySnapshots).sort();
        for (let i = 1; i < sortedDays.length; i++) {
          const prevDay = sortedDays[i - 1];
          const currDay = sortedDays[i];
          const prev = dailySnapshots[prevDay];
          const curr = dailySnapshots[currDay];

          const cDelta = Math.max(0, (curr.totalDownloads || 0) - (prev.totalDownloads || 0));
          if (!dailyDeltas[currDay]) dailyDeltas[currDay] = { combined: 0, byRepo: {} };
          dailyDeltas[currDay].combined += cDelta;
          recordedCombinedDelta += cDelta;

          if (Array.isArray(curr.repos)) {
            curr.repos.forEach(cr => {
              const rName = (cr.Name || '').toLowerCase();
              const pr = Array.isArray(prev.repos) ? prev.repos.find(r => (r.Name || '').toLowerCase() === rName) : null;
              const prevDl = pr ? (pr.Downloads || 0) : 0;
              const rDelta = Math.max(0, (cr.Downloads || 0) - prevDl);
              if (rDelta > 0) {
                dailyDeltas[currDay].byRepo[rName] = (dailyDeltas[currDay].byRepo[rName] || 0) + rDelta;
                recordedRepoDeltas[rName] = (recordedRepoDeltas[rName] || 0) + rDelta;
              }
            });
          }
        }

        if (chartRepo === 'combined') {
          // Add release packages baseline
          allReleases.forEach(r => {
            if (r.date) {
              activityMap[r.date] = (activityMap[r.date] || 0) + (r.downloads || 0);
            }
          });
          // Rebalance: deduct recorded deltas from earliest publish dates so total matches exact all-time
          let remainingToDeduct = recordedCombinedDelta;
          Object.keys(activityMap).sort().forEach(dt => {
            if (remainingToDeduct <= 0) return;
            const deduct = Math.min(activityMap[dt], remainingToDeduct);
            activityMap[dt] -= deduct;
            remainingToDeduct -= deduct;
          });
          // Add actual daily download activity on the days they occurred
          Object.keys(dailyDeltas).forEach(dt => {
            if (dailyDeltas[dt].combined > 0) {
              activityMap[dt] = (activityMap[dt] || 0) + dailyDeltas[dt].combined;
            }
          });
        } else {
          // Single repository
          const targetRepo = chartRepo.toLowerCase();
          const repoReleases = allReleases.filter(r => (r.repo || '').toLowerCase() === targetRepo);
          repoReleases.forEach(r => {
            if (r.date) {
              activityMap[r.date] = (activityMap[r.date] || 0) + (r.downloads || 0);
            }
          });

          // Rebalance baseline
          let remainingToDeduct = recordedRepoDeltas[targetRepo] || 0;
          Object.keys(activityMap).sort().forEach(dt => {
            if (remainingToDeduct <= 0) return;
            const deduct = Math.min(activityMap[dt], remainingToDeduct);
            activityMap[dt] -= deduct;
            remainingToDeduct -= deduct;
          });

          // Add actual daily download activity on the days they occurred
          Object.keys(dailyDeltas).forEach(dt => {
            const rDelta = (dailyDeltas[dt].byRepo && dailyDeltas[dt].byRepo[targetRepo]) || 0;
            if (rDelta > 0) {
              activityMap[dt] = (activityMap[dt] || 0) + rDelta;
            }
          });
        }
      } else {
        if (chartRepo === 'combined') {
          cumulativeYearData.forEach(d => {
            const val = chartMetric === 'views' ? (d.dayViews || 0) : (d.dayUniques || 0);
            activityMap[d.date] = val;
          });
        } else {
          cumulativeYearData.forEach(d => {
            const val = getRepoDayVal(d, chartRepo, chartMetric);
            if (val > 0) activityMap[d.date] = val;
          });
          const repoDaily = getByRepoDaily(chartRepo) || {};
          Object.keys(repoDaily).forEach(dt => {
            const val = chartMetric === 'views' ? (repoDaily[dt].views || 0) : (repoDaily[dt].uniques || 0);
            if (val > 0 && !activityMap[dt]) activityMap[dt] = val;
          });
        }
      }

      const today = new Date();
      const pad = n => String(n).padStart(2, '0');
      const todayObj = new Date(today.getFullYear(), today.getMonth(), today.getDate());
      const todayStr = `${todayObj.getFullYear()}-${pad(todayObj.getMonth() + 1)}-${pad(todayObj.getDate())}`;

      const todayDayOfWeek = todayObj.getDay(); // 0 is Sunday
      const startDate = new Date(todayObj.getFullYear(), todayObj.getMonth(), todayObj.getDate() - todayDayOfWeek - (52 * 7));

      const weeks = [];
      let curWeek = [];
      let curDate = new Date(startDate);

      let totalActivity = 0;
      let activeDaysCount = 0;
      let peakVal = 0;
      let peakDate = '-';

      while (curDate <= todayObj || curDate.getDay() !== 0) {
        if (curDate.getDay() === 0 && curWeek.length > 0) {
          weeks.push(curWeek);
          curWeek = [];
        }

        const dStr = `${curDate.getFullYear()}-${pad(curDate.getMonth() + 1)}-${pad(curDate.getDate())}`;
        const isFuture = curDate > todayObj;
        const val = isFuture ? 0 : (activityMap[dStr] || 0);

        if (!isFuture) {
          totalActivity += val;
          if (val > 0) activeDaysCount++;
          if (val > peakVal) {
            peakVal = val;
            peakDate = dStr;
          }
        }

        curWeek.push({
          date: dStr,
          val: val,
          isToday: (dStr === todayStr),
          isFuture: isFuture,
          dayOfWeek: curDate.getDay()
        });

        curDate.setDate(curDate.getDate() + 1);
      }
      if (curWeek.length > 0) {
        weeks.push(curWeek);
      }

      const totalLbl = document.getElementById('chart-sum-total-lbl');
      const avgLbl = document.getElementById('chart-sum-avg-lbl');
      const peakLbl = document.getElementById('chart-sum-peak-lbl');
      if (totalLbl) totalLbl.innerText = 'Annual Total:';
      if (avgLbl) avgLbl.innerText = 'Active Days:';
      if (peakLbl) peakLbl.innerText = 'Busiest Day:';

      const metricNoun = chartMetric === 'downloads' ? 'DLs' : (chartMetric === 'views' ? 'Views' : 'Visitors');
      document.getElementById('chart-sum-total').innerText = totalActivity.toLocaleString();
      document.getElementById('chart-sum-avg').innerText = `${activeDaysCount} days`;
      document.getElementById('chart-sum-peak').innerText = peakVal > 0 ? `${peakVal} ${metricNoun} (${peakDate})` : '-';

      function getHeatClass(v) {
        if (v <= 0) return 'heat-lvl-0';
        if (peakVal <= 4) {
          if (v === 1) return 'heat-lvl-1';
          if (v === 2) return 'heat-lvl-2';
          if (v === 3) return 'heat-lvl-3';
          return 'heat-lvl-4';
        }
        const q1 = Math.max(1, Math.round(peakVal * 0.2));
        const q2 = Math.max(2, Math.round(peakVal * 0.45));
        const q3 = Math.max(3, Math.round(peakVal * 0.75));
        if (v <= q1) return 'heat-lvl-1';
        if (v <= q2) return 'heat-lvl-2';
        if (v <= q3) return 'heat-lvl-3';
        return 'heat-lvl-4';
      }

      const monthLabels = [];
      let lastMonth = -1;
      let lastWeekIdx = -5;

      weeks.forEach((w, wIdx) => {
        const firstDayOfMonth = w.find(d => !d.isFuture && new Date(d.date + 'T00:00:00').getDate() <= 7);
        if (firstDayOfMonth) {
          const dt = new Date(firstDayOfMonth.date + 'T00:00:00');
          const mIdx = dt.getMonth();
          if (mIdx !== lastMonth && (wIdx - lastWeekIdx) >= 3) {
            monthLabels.push({
              weekIdx: wIdx,
              monthName: dt.toLocaleDateString('en-US', { month: 'short' })
            });
            lastMonth = mIdx;
            lastWeekIdx = wIdx;
          }
        }
      });

      let monthsHtml = `<div style="position: relative; height: 16px; margin-bottom: 6px; margin-left: 32px; width: ${weeks.length * 15}px;">`;
      monthLabels.forEach(m => {
        const leftPx = m.weekIdx * 15;
        monthsHtml += `<span style="position: absolute; left: ${leftPx}px; font-size: 0.68rem; color: #94a3b8; font-family: 'JetBrains Mono', monospace;">${m.monthName}</span>`;
      });
      monthsHtml += `</div>`;

      let gridHtml = '';
      weeks.forEach(w => {
        gridHtml += '<div class="heatmap-week">';
        w.forEach(d => {
          if (d.isFuture) {
            gridHtml += '<div class="heatmap-cell" style="visibility: hidden;"></div>';
          } else {
            const lvlClass = getHeatClass(d.val);
            const todayClass = d.isToday ? 'is-today' : '';
            const title = `${d.date}: ${d.val} ${metricNoun}${d.isToday ? ' (Today)' : ''}`;
            gridHtml += `<div class="heatmap-cell ${lvlClass} ${todayClass}" title="${title}"></div>`;
          }
        });
        gridHtml += '</div>';
      });

      heatmapContainer.innerHTML = `
        <div class="heatmap-wrap">
          ${monthsHtml}
          <div class="heatmap-body">
            <div class="heatmap-days-legend">
              <span></span>
              <span>Mon</span>
              <span></span>
              <span>Wed</span>
              <span></span>
              <span>Fri</span>
              <span></span>
            </div>
            <div class="heatmap-grid">
              ${gridHtml}
            </div>
          </div>
          <div class="heatmap-footer">
            <span>Less</span>
            <div class="heatmap-legend-cells">
              <div class="heatmap-cell heat-lvl-0" title="0 activity"></div>
              <div class="heatmap-cell heat-lvl-1" title="Low activity"></div>
              <div class="heatmap-cell heat-lvl-2" title="Medium activity"></div>
              <div class="heatmap-cell heat-lvl-3" title="High activity"></div>
              <div class="heatmap-cell heat-lvl-4" title="Peak activity"></div>
            </div>
            <span>More</span>
          </div>
        </div>
      `;
    }

    /* ------------------- REPO HEALTH & CONVERSIONS LOGIC ------------------- */
    function calculateRepoHealth(r) {
      let score = 0;
      let breakdown = [];

      // 1. Recency & Maintenance (Max 30 pts)
      const daysSincePush = r.PushedAt ? Math.floor((new Date() - new Date(r.PushedAt)) / (1000 * 86400)) : 999;
      if (daysSincePush <= 14) {
        score += 30;
        breakdown.push({ label: 'Recent commit (<= 14d)', pts: '+30' });
      } else if (daysSincePush <= 30) {
        score += 25;
        breakdown.push({ label: 'Active commit (<= 30d)', pts: '+25' });
      } else if (daysSincePush <= 90) {
        score += 18;
        breakdown.push({ label: 'Committed (<= 90d)', pts: '+18' });
      } else if (daysSincePush <= 180) {
        score += 10;
        breakdown.push({ label: 'Committed (<= 6mo)', pts: '+10' });
      } else {
        score += 5;
        breakdown.push({ label: 'Stale (> 6mo)', pts: '+5' });
      }

      // 2. Packaging & Docs Hygiene (Max 30 pts)
      let hygienePts = 0;
      if (r.Description && r.Description !== 'No description provided.') hygienePts += 8;
      if (r.License && r.License !== 'Custom' && r.License !== 'None') hygienePts += 8;
      if (r.Topics && r.Topics.length > 0) hygienePts += 7;
      if (r.ReleaseCount && r.ReleaseCount > 0) hygienePts += 7;
      score += hygienePts;
      breakdown.push({ label: 'Docs, License & Releases', pts: `+${hygienePts}/30` });

      // 3. Traction & Adoption (Max 25 pts)
      let tractionPts = 0;
      if (r.Stars >= 5) tractionPts += 10;
      else if (r.Stars >= 1) tractionPts += 7;
      else tractionPts += 3;

      if (r.Downloads >= 20 || r.Clones14Days >= 20) tractionPts += 15;
      else if (r.Downloads > 0 || r.Clones14Days > 0) tractionPts += 10;
      else tractionPts += 3;
      score += tractionPts;
      breakdown.push({ label: 'Stars, Clones & Downloads', pts: `+${tractionPts}/25` });

      // 4. Issue Management (Max 15 pts)
      let issuePts = 0;
      if (r.OpenIssues === 0) issuePts = 15;
      else if (r.OpenIssues <= 2) issuePts = 12;
      else if (r.OpenIssues <= 5) issuePts = 8;
      else issuePts = 4;
      score += issuePts;
      breakdown.push({ label: `Clean backlog (${r.OpenIssues} open)`, pts: `+${issuePts}/15` });

      score = Math.min(Math.max(score, 0), 100);

      let status = 'Healthy';
      let color = '#34d399';
      let bg = 'rgba(52, 211, 153, 0.15)';
      let border = 'rgba(52, 211, 153, 0.3)';

      if (score >= 85) {
        status = 'Prime';
        color = '#10b981';
        bg = 'rgba(16, 185, 129, 0.15)';
        border = 'rgba(16, 185, 129, 0.35)';
      } else if (score >= 70) {
        status = 'Healthy';
        color = '#38bdf8';
        bg = 'rgba(56, 189, 248, 0.15)';
        border = 'rgba(56, 189, 248, 0.35)';
      } else if (score >= 50) {
        status = 'Moderate';
        color = '#fbbf24';
        bg = 'rgba(251, 191, 36, 0.15)';
        border = 'rgba(251, 191, 36, 0.35)';
      } else {
        status = 'Attention';
        color = '#f87171';
        bg = 'rgba(248, 113, 113, 0.15)';
        border = 'rgba(248, 113, 113, 0.35)';
      }

      return { score, status, color, bg, border, breakdown, daysSincePush };
    }

    function calculateRepoConversions(r) {
      const rawViews = r.Views14Days || 0;
      const allTimeViews = r.AllTimeViews || rawViews;
      const uniqueClones = r.UniqueClones14Days || 0;
      const totalClones = r.Clones14Days || 0;
      
      const botPulls = Math.max(0, totalClones - uniqueClones);
      const botPercent = totalClones > 0 ? Math.round((botPulls / totalClones) * 100) : 0;
      const cloneRepeat = uniqueClones > 0 ? (totalClones / uniqueClones).toFixed(1) : 1;

      // 14-day human cloners conversion
      const cloneRateNum = rawViews > 0 ? Math.min(100, (uniqueClones / rawViews) * 100) : 0;

      // Ground star & download conversions in lifetime visitors
      const baseVisitors = Math.max(allTimeViews, rawViews, 0);
      const starRateNum = baseVisitors > 0 ? Math.min(100, (r.Stars / baseVisitors) * 100) : (r.Stars > 0 ? 100 : 0);
      const starRate = starRateNum.toFixed(1);
      const dlMultiplier = baseVisitors > 0 ? (r.Downloads / baseVisitors).toFixed(1) : (r.Downloads > 0 ? '1.0' : '0.0');
      const dlRateNum = baseVisitors > 0 ? Math.min(100, (r.Downloads / Math.max(baseVisitors, r.Downloads)) * 100) : (r.Downloads > 0 ? 100 : 0);

      // Today's traffic pulse
      let todayViews = r.ViewsToday || 0;
      let todayUniques = r.UniquesToday || 0;

      if (!todayViews && byRepoDaily && byRepoDaily[r.Name]) {
        const now = new Date();
        const pad = n => String(n).padStart(2, '0');
        const localToday = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
        const utcToday = now.toISOString().split('T')[0];
        const rDaily = byRepoDaily[r.Name];
        if (rDaily[localToday]) {
          todayViews = rDaily[localToday].views || 0;
          todayUniques = rDaily[localToday].uniques || 0;
        } else if (rDaily[utcToday]) {
          todayViews = rDaily[utcToday].views || 0;
          todayUniques = rDaily[utcToday].uniques || 0;
        }
      }

      let persona = 'Hybrid Dev/App';
      let personaIcon = '&#x2696;&#xFE0F;';
      if (totalClones > 0 && r.Downloads === 0) {
        persona = 'Dev Code';
        personaIcon = '&#x1F6E0;&#xFE0F;';
      } else if (r.Downloads > 0 && r.Downloads >= totalClones) {
        persona = 'App Utility';
        personaIcon = '&#x1F4E6;';
      } else if (totalClones > r.Downloads) {
        persona = 'Dev Heavy';
        personaIcon = '&#x1F4BB;';
      } else if (r.Downloads > 0) {
        persona = 'Dual Audience';
        personaIcon = '&#x1F504;';
      }

      return {
        rawViews,
        allTimeViews,
        baseVisitors,
        dlRate: dlRateNum.toFixed(1),
        dlMultiplier,
        starRate,
        cloneRate: cloneRateNum.toFixed(1),
        dlRateNum,
        starRateNum,
        cloneRateNum,
        uniqueClones,
        totalClones,
        botPulls,
        botPercent,
        cloneRepeat,
        persona,
        personaIcon,
        todayViews,
        todayUniques
      };
    }

    function renderFunnelSection() {
      const container = document.getElementById('funnel-cards-container');
      const flow = document.getElementById('funnel-flow-container');
      if (!container || !flow) return;

      const totalStars = repos.reduce((acc, r) => acc + (r.Stars || 0), 0);
      const totalDownloads = repos.reduce((acc, r) => acc + (r.Downloads || 0), 0);
      const total14dClones = repos.reduce((acc, r) => acc + (r.Clones14Days || 0), 0);
      const total14dUniqueClones = repos.reduce((acc, r) => acc + (r.UniqueClones14Days || 0), 0);
      const total14dViews = Math.max(repos.reduce((acc, r) => acc + (r.Views14Days || 0), 0), 1);

      let totalVisitors = 0;
      if (cumulativeYearData && cumulativeYearData.length > 0) {
        totalVisitors = cumulativeYearData.reduce((acc, d) => acc + (d.dayUniques || 0), 0);
      }
      if (totalVisitors === 0) {
        totalVisitors = repos.reduce((acc, r) => acc + (r.Uniques14Days || 0), 0);
      }
      totalVisitors = Math.max(totalVisitors, total14dViews, 1);

      const starRate = Math.min(100, ((totalStars / totalVisitors) * 100)).toFixed(1);
      const dlMultiplier = (totalDownloads / totalVisitors).toFixed(1);

      const totalGitPulls = Math.max(total14dClones, total14dUniqueClones);
      const humanPulls = total14dUniqueClones;
      const botPullsTotal = Math.max(0, totalGitPulls - humanPulls);
      const humanPercent = totalGitPulls > 0 ? Math.round((humanPulls / totalGitPulls) * 100) : 100;
      const botPercent = 100 - humanPercent;

      const isDevPersona = total14dClones >= totalDownloads;
      const personaTitle = isDevPersona ? 'Developer & Infra' : 'Consumer Utility';
      const personaPill = isDevPersona ? '&#x1F6E0;&#xFE0F; High Git Clones' : '&#x1F4E6; High Release DLs';

      container.innerHTML = `
        <div class="funnel-card">
          <div class="funnel-card-header">
            <span class="funnel-card-label">Star Conversion</span>
            <span class="funnel-pill" style="background: rgba(251, 191, 36, 0.15); color: #fbbf24;">README Appeal</span>
          </div>
          <div class="funnel-card-val" style="color: #fbbf24;">${starRate}%</div>
          <div class="funnel-card-formula">${totalStars} stars &divide; ${totalVisitors} unique visitors</div>
          <p class="funnel-card-desc">Percentage of visitors who intentionally bookmarked or starred your repositories.</p>
        </div>

        <div class="funnel-card">
          <div class="funnel-card-header">
            <span class="funnel-card-label">Release Asset Adoption</span>
            <span class="funnel-pill" style="background: rgba(52, 211, 153, 0.15); color: #34d399;">High Utility</span>
          </div>
          <div class="funnel-card-val" style="color: #34d399;">${dlMultiplier}x</div>
          <div class="funnel-card-formula">${totalDownloads} downloads &divide; ${totalVisitors} visitors</div>
          <p class="funnel-card-desc">Average release packages downloaded per discovery visitor (${dlMultiplier}x adoption).</p>
        </div>

        <div class="funnel-card">
          <div class="funnel-card-header">
            <span class="funnel-card-label">Developer Cloners</span>
            <span class="funnel-pill" style="background: rgba(56, 189, 248, 0.15); color: #38bdf8;">&#x1F464; Human Intent</span>
          </div>
          <div class="funnel-card-val" style="color: #38bdf8;">${humanPulls} <span style="font-size: 0.95rem; font-weight: 600; color: #94a3b8;">devs (${humanPercent}% human)</span></div>
          <div class="funnel-card-formula">${humanPulls} unique machines out of ${totalGitPulls} git pulls (14d)</div>
          <p class="funnel-card-desc">Distinct developers or client machines pulling codebase locally (${humanPercent}% human vs ${botPercent}% automated).</p>
        </div>

        <div class="funnel-card">
          <div class="funnel-card-header">
            <span class="funnel-card-label">Robot &amp; CI Filter</span>
            <span class="funnel-pill" style="background: rgba(248, 113, 113, 0.15); color: #f87171;">&#x1F916; ${botPercent}% Automated</span>
          </div>
          <div class="funnel-card-val" style="color: #f87171;">${botPullsTotal} <span style="font-size: 0.95rem; font-weight: 600; color: #94a3b8;">auto pulls</span></div>
          <div class="funnel-card-formula">${botPullsTotal} repeat cron/CI syncs filtered</div>
          <p class="funnel-card-desc">Automated bot activity: cron jobs, Docker builds, and daemons checking updates.</p>
        </div>

        <div class="funnel-card">
          <div class="funnel-card-header">
            <span class="funnel-card-label">Audience Persona</span>
            <span class="funnel-pill" style="background: rgba(129, 140, 248, 0.15); color: #818cf8;">Profile</span>
          </div>
          <div class="funnel-card-val" style="color: #818cf8; font-size: 1.45rem;">${personaTitle}</div>
          <div class="funnel-card-formula">${personaPill}</div>
          <p class="funnel-card-desc">Audience breakdown based on Git clone vs release package ratio.</p>
        </div>
      `;

      flow.innerHTML = `
        <div class="stage-pill pill-visitors" title="Total unique visitors: ${totalVisitors}">
          &#x1F441;&#xFE0F; <strong>${totalVisitors}</strong> Visitors (100%)
        </div>

        <div class="stage-pill pill-devs" title="${humanPulls} unique client machines (${humanPercent}% human intent out of ${totalGitPulls} total git pulls)">
          &#x1F464; <strong>${humanPulls}</strong> Devs (${humanPercent}% human)
        </div>

        <div class="stage-pill pill-downloads" title="Release Downloads: ${totalDownloads} packages total (${dlMultiplier}x adoption per visitor)">
          &#x1F4E5; <strong>${totalDownloads}</strong> Downloads (${dlMultiplier}x)
        </div>

        <div class="stage-pill pill-stars" title="Stars: ${totalStars} total stars (${starRate}% conversion rate)">
          &#x2B50; <strong>${totalStars}</strong> Stars (${starRate}%)
        </div>

        <div class="stage-pill pill-bots" title="Automated repeat git pulls filtered from human stats: ${botPullsTotal} pulls (${botPercent}%)">
          &#x1F916; <strong>${botPullsTotal}</strong> Bots (${botPercent}% auto)
        </div>
      `;
    }

    /* ------------------- REPO CARDS RENDERING ------------------- */
    function render() {
      const container = document.getElementById('repo-container');
      
      const hasForks = repos.some(r => r.IsFork);
      const forkBtn = document.querySelector('[data-filter="fork"]');
      const srcBtn = document.querySelector('[data-filter="source"]');
      const allBtn = document.querySelector('[data-filter="all"]');
      
      if (!hasForks) {
        if (forkBtn) forkBtn.style.display = 'none';
        if (srcBtn) srcBtn.style.display = 'none';
        if (allBtn) {
          allBtn.classList.add('active');
          allBtn.innerHTML = `All Projects (<span id="count-all">${repos.length}</span>)`;
        }
        currentFilter = 'all';
      } else {
        if (document.getElementById('count-all')) document.getElementById('count-all').innerText = repos.length;
        if (document.getElementById('count-src')) document.getElementById('count-src').innerText = repos.filter(r => !r.IsFork).length;
        if (document.getElementById('count-fork')) document.getElementById('count-fork').innerText = repos.filter(r => r.IsFork).length;
      }

      let filtered = repos.filter(r => {
        if (currentFilter === 'source' && r.IsFork) return false;
        if (currentFilter === 'fork' && !r.IsFork) return false;
        if (searchQuery) {
          const q = searchQuery.toLowerCase();
          const matchName = (r.Name || '').toLowerCase().includes(q);
          const matchDesc = (r.Description || '').toLowerCase().includes(q);
          const matchTopics = (r.Topics || []).some(t => String(t).toLowerCase().includes(q));
          const matchLang = (r.Language || '').toLowerCase().includes(q);
          const matchLicense = (r.License || '').toLowerCase().includes(q);
          return matchName || matchDesc || matchTopics || matchLang || matchLicense;
        }
        return true;
      });

      filtered.sort((a, b) => {
        if (currentSort === 'downloads') return b.Downloads - a.Downloads || b.Stars - a.Stars;
        if (currentSort === 'health') return calculateRepoHealth(b).score - calculateRepoHealth(a).score || b.Downloads - a.Downloads;
        if (currentSort === 'starRate') return calculateRepoConversions(b).starRateNum - calculateRepoConversions(a).starRateNum || b.Stars - a.Stars;
        if (currentSort === 'views') return b.Views14Days - a.Views14Days || b.Downloads - a.Downloads;
        if (currentSort === 'stars') return b.Stars - a.Stars || b.Downloads - a.Downloads;
        if (currentSort === 'pushed') return new Date(b.PushedAt) - new Date(a.PushedAt);
        if (currentSort === 'name') return a.Name.localeCompare(b.Name);
        return 0;
      });

      if (filtered.length === 0) {
        container.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 4rem; color: #94a3b8;">No repositories matched your filters.</div>';
        return;
      }

      container.innerHTML = filtered.map(r => {
        const langColor = languageColors[r.Language] || '#38bdf8';
        const topics = (Array.isArray(r.Topics) ? r.Topics : [])
          .filter(t => typeof t === 'string' && t.trim().length > 0 && t !== '[object Object]');
        const topicsHtml = topics.slice(0, 6).map(t => `<span class="topic-tag">#${t.trim()}</span>`).join('');
        const extraTopics = topics.length > 6 ? `<span class="topic-tag">+${topics.length - 6}</span>` : '';
        const badge = r.IsFork ? '<span class="badge-fork">&#x1F500; Fork</span>' : '<span class="badge-source">&#x2728; Original</span>';
        const releaseBadge = r.LatestReleaseTag ? `<span class="badge-release" title="Latest release: ${r.LatestReleaseTag}">&#x1F4E6; ${r.LatestReleaseTag}</span>` : '';

        const licenseBadge = r.License ? `<span class="badge-license" title="License: ${r.License}">${r.License}</span>` : '';

        const h = calculateRepoHealth(r);
        const b1 = (h.breakdown && h.breakdown[1]) ? h.breakdown[1].pts : '';
        const b2 = (h.breakdown && h.breakdown[2]) ? h.breakdown[2].pts : '';
        const b3 = (h.breakdown && h.breakdown[3]) ? h.breakdown[3].pts : '';
        const healthTooltip = `${r.Name} Repository Health: ${h.score}/100 (${h.status})&#10;&bull; Last push: ${h.daysSincePush <= 14 ? 'Recent (<=14d)' : h.daysSincePush + 'd ago'}&#10;&bull; Hygiene: ${b1}&#10;&bull; Traction: ${b2}&#10;&bull; Backlog: ${b3}`;

        const conv = calculateRepoConversions(r);
        const allTimeViewsVal = r.AllTimeViews || r.Views14Days || 0;

        return `
          <div class="repo-card">
            <div>
              <div class="repo-header">
                <div style="display: flex; align-items: center; flex-wrap: wrap; gap: 0.4rem;">
                  <a class="repo-name" href="${r.HtmlUrl}" target="_blank" rel="noopener noreferrer">${r.Name}</a>
                  ${badge}
                  ${releaseBadge}
                </div>
              </div>

              <!-- Health Meter -->
              <div class="repo-health-strip" title="${healthTooltip}">
                <div class="health-meta">
                  <span style="color: ${h.color};">${h.score}% Health</span>
                  <span style="color: ${h.color}; font-size: 0.7rem; padding: 0.1rem 0.4rem; border-radius: 4px; background: ${h.bg}; border: 1px solid ${h.border};">${h.status}</span>
                </div>
                <div class="health-bar-bg" title="Health Score: ${h.score}%">
                  <div class="health-bar-fill" style="width: ${h.score}%; background: ${h.color};"></div>
                </div>
              </div>

              <p class="repo-desc" title="${r.Description}">${r.Description}</p>

              <div>
                ${topicsHtml} ${extraTopics}
              </div>
            </div>

            <div>
              <div class="metrics-bar">
                <div class="metric-item">
                  <span class="metric-val" style="color: #fbbf24;">&#x2B50; ${r.Stars}</span>
                  <span class="metric-lbl">Stars</span>
                </div>
                <div class="metric-item" title="${r.ReleaseCount} releases total">
                  <span class="metric-val" style="color: #34d399;">&#x1F4E5; ${r.Downloads}</span>
                  <span class="metric-lbl">Downloads</span>
                </div>
                <div class="metric-item" title="14-day page views: ${r.Views14Days} (${r.Uniques14Days} unique visitors) &bull; Lifetime archived views: ${allTimeViewsVal}">
                  <span class="metric-val" style="color: #38bdf8;">&#x1F441;&#xFE0F; ${r.Views14Days} <span style="font-size: 0.72rem; font-weight: 500; color: #94a3b8;" title="Lifetime archived views">(${allTimeViewsVal})</span></span>
                  <span class="metric-lbl">Views (14d/All)</span>
                </div>
                <div class="metric-item">
                  <span class="metric-val" style="color: #c084fc;">&#x1F500; ${r.Forks}</span>
                  <span class="metric-lbl">Forks</span>
                </div>
                <div class="metric-item">
                  <span class="metric-val" style="color: #f87171;">&#x25C9; ${r.OpenIssues}</span>
                  <span class="metric-lbl">Issues</span>
                </div>
              </div>

              <div class="repo-conv-bar">
                <span class="conv-tag conv-tag-today ${conv.todayUniques > 0 ? 'active' : ''}" title="${conv.todayUniques > 0 ? `${conv.todayUniques} unique visitor${conv.todayUniques === 1 ? '' : 's'} (${conv.todayViews} page view${conv.todayViews === 1 ? '' : 's'}) recorded on GitHub today` : 'No visitors recorded yet on GitHub today'}">${conv.todayUniques > 0 ? '&#x1F7E2;' : '&#x26AA;'} ${conv.todayUniques} visitor${conv.todayUniques === 1 ? '' : 's'} today</span>
                <span class="conv-tag conv-tag-star ${conv.starRateNum > 0 ? 'active' : ''}" title="${conv.baseVisitors > 0 ? `Star Conversion: ${conv.starRate}% of recorded visitors starred this repo (${r.Stars} stars &divide; ${conv.baseVisitors} visitors)` : 'No views recorded yet'}">&#x2B50; ${conv.starRate}% Star Conv</span>
                <span class="conv-tag conv-tag-dl ${conv.dlRateNum > 0 ? 'active' : ''}" title="${conv.baseVisitors > 0 ? `Release Downloads: ${r.Downloads} packages (${conv.dlMultiplier}x per visitor &bull; ${r.Downloads} &divide; ${conv.baseVisitors})` : `Release Downloads: ${r.Downloads} packages total`}">&#x1F4E5; ${r.Downloads} DLs (${conv.dlMultiplier}x)</span>
                <span class="conv-tag conv-tag-dev ${conv.uniqueClones > 0 ? 'active' : ''}" title="Devs: ${conv.uniqueClones} unique client IPs or user accounts that cloned this repo in the last 14 days (${conv.totalClones} total git pulls &bull; +${conv.botPulls} repeat/CI pulls)">&#x1F680; ${conv.uniqueClones} Devs <span style="opacity:0.65;font-size:0.62rem;">(+${conv.botPulls} &#x1F916;)</span></span>
                <span class="conv-tag conv-persona" title="Audience Classification">${conv.personaIcon} ${conv.persona}</span>
              </div>

              <div class="repo-footer">
                <div style="display: flex; align-items: center; gap: 0.5rem;">
                  <span style="display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: ${langColor};"></span>
                  <span>${r.Language}</span>
                  ${licenseBadge}
                </div>
                <div>
                  <span>${r.SizeFormatted}</span>
                  <span style="margin: 0 0.3rem;">&bull;</span>
                  <span title="${formatDate(r.PushedAt)}">Updated ${timeAgo(r.PushedAt)}</span>
                </div>
              </div>
            </div>
          </div>
        `;
      }).join('');
    }

    document.querySelectorAll('.filter-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
        e.currentTarget.classList.add('active');
        currentFilter = e.currentTarget.getAttribute('data-filter');
        render();
      });
    });

    document.getElementById('search-input').addEventListener('input', (e) => {
      searchQuery = e.target.value.trim();
      render();
    });

    document.getElementById('sort-select').addEventListener('change', (e) => {
      currentSort = e.target.value;
      render();
    });

    initChartControls();
    renderChart();
    renderFunnelSection();
    render();
  </script>
</body>
</html>
'@

# Replace tokens in template
$htmlContent = $htmlTemplate `
  -replace '__SCRIPT_VERSION__', $ScriptVersion `
  -replace '__USER_AVATAR__', $avatarDataUri `
  -replace '__USER_LOGIN__', $user.login `
  -replace '__USER_BIO__', [System.Web.HttpUtility]::HtmlEncode($bio) `
  -replace '__TOTAL_STARS__', $totalStars `
  -replace '__DELTA_STARS_HTML__', $deltaStarsHtml `
  -replace '__TOTAL_DOWNLOADS__', $totalDownloads `
  -replace '__DELTA_DOWNLOADS_HTML__', $deltaDownloadsHtml `
  -replace '__TOTAL_VIEWS_14D__', $total14DayViews `
  -replace '__TOTAL_FORKS__', $totalForks `
  -replace '__TOTAL_REPOS__', $analyzedRepos.Count `
  -replace '__TRAFFIC_HTML__', $trafficHtml `
  -replace '__RADAR_QUERY_QUOTED__', $radarQueryQuoted `
  -replace '__RADAR_QUERY_PLAIN__', $radarQueryPlain `
  -replace '__RADAR_TERMS_DISPLAY__', $radarTermsDisplay `
  -replace '__GENERATED_AT__', $generatedAt `
  -replace '__REPOS_JSON__', $reposJson `
  -replace '__ROLLING_14_JSON__', $rolling14Json `
  -replace '__CUMULATIVE_YEAR_JSON__', $cumulativeYearJson `
  -replace '__BY_REPO_DAILY_JSON__', $byRepoDailyJson `
  -replace '__RELEASES_JSON__', $allReleasesJson `
  -replace '__HISTORY_JSON__', $historyCompressed

Set-Content -Path $reportFile -Value $htmlContent -Encoding UTF8

Write-Host ""
Write-Host "  [+] GitMyRate Dashboard ready:" -ForegroundColor Green
Write-Host "      $reportFile" -ForegroundColor White
Write-Host ""

if (-not $NoBrowser) {
  Write-Host "  [+] Opening in your default browser..." -ForegroundColor Cyan
  Start-Process -FilePath $reportFile
}

Write-Host "  Done!" -ForegroundColor Green
Write-Host ""
