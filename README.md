# ⚡ GitMyRate

> **GitHub permanently forgets your traffic after 14 days. GitMyRate remembers forever.**  
> Zero-install audience analytics, conversion funnels, release downloads, and health telemetry for open-source creators on Windows.

---

## 🚀 1-Second Quickstart

Open **PowerShell** on any Windows machine and run:

```powershell
irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
```

That's it! No cloning, no Node.js/Python dependencies, and no installer wizard.

---

## ✨ Features & Capabilities

### 📅 Bypasses GitHub's 14-Day Traffic Erasure
GitHub permanently discards your visitor views and git clones after two weeks. GitMyRate archives rolling deltas in `%LOCALAPPDATA%\GitMyRate\` on every scan, permanently preserving your lifetime traffic history and download milestones.

### 🟢 Live "Today's Pulse" Detection
Every repository card features a live pulse badge (`[ 🟢 X visitors today ]`) showing real-time visitor counts and page impressions recorded on GitHub today.

### 🟩 365-Day Traffic Activity Heatmap
A GitHub contribution-style 53-week activity grid tracking your traffic and audience spikes across the entire year. Filter between page views, unique visitors, or package downloads.

### 📊 Overhauled 14-Day Activity Velocity Chart
* **Floating Data Labels**: See exact visitor counts directly above each active day at a glance.
* **Grounded Y-Axis**: Clear reference scale and dashed horizontal gridlines for immediate scale recognition.
* **Clean Zero Baseline**: Quiet days render as subtle baseline dots instead of misleading blocks.
* **Today Live Pillar**: Highlights the active in-progress day with a live status tag.

### 🎯 True Audience Conversion Funnels
* **⭐ Star Conversion Rate**: Percentage of discovering visitors who star your repository.
* **📦 Package Adoption Multiplier**: Average release packages downloaded per discovery visit.
* **🚀 Human Dev Cloners**: Unique client developer machines pulling code.
* **🤖 Automated Bot & CI Filter**: Distinguishes automated CI runs, scrapers, and package daemons from real human developers.

### 💚 Algorithmic Health Score (0–100%)
Evaluates commit recency, documentation hygiene, issue-to-star ratio, and community traction for every repository.

### 🔒 Hardware-Locked DPAPI Security
* Optional Personal Access Token (PAT) inputs are **masked (`****`)** and **never leak into PowerShell's `PSReadLine` history**.
* Tokens are encrypted directly via Windows **DPAPI** (Data Protection API) tied to your Windows User SID. It is mathematically impossible to decrypt on another computer or account.

### 🖥️ Native Desktop Shortcut & Offline Resilience
* Generates a one-click desktop shortcut with your actual GitHub avatar as an icon.
* Click the shortcut without Wi-Fi or while on a flight, and it instantly opens your last cached dashboard without network errors.

---

## 🛠️ Command-Line Options

You can pass standard parameters directly when launching:

```powershell
# Re-scan immediately (bypass today's 24h cache)
irm .../run.ps1 | iex -args "-Force"

# Scan another GitHub user or organization
irm .../run.ps1 | iex -args "-TargetUsername torvalds"

# Re-create or refresh your desktop shortcut icon
irm .../run.ps1 | iex -args "-CreateShortcut"

# Generate dashboard without auto-opening your default browser
irm .../run.ps1 | iex -args "-NoBrowser"

# Reset saved credentials and wipe local cache
irm .../run.ps1 | iex -args "-Reset"
```

---

## 🔒 Security & Privacy

* **100% Client-Side:** GitMyRate communicates **only** with the official `api.github.com` REST API.
* **Zero Telemetry / No Cloud Relays:** No external tracking scripts, CDNs, third-party analytics, or remote database logging.
* **Local Storage Structure:**
  ```text
  %LOCALAPPDATA%\GitMyRate\
  ├── config.json          # Target username & scan preferences
  ├── token.enc            # DPAPI hardware-locked encrypted PAT
  ├── stats-history.json   # Lifetime milestone archive
  ├── yearly-traffic.json  # 365-day rolling traffic calendar
  ├── dashboard.html       # Self-contained offline report
  └── avatar-*.ico         # 32-bit HD multi-DPI desktop icon
  ```

---

## 📄 License

Licensed under the [PolyForm Perimeter License 1.0.0](LICENSE) © 2026 [TalviFox](https://github.com/TalviFox).  
Free to use, run, and modify by anyone and any organization; competitive commercial services or products are prohibited.

