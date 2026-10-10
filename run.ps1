<#
.SYNOPSIS
    GitMyRate - Zero-Install GitHub Conversion Rates, Traffic Radar & Lifetime Analytics
    Hosted IEX Suite with Local DPAPI Hardware-Locked Encryption & Desktop Shortcut
.DESCRIPTION
    Pulls visitor traffic, release asset downloads, clone velocity, and audience conversion
    metrics from GitHub. Bypasses GitHub's 14-day deletion limit by archiving historical stats
    locally in %LOCALAPPDATA%\GitMyRate.
.EXAMPLE
    irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$TargetUsername,

    [string]$Token,
    [switch]$Force,
    [switch]$NoBrowser,
    [switch]$CreateShortcut,
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'

# Define persistent storage in LocalAppData
$appDataDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "GitMyRate"
if (-not (Test-Path -Path $appDataDir)) {
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
}

$configFile  = Join-Path -Path $appDataDir -ChildPath "config.json"
$tokenFile   = Join-Path -Path $appDataDir -ChildPath "token.enc"
$historyFile = Join-Path -Path $appDataDir -ChildPath "stats-history.json"
$yearlyFile  = Join-Path -Path $appDataDir -ChildPath "yearly-traffic.json"
$reportFile  = Join-Path -Path $appDataDir -ChildPath "dashboard.html"
$avatarIco   = Join-Path -Path $appDataDir -ChildPath "avatar.ico"
$launcherPs1 = Join-Path -Path $appDataDir -ChildPath "launcher.ps1"

Write-Host ""
Write-Host "   ======================================================" -ForegroundColor Cyan
Write-Host "                GitMyRate - Audience & Vitals            " -ForegroundColor White
Write-Host "   ======================================================" -ForegroundColor Cyan
Write-Host ""

# Handle --Reset switch
if ($Reset) {
    Write-Host "  [*] Resetting GitMyRate local configuration and credentials..." -ForegroundColor Yellow
    if (Test-Path $tokenFile) { Remove-Item $tokenFile -Force }
    if (Test-Path $configFile) { Remove-Item $configFile -Force }
    Write-Host "  [+] Reset complete." -ForegroundColor Green
    return
}

# Load saved configuration if available
$config = @{}
if (Test-Path -Path $configFile) {
    try {
        $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $config = @{}
    }
}

# Determine GitHub Username
$Username = $TargetUsername
if ([string]::IsNullOrWhiteSpace($Username)) {
    if ($config.ContainsKey('Username') -and -not [string]::IsNullOrWhiteSpace($config['Username'])) {
        $Username = $config['Username']
    } else {
        # Check git config
        $detectedUser = ""
        try {
            $detectedUser = (git config --get user.name) 2>$null
        } catch {}

        $promptMsg = if ($detectedUser) { "Enter GitHub Username [default: $detectedUser]" } else { "Enter GitHub Username" }
        Write-Host -NoNewline "  ? ${promptMsg}: " -ForegroundColor Yellow
        $inputUser = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($inputUser)) {
            $Username = if ($detectedUser) { $detectedUser } else { "TalviFox" }
        } else {
            $Username = $inputUser.Trim()
        }
    }
}

# Save resolved username
$config['Username'] = $Username
$config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8

# Resolve Token (DPAPI-encrypted local storage)
$resolvedToken = ""
if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $resolvedToken = $Token
} elseif (Test-Path -Path $tokenFile) {
    try {
        $enc = Get-Content -Path $tokenFile -Raw
        $sec = ConvertTo-SecureString $enc
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $resolvedToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } catch {
        Write-Host "  [!] Could not decrypt saved token. Continuing in public mode." -ForegroundColor DarkYellow
    }
} else {
    # Check if user has an existing legacy github-token.txt in current folder or parent
    $legacyTokenPath = Join-Path (Get-Location) "github-token.txt"
    if (Test-Path $legacyTokenPath) {
        $resolvedToken = (Get-Content $legacyTokenPath -Raw).Trim()
        # Migrate into DPAPI
        try {
            $sec = ConvertTo-SecureString $resolvedToken -AsPlainText -Force
            $enc = ConvertFrom-SecureString $sec
            Set-Content -Path $tokenFile -Value $enc -Encoding UTF8
            Write-Host "  [+] Imported and encrypted existing token into Windows DPAPI storage." -ForegroundColor Green
        } catch {}
    } else {
        # First-time interactive prompt
        Write-Host ""
        Write-Host "  [Key Setup] Optional GitHub Personal Access Token" -ForegroundColor Gray
        Write-Host "  - Private visitor views, clones, and referrers require a fine-grained or classic token." -ForegroundColor DarkGray
        Write-Host "  - Token will be encrypted with Windows DPAPI (locked to your user account) and masked." -ForegroundColor DarkGray
        Write-Host "  - Press Enter to skip and continue in public mode (60 requests/hr)." -ForegroundColor DarkGray
        Write-Host ""
        try {
            $secInput = Read-Host -Prompt "  Paste GitHub Token (hidden, press Enter to skip)" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secInput)
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            
            if (-not [string]::IsNullOrWhiteSpace($plain)) {
                $enc = ConvertFrom-SecureString $secInput
                Set-Content -Path $tokenFile -Value $enc -Encoding UTF8
                $resolvedToken = $plain.Trim()
                Write-Host "  [+] Token encrypted and saved safely to LocalAppData." -ForegroundColor Green
            }
        } catch {}
    }
}

# Setup GitHub headers
$headers = @{
    "User-Agent" = "GitMyRate-Analytics/1.0"
    "Accept"     = "application/vnd.github.v3+json"
}
$isAuthenticated = $false
if (-not [string]::IsNullOrWhiteSpace($resolvedToken)) {
    $headers["Authorization"] = "Bearer $resolvedToken"
    # Validate token
    try {
        $authTest = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get -TimeoutSec 8
        $isAuthenticated = $true
        Write-Host "  [✓] Authenticated as $($authTest.login) (Rate Limit: 5,000 req/hr)" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Token provided failed authentication. Falling back to public mode." -ForegroundColor Yellow
        $headers.Remove("Authorization")
        $isAuthenticated = $false
    }
} else {
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

if ($alreadyScannedToday -and -not $Force) {
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
    } catch {
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
    } else {
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
} catch {
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
    } catch {
        Write-Host "  [!] Error fetching repos page ${page}: $($_.Exception.Message)" -ForegroundColor Yellow
        break
    }
}

# Load or initialize Yearly Traffic Archive
$archive = @{}
if (Test-Path -Path $yearlyFile) {
    try {
        $raw = Get-Content -Path $yearlyFile -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            $archive[$prop.Name] = [PSCustomObject]@{
                views   = [int]$prop.Value.views
                uniques = [int]$prop.Value.uniques
            }
        }
    } catch {}
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
        $releasesUrl = "https://api.github.com/repos/$Username/$repoName/releases?per_page=30"
        $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get
        if ($releases -and $releases.Count -gt 0) {
            $releaseCount = $releases.Count
            $latestReleaseTag = $releases[0].tag_name
            foreach ($rel in $releases) {
                $relDl = 0
                $relAssets = [System.Collections.Generic.List[PSObject]]::new()
                if ($rel.assets) {
                    foreach ($asset in $rel.assets) {
                        $dl = [int]$asset.download_count
                        $relDl += $dl
                        $relAssets.Add([PSCustomObject]@{
                            name      = $asset.name
                            downloads = $dl
                            size      = $asset.size
                        })
                    }
                }
                $repoDownloads += $relDl
                $allReleases.Add([PSCustomObject]@{
                    repo      = $repoName
                    tag       = $rel.tag_name
                    name      = if ($rel.name) { $rel.name } else { $rel.tag_name }
                    date      = $rel.published_at.Substring(0, 10)
                    downloads = $relDl
                    assets    = $relAssets
                })
            }
        }
    } catch {}
    $totalDownloads += $repoDownloads

    # Traffic & Clones (Authenticated only)
    $repo14DayViews = 0
    $repo14DayUniques = 0
    $repo14DayClones = 0
    $repo14DayUniqueClones = 0

    if ($isAuthenticated) {
        # Views
        try {
            $viewsData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$repoName/traffic/views" -Headers $headers -Method Get
            $repo14DayViews = [int]$viewsData.count
            $repo14DayUniques = [int]$viewsData.uniques
            $total14DayViews += $repo14DayViews

            if ($viewsData.views) {
                $repoDaily = @{}
                foreach ($v in $viewsData.views) {
                    $dayStr = $v.timestamp.Substring(0, 10)
                    $cnt = [int]$v.count
                    $unq = [int]$v.uniques
                    $repoDaily[$dayStr] = @{ views = $cnt; uniques = $unq }

                    if (-not $archive.ContainsKey($dayStr)) {
                        $archive[$dayStr] = [PSCustomObject]@{ views = 0; uniques = 0 }
                    }
                    $archive[$dayStr].views += $cnt
                    $archive[$dayStr].uniques += $unq
                }
                $dailyTrafficByRepo[$repoName] = $repoDaily
            }
        } catch {}

        # Clones
        try {
            $clonesData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$repoName/traffic/clones" -Headers $headers -Method Get
            $repo14DayClones = [int]$clonesData.count
            $repo14DayUniqueClones = [int]$clonesData.uniques
            $total14DayClones += $repo14DayClones
            $total14DayUniqueClones += $repo14DayUniqueClones
        } catch {}

        # Referrers
        try {
            $refData = Invoke-RestMethod -Uri "https://api.github.com/repos/$Username/$repoName/traffic/popular/referrers" -Headers $headers -Method Get
            if ($refData) {
                foreach ($rf in $refData) {
                    $trafficReferrers.Add([PSCustomObject]@{
                        Repo      = $repoName
                        Referrer  = $rf.referrer
                        Count     = [int]$rf.count
                        Uniques   = [int]$rf.uniques
                    })
                }
            }
        } catch {}
    }

    # License Detection
    $detectedLicense = "Custom"
    if ($repo.license -and $repo.license.spdx_id -and $repo.license.spdx_id -ne "NOASSERTION") {
        $detectedLicense = $repo.license.spdx_id
    }

    # Format Size
    $sizeKb = [int]$repo.size
    $formattedSize = if ($sizeKb -ge 1024) { "{0:N1} MB" -f ($sizeKb / 1024) } else { "$sizeKb KB" }

    # Normalize Language
    $lang = if ($repo.language) { $repo.language } else { "General" }
    if ($lang -eq "PowerShell") { $lang = "PoSH" }

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
        Clones14Days       = $repo14DayClones
        UniqueClones14Days = $repo14DayUniqueClones
    })
}

# Save Yearly Traffic
$archive | ConvertTo-Json -Depth 5 | Set-Content -Path $yearlyFile -Encoding UTF8

# Build 14-day Rolling timeline
$timelineDays = @()
for ($i = 13; $i -ge 0; $i--) {
    $timelineDays += (Get-Date).AddDays(-$i).ToString("yyyy-MM-dd")
}

$chartRolling14List = [System.Collections.Generic.List[PSObject]]::new()
foreach ($day in $timelineDays) {
    $sumViews = 0
    $sumUniques = 0
    if ($archive.ContainsKey($day)) {
        $sumViews = [int]$archive[$day].views
        $sumUniques = [int]$archive[$day].uniques
    }
    $chartRolling14List.Add([PSCustomObject]@{
        date    = $day
        views   = $sumViews
        uniques = $sumUniques
    })
}

# Build Lifetime Cumulative Timeline
$chartCumulativeList = [System.Collections.Generic.List[PSObject]]::new()
$sortedDays = $archive.Keys | Sort-Object
$cumViews = 0
$cumUniques = 0
foreach ($d in $sortedDays) {
    $cumViews += [int]$archive[$d].views
    $cumUniques += [int]$archive[$d].uniques
    $chartCumulativeList.Add([PSCustomObject]@{
        date       = $d
        cumViews   = $cumViews
        cumUniques = $cumUniques
        dayViews   = [int]$archive[$d].views
        dayUniques = [int]$archive[$d].uniques
    })
}

# Historical Snapshot Tracking
$historyList = [System.Collections.Generic.List[PSObject]]::new()
if (Test-Path -Path $historyFile) {
    try {
        $rawHist = Get-Content -Path $historyFile -Raw | ConvertFrom-Json
        if ($rawHist -is [System.Array]) {
            foreach ($h in $rawHist) { $historyList.Add($h) }
        } elseif ($null -ne $rawHist) {
            $historyList.Add($rawHist)
        }
    } catch {}
}

# Compute deltas from last record
$deltaStars = 0
$deltaDownloads = 0
if ($historyList.Count -gt 0) {
    $lastRecord = $historyList[-1]
    $deltaStars = [Math]::Max(0, $totalStars - [int]$lastRecord.totalStars)
    $deltaDownloads = [Math]::Max(0, $totalDownloads - [int]$lastRecord.totalDownloads)
}

# Append today's record
$historyList.Add([PSCustomObject]@{
    timestamp              = (Get-Date).ToString("o")
    dateDisplay            = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    totalStars             = $totalStars
    totalDownloads         = $totalDownloads
    totalForks             = $totalForks
    totalRepos             = $analyzedRepos.Count
    totalViews14d          = $total14DayViews
    totalClones14d         = $total14DayClones
    totalUniqueClones14d   = $total14DayUniqueClones
    yearCumulativeViews    = $cumViews
    repos                  = ($analyzedRepos | Select-Object Name, Stars, Downloads, Forks, Views14Days, License, Language)
})

Set-Content -Path $historyFile -Value ($historyList | ConvertTo-Json -Depth 5) -Encoding UTF8

# Handle Avatar & Desktop Shortcut
$avatarUrl = $user.avatar_url
$avatarDataUri = $avatarUrl
$hasCustomIcon = $false

try {
    # Download avatar bytes
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "GitMyRate-Setup")
    $avatarBytes = $wc.DownloadData($avatarUrl)
    $wc.Dispose()

    # Base64 encode for embedding inside HTML report
    $b64 = [Convert]::ToBase64String($avatarBytes)
    $avatarDataUri = "data:image/png;base64,$b64"

    # Convert to .ICO for Windows Desktop Shortcut
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    if ([System.Type]::GetType("System.Drawing.Bitmap")) {
        $ms = [System.IO.MemoryStream]::new($avatarBytes)
        $bmp = [System.Drawing.Bitmap]::FromStream($ms)
        $thumb = [System.Drawing.Bitmap]::new($bmp, [System.Drawing.Size]::new(64, 64))
        $hIcon = $thumb.GetHicon()
        $ico = [System.Drawing.Icon]::FromHandle($hIcon)
        $fs = [System.IO.FileStream]::new($avatarIco, [System.IO.FileMode]::Create)
        $ico.Save($fs)
        $fs.Close()
        $fs.Dispose()
        $ico.Dispose()
        $thumb.Dispose()
        $bmp.Dispose()
        $ms.Dispose()
        $hasCustomIcon = $true
    }
} catch {
    # Silent fallback - zero crashes
    $hasCustomIcon = $false
}

# Create / Update Desktop Shortcut & Offline Launcher
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutFile = Join-Path -Path $desktopPath -ChildPath "GitMyRate ($Username).lnk"

# Write offline-resilient launcher trampoline script
$launcherContent = @"
try {
    if ([System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
        return
    }
} catch {}

`$report = "$reportFile"
if (Test-Path `$report) {
    Start-Process -FilePath `$report
}
"@
Set-Content -Path $launcherPs1 -Value $launcherContent -Encoding UTF8

if ($CreateShortcut -or (-not (Test-Path $shortcutFile))) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($shortcutFile)
        $sc.TargetPath = "powershell.exe"
        $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherPs1`""
        $sc.Description = "GitMyRate - GitHub Audience & Conversion Rates Dashboard"
        $sc.WorkingDirectory = $appDataDir
        if ($hasCustomIcon -and (Test-Path $avatarIco)) {
            $sc.IconLocation = "$avatarIco,0"
        } else {
            $sc.IconLocation = "$env:SystemRoot\System32\shell32.dll,22"
        }
        $sc.Save()
        Write-Host "  [+] Desktop Shortcut created: 'GitMyRate ($Username).lnk'" -ForegroundColor Green
    } catch {
        # Silently proceed if shortcut cannot be written
    }
}

Write-Host "  [4/4] Rendering GitMyRate HTML Dashboard..." -ForegroundColor Cyan

# Prepare Referrers / Traffic Block
$trafficHtml = ""
if ($isAuthenticated) {
    $refRows = ""
    if ($trafficReferrers.Count -gt 0) {
        foreach ($tr in $trafficReferrers) {
            $refRows += "<tr><td><strong>$($tr.Repo)</strong></td><td>$($tr.Referrer)</td><td>$($tr.Count)</td><td>$($tr.Uniques)</td></tr>"
        }
    } else {
        $refRows = "<tr><td colspan='4' style='color:var(--text-muted); text-align:center;'>No external referral domains detected in the last 14 days.</td></tr>"
    }

    $cloneRows = ""
    $reposWithClones = $analyzedRepos | Where-Object { -not $_.IsFork } | Sort-Object -Descending Clones14Days
    foreach ($r in $reposWithClones) {
        $cloneRows += "<tr><td><strong>$($r.Name)</strong></td><td style='color:#34d399; font-weight:700;'>$($r.Clones14Days)</td><td style='color:var(--text-muted);'>$($r.Views14Days) views</td></tr>"
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
            <tr><th>Repository</th><th>14d Clones</th><th>14d Views</th></tr>
          </thead>
          <tbody>$cloneRows</tbody>
        </table>
      </div>
    </div>
"@
} else {
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
    .profile-banner {
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
      gap: 1.5rem; background: var(--card-bg); border: 1px solid var(--card-border);
      border-radius: 1.25rem; padding: 1.75rem 2rem; backdrop-filter: blur(16px);
      box-shadow: 0 10px 30px rgba(0,0,0,0.3); margin-bottom: 2rem;
    }
    .profile-left { display: flex; align-items: center; gap: 1.25rem; }
    .avatar { width: 72px; height: 72px; border-radius: 50%; border: 3px solid var(--accent-primary); box-shadow: 0 0 20px rgba(56,189,248,0.3); }
    .profile-info h1 { font-size: 1.75rem; font-weight: 800; }
    .profile-bio { color: var(--text-muted); font-size: 0.9rem; margin-top: 0.25rem; }
    .brand-badge {
      display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.35rem 0.75rem;
      border-radius: 9999px; background: rgba(56, 189, 248, 0.12); color: var(--accent-primary);
      border: 1px solid rgba(56, 189, 248, 0.25); font-size: 0.75rem; font-weight: 700;
    }
    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
    .kpi-card {
      background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 1rem;
      padding: 1.25rem; display: flex; align-items: center; gap: 1rem; backdrop-filter: blur(12px);
    }
    .kpi-icon { font-size: 1.8rem; }
    .kpi-val { font-size: 1.65rem; font-weight: 800; font-family: 'JetBrains Mono', monospace; }
    .kpi-lbl { font-size: 0.8rem; color: var(--text-muted); text-transform: uppercase; font-weight: 600; }
    .kpi-delta { font-size: 0.75rem; padding: 0.15rem 0.45rem; border-radius: 9999px; background: rgba(52, 211, 153, 0.15); color: #34d399; font-weight: 700; margin-left: 0.35rem; }
    
    /* Funnel */
    .funnel-section {
      background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 1.25rem;
      padding: 1.5rem; margin-bottom: 2rem;
    }
    .funnel-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 0.85rem; margin-top: 1rem; }
    .funnel-card {
      background: rgba(15, 23, 42, 0.6); border: 1px solid rgba(255, 255, 255, 0.05);
      border-radius: 0.85rem; padding: 1rem;
    }
    .funnel-val { font-size: 1.5rem; font-weight: 800; margin: 0.35rem 0; font-family: 'JetBrains Mono', monospace; }
    .funnel-formula { font-size: 0.72rem; color: var(--text-muted); }
    .funnel-desc { font-size: 0.78rem; color: #cbd5e1; margin-top: 0.4rem; line-height: 1.35; }
    
    /* Toolbar */
    .toolbar {
      display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
      gap: 1rem; margin-bottom: 1.5rem;
    }
    .filter-btn {
      background: rgba(255,255,255,0.04); border: 1px solid var(--card-border); color: var(--text-muted);
      padding: 0.5rem 1rem; border-radius: 0.5rem; font-weight: 600; cursor: pointer;
    }
    .filter-btn.active { background: rgba(56,189,248,0.15); border-color: var(--accent-primary); color: var(--accent-primary); }
    .search-box, .sort-select {
      background: rgba(15, 23, 42, 0.8); border: 1px solid var(--card-border); color: var(--text-main);
      padding: 0.55rem 0.9rem; border-radius: 0.5rem; font-size: 0.88rem;
    }

    /* Repo Cards */
    .repo-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 1.25rem; }
    .repo-card {
      background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 1rem;
      padding: 1.35rem; display: flex; flex-direction: column; justify-content: space-between;
      transition: all 0.2s ease;
    }
    .repo-card:hover { transform: translateY(-3px); border-color: rgba(56,189,248,0.4); }
    .repo-name { font-size: 1.15rem; font-weight: 700; color: #bae6fd; text-decoration: none; }
    .repo-desc { font-size: 0.84rem; color: var(--text-muted); margin: 0.6rem 0; min-height: 2.5rem; line-height: 1.4; }
    .repo-metrics { display: flex; gap: 0.75rem; flex-wrap: wrap; margin-top: 0.75rem; }
    .m-badge { font-size: 0.75rem; padding: 0.2rem 0.5rem; border-radius: 0.35rem; background: rgba(255,255,255,0.05); font-weight: 600; }
    .health-bar { height: 5px; border-radius: 3px; background: rgba(255,255,255,0.1); overflow: hidden; margin-top: 0.5rem; }
    .health-fill { height: 100%; border-radius: 3px; }
    .topic-tag { font-size: 0.7rem; color: var(--accent-primary); background: rgba(56,189,248,0.08); padding: 0.15rem 0.4rem; border-radius: 0.25rem; display: inline-block; margin: 0.15rem; }

    /* Tables */
    .traffic-box { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 1rem; padding: 1.25rem; }
    .traffic-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.75rem; }
    .traffic-table th, .traffic-table td { padding: 0.6rem; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.06); }
    .traffic-table th { color: var(--text-muted); font-weight: 600; }

    .footer { text-align: center; color: var(--text-muted); font-size: 0.8rem; margin-top: 3.5rem; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="container">
    <header class="profile-banner">
      <div class="profile-left">
        <img class="avatar" src="__USER_AVATAR__" alt="__USER_LOGIN__">
        <div class="profile-info">
          <h1>__USER_LOGIN__</h1>
          <p class="profile-bio">__USER_BIO__</p>
        </div>
      </div>
      <div>
        <span class="brand-badge">&#x26A1; GitMyRate Telemetry</span>
      </div>
    </header>

    <!-- Top KPIs -->
    <section class="kpi-grid">
      <div class="kpi-card">
        <div class="kpi-icon">&#x2B50;</div>
        <div>
          <div class="kpi-val" style="color: var(--star-color);">__TOTAL_STARS____DELTA_STARS_HTML__</div>
          <div class="kpi-lbl">Total Stars</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F4E5;</div>
        <div>
          <div class="kpi-val" style="color: var(--download-color);">__TOTAL_DOWNLOADS____DELTA_DOWNLOADS_HTML__</div>
          <div class="kpi-lbl">Release Downloads</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F441;&#xFE0F;</div>
        <div>
          <div class="kpi-val" style="color: var(--views-color);">__TOTAL_VIEWS_14D__</div>
          <div class="kpi-lbl">14-Day Views</div>
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-icon">&#x1F4E6;</div>
        <div>
          <div class="kpi-val">__TOTAL_REPOS__</div>
          <div class="kpi-lbl">Public Repos</div>
        </div>
      </div>
    </section>

    <!-- Funnel -->
    <section class="funnel-section">
      <h2 style="font-size: 1.15rem; font-weight: 700; margin-bottom: 0.25rem;">&#x1F3AF; Git Conversion Rates &amp; Funnel Health</h2>
      <p style="font-size: 0.8rem; color: var(--text-muted);">How effectively discovery turns into bookmarks, clones, and package downloads</p>
      <div class="funnel-grid" id="funnel-container"></div>
    </section>

    <!-- Referrers & Clones -->
    __TRAFFIC_HTML__

    <!-- Toolbar -->
    <div class="toolbar" style="margin-top: 2rem;">
      <div class="filter-group">
        <button class="filter-btn active" data-filter="all">All Projects (<span id="count-all">0</span>)</button>
        <button class="filter-btn" data-filter="source">Original (<span id="count-src">0</span>)</button>
        <button class="filter-btn" data-filter="fork">Forks (<span id="count-fork">0</span>)</button>
      </div>

      <div style="display: flex; gap: 0.75rem;">
        <input type="text" id="search-input" class="search-box" placeholder="Search repos, topics, license...">
        <select id="sort-select" class="sort-select">
          <option value="downloads">Sort by Downloads</option>
          <option value="health">Sort by Health Score &#x1F49A;</option>
          <option value="views">Sort by 14-Day Views</option>
          <option value="stars">Sort by Stars</option>
          <option value="name">Sort by Name</option>
        </select>
      </div>
    </div>

    <!-- Repos Grid -->
    <main class="repo-grid" id="repo-container"></main>

    <footer class="footer">
      Generated automatically by <strong>GitMyRate</strong> &bull; Refreshed: __GENERATED_AT__<br>
      Saved in <code>%LOCALAPPDATA%\GitMyRate</code> (bypassing GitHub's 14-day deletion limit).
    </footer>
  </div>

  <script>
    const repos = __REPOS_JSON__;
    if (Array.isArray(repos)) {
      repos.forEach(r => {
        r.Topics = Array.isArray(r.Topics) ? r.Topics : (r.Topics ? [r.Topics] : []);
        r.Description = r.Description || '';
        r.Language = r.Language || 'General';
        r.License = r.License || '';
        r.Downloads = r.Downloads || 0;
        r.Stars = r.Stars || 0;
        r.Views14Days = r.Views14Days || 0;
        r.Uniques14Days = r.Uniques14Days || 0;
        r.Clones14Days = r.Clones14Days || 0;
        r.UniqueClones14Days = r.UniqueClones14Days || 0;
        r.Forks = r.Forks || 0;
        r.OpenIssues = r.OpenIssues || 0;
      });
    }

    let currentFilter = 'all';
    let currentSort = 'downloads';
    let searchQuery = '';

    function calculateHealth(r) {
      let score = 30; // base
      if (r.Stars > 0) score += 15;
      if (r.Downloads > 0 || r.Clones14Days > 0) score += 25;
      if (r.Description && r.Description !== 'No description provided.') score += 15;
      if (r.Topics && r.Topics.length > 0) score += 15;
      score = Math.min(100, score);

      let color = score >= 80 ? '#10b981' : (score >= 50 ? '#38bdf8' : '#fbbf24');
      let status = score >= 80 ? 'Prime' : (score >= 50 ? 'Healthy' : 'Moderate');
      return { score, color, status };
    }

    function renderFunnel() {
      const container = document.getElementById('funnel-container');
      if (!container) return;

      const totalStars = repos.reduce((a, b) => a + b.Stars, 0);
      const totalDl = repos.reduce((a, b) => a + b.Downloads, 0);
      const totalViews = Math.max(repos.reduce((a, b) => a + b.Views14Days, 0), 1);
      const totalClones = repos.reduce((a, b) => a + b.Clones14Days, 0);
      const uniqueClones = repos.reduce((a, b) => a + b.UniqueClones14Days, 0);

      const starRate = ((totalStars / totalViews) * 100).toFixed(1);
      const dlMultiplier = (totalDl / totalViews).toFixed(1);
      const botPulls = Math.max(0, totalClones - uniqueClones);

      container.innerHTML = `
        <div class="funnel-card">
          <div style="color: #fbbf24; font-size: 0.8rem; font-weight: 700;">⭐ Star Conversion</div>
          <div class="funnel-val" style="color: #fbbf24;">${starRate}%</div>
          <div class="funnel-formula">${totalStars} stars &divide; ${totalViews} views</div>
          <p class="funnel-desc">Visitors who bookmarked or starred your repositories.</p>
        </div>

        <div class="funnel-card">
          <div style="color: #34d399; font-size: 0.8rem; font-weight: 700;">📦 Package Adoption</div>
          <div class="funnel-val" style="color: #34d399;">${dlMultiplier}x</div>
          <div class="funnel-formula">${totalDl} downloads &divide; ${totalViews} visitors</div>
          <p class="funnel-desc">Average release packages downloaded per discovery visit.</p>
        </div>

        <div class="funnel-card">
          <div style="color: #38bdf8; font-size: 0.8rem; font-weight: 700;">🚀 Developer Cloners</div>
          <div class="funnel-val" style="color: #38bdf8;">${uniqueClones} <span style="font-size:0.8rem;">devs</span></div>
          <div class="funnel-formula">${uniqueClones} unique machines pulled code</div>
          <p class="funnel-desc">Developers who cloned the project locally to inspect or build.</p>
        </div>

        <div class="funnel-card">
          <div style="color: #f87171; font-size: 0.8rem; font-weight: 700;">🤖 Automated / Bot Syncs</div>
          <div class="funnel-val" style="color: #f87171;">${botPulls} <span style="font-size:0.8rem;">pulls</span></div>
          <div class="funnel-formula">Filtered repeat daemon &amp; CI syncs</div>
          <p class="funnel-desc">Automated build servers and repeat cron pulls separated from humans.</p>
        </div>
      `;
    }

    function render() {
      const container = document.getElementById('repo-container');
      document.getElementById('count-all').innerText = repos.length;
      document.getElementById('count-src').innerText = repos.filter(r => !r.IsFork).length;
      document.getElementById('count-fork').innerText = repos.filter(r => r.IsFork).length;

      let filtered = repos.filter(r => {
        if (currentFilter === 'source' && r.IsFork) return false;
        if (currentFilter === 'fork' && !r.IsFork) return false;
        if (searchQuery) {
          const q = searchQuery.toLowerCase();
          const matchName = (r.Name || '').toLowerCase().includes(q);
          const matchDesc = (r.Description || '').toLowerCase().includes(q);
          const matchTopics = (r.Topics || []).some(t => String(t).toLowerCase().includes(q));
          return matchName || matchDesc || matchTopics;
        }
        return true;
      });

      filtered.sort((a, b) => {
        if (currentSort === 'downloads') return b.Downloads - a.Downloads || b.Stars - a.Stars;
        if (currentSort === 'health') return calculateHealth(b).score - calculateHealth(a).score;
        if (currentSort === 'views') return b.Views14Days - a.Views14Days;
        if (currentSort === 'stars') return b.Stars - a.Stars;
        if (currentSort === 'name') return a.Name.localeCompare(b.Name);
        return 0;
      });

      if (filtered.length === 0) {
        container.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 3rem; color: #94a3b8;">No projects found.</div>';
        return;
      }

      container.innerHTML = filtered.map(r => {
        const h = calculateHealth(r);
        const topics = Array.isArray(r.Topics) ? r.Topics : [];
        const topicsHtml = topics.slice(0, 5).map(t => `<span class="topic-tag">#${t}</span>`).join('');

        return `
          <div class="repo-card">
            <div>
              <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 0.5rem;">
                <a class="repo-name" href="${r.HtmlUrl}" target="_blank" rel="noopener noreferrer">${r.Name}</a>
                <span style="font-size: 0.72rem; color: ${h.color}; font-weight: 700;">${h.score}% (${h.status})</span>
              </div>
              <div class="health-bar"><div class="health-fill" style="width: ${h.score}%; background: ${h.color};"></div></div>
              <p class="repo-desc">${r.Description || 'No description.'}</p>
              <div>${topicsHtml}</div>
            </div>

            <div>
              <div class="repo-metrics">
                <span class="m-badge" style="color: #fbbf24;">⭐ ${r.Stars}</span>
                <span class="m-badge" style="color: #34d399;">📦 ${r.Downloads} DLs</span>
                <span class="m-badge" style="color: #38bdf8;">👁️ ${r.Views14Days} (14d)</span>
                <span class="m-badge" style="color: #c084fc;">🍴 ${r.Forks}</span>
              </div>
              <div style="display: flex; justify-content: space-between; margin-top: 0.75rem; font-size: 0.75rem; color: var(--text-muted);">
                <span>${r.Language}</span>
                <span>${r.SizeFormatted}</span>
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

    renderFunnel();
    render();
  </script>
</body>
</html>
'@

# Replace tokens in template
$htmlContent = $htmlTemplate `
    -replace '__USER_AVATAR__', $avatarDataUri `
    -replace '__USER_LOGIN__', $user.login `
    -replace '__USER_BIO__', [System.Web.HttpUtility]::HtmlEncode($bio) `
    -replace '__TOTAL_STARS__', $totalStars `
    -replace '__DELTA_STARS_HTML__', $deltaStarsHtml `
    -replace '__TOTAL_DOWNLOADS__', $totalDownloads `
    -replace '__DELTA_DOWNLOADS_HTML__', $deltaDownloadsHtml `
    -replace '__TOTAL_VIEWS_14D__', $total14DayViews `
    -replace '__TOTAL_REPOS__', $analyzedRepos.Count `
    -replace '__TRAFFIC_HTML__', $trafficHtml `
    -replace '__GENERATED_AT__', $generatedAt `
    -replace '__REPOS_JSON__', $reposJson

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
