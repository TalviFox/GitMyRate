# ⚡ GitMyRate

> **GitHub forgets your traffic after 14 days. GitMyRate remembers forever.**  
> Zero-install audience analytics, conversion funnels, release downloads, and health telemetry for open source creators.

---

## 🚀 1-Second Quickstart

Open **PowerShell** on any Windows machine and run:

```powershell
irm https://raw.githubusercontent.com/TalviFox/GitMyRate/main/run.ps1 | iex
```

That's it! No cloning, no Node/Python dependencies, and no installer wizard.

---

## ✨ Why GitMyRate?

GitHub provides basic 14-day traffic insights, but deletes your data at the end of two weeks and hides your actual audience conversion metrics. **GitMyRate** solves this:

* **📅 Bypasses the 14-Day Limit:** Automatically builds an archive in `%LOCALAPPDATA%\GitMyRate\` so your historical views, clones, and download milestones are preserved permanently.
* **🎯 Conversion Funnel Analytics:** 
  * **⭐ Star Conversion Rate:** What percentage of visitors bookmark your repositories.
  * **📦 Package Adoption Multiplier:** Average release packages downloaded per discovery visit.
  * **🚀 Human Dev Cloners:** Real unique developer machines pulling code.
  * **🤖 Automated Bot & CI Filter:** Separates repeat daemon pulls and GitHub Actions loops from human developers.
* **💚 Repository Health Rating (0–100%):** Evaluates documentation hygiene, recency, community traction, and backlog.
* **🔒 DPAPI Hardware-Locked Token Encryption:** 
  * Tokens entered into the prompt are **masked (`****`)** and **never saved in PowerShell's `PSReadLine` history**.
  * Encrypted directly using Windows **DPAPI** (Data Protection API) tied to your Windows User SID. It is mathematically impossible to decrypt on another computer or account.
* **🖥️ Custom Avatar Desktop Shortcut:** Generates a one-click desktop shortcut with your real GitHub avatar as an icon (with graceful silent fallback if offline).
* **✈️ Offline Resilience:** If you click the shortcut while on a flight or without Wi-Fi, it instantly opens your last cached dashboard without throwing network errors.

---

## 🛠️ Command-Line Options

You can pass standard flags directly when calling the script:

```powershell
# Re-scan immediately (bypass today's 24h cache)
irm .../run.ps1 | iex -args "-Force"

# Scan a different user profile
irm .../run.ps1 | iex -args "-TargetUsername torvalds"

# Re-create or repair your desktop shortcut
irm .../run.ps1 | iex -args "-CreateShortcut"

# Reset saved credentials and cache
irm .../run.ps1 | iex -args "-Reset"
```

---

## 🔒 Security & Privacy

* **100% Client-Side:** GitMyRate communicates **only** with the official `api.github.com` REST API.
* **No Telemetry / No Tracking:** Zero external tracking scripts, third-party analytics, or cloud telemetry.
* **Local Storage:** Everything is saved locally on your computer at:
  ```text
  %LOCALAPPDATA%\GitMyRate\
  ├── config.json          # Target username & preferences
  ├── token.enc            # DPAPI-encrypted Personal Access Token
  ├── stats-history.json   # Lifetime milestone archive
  ├── yearly-traffic.json  # 365-day rolling traffic calendar
  └── dashboard.html       # Self-contained interactive report
  ```

---

## 📄 License

Licensed under the [PolyForm Perimeter License 1.0.0](LICENSE) © 2026 [TalviFox](https://github.com/TalviFox).  
Free to use, run, and modify by anyone and any organization; competitive commercial services or products are prohibited.
