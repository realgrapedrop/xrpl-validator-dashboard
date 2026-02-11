# XRPL Validator Dashboard - Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [3.0.8] - 2026-02-11

### Improved
- **Health panel label**: Shortened "Monitor Health:" to "Health:" to reduce wrapping on mobile devices. Adjusted CSS for better horizontal alignment with stat panels in the top row. Applied across all three themes.

---

## [3.0.7] - 2026-02-01

### Fixed
- **Monitor Health panels showing "Offline"**: Added `--search.maxStalenessInterval=60s` to VictoriaMetrics configuration. This ensures instant queries find sparse metrics (emitted every 30 seconds) that were previously missed due to the default lookback window. Affected panels: Monitor Health, WebSocket, HTTP RPC, Collector, Database.

  **To apply this fix:** Run `git pull`, then `./manage.sh` and select option 10 (Apply Updates).

---

## [3.0.6] - 2025-01-28

### Changed
- Light Mode is now the default home dashboard for better iPad/mobile experience
- Shortened panel names in Light Mode for better mobile display
- Poll results formatting improved with bullet list and theme names

### Fixed
- PhotonOS validation pending (removed from release notes until confirmed)

---

## [3.0.5] - 2025-01-24

### Added
- Light Mode dashboard theme with shorter panel names for mobile/tablet viewing

### Changed
- Default home dashboard set to Light Mode

---

## [3.0.4] - 2025-12-06

### Added
- Webhook alert support with Pipedream tutorial in ALERTS.md
- Docker volume path auto-detection for rippled data

### Fixed
- Data Collection panel `noValue` now shows "Data Collection: Waiting" instead of just "Waiting"
- Improved "How Grafana Alerts Work" documentation in ALERTS.md

---

## [3.0.3] - 2025-12-04

### Added
- Email alert notifications tested and verified (Gmail SMTP)
- Webhook alert notifications tested with Pipedream

### Fixed
- Install/uninstall scripts verified working with clean reinstall

---

## [3.0.2] - 2025-12-01

### Fixed
- HTTP polling retry optimization for faster recovery after rippled restarts
- Dashboard state transition delay reduced from 52s to 10-15s

---

## [3.0.1] - 2025-11-30

### Added
- Port conflict detection in installer
- Git tag-based backup system for stable recovery points

### Fixed
- Install script robustness improvements

---

## [3.0.0] - 2025-11-29

### Added
- Complete rewrite of XRPL Validator Dashboard
- VictoriaMetrics time-series database (replaces InfluxDB)
- Real-time WebSocket monitoring with automatic reconnection
- Validation agreement tracking with 1h and 24h windows
- State persistence across restarts
- Docker Compose deployment
- Comprehensive alert rules (14 alert types)
- Email and webhook notification support

### Changed
- Architecture redesigned for reliability and performance
- Dashboard panels optimized for real-time updates
- Memory footprint reduced significantly

---

## Release Notes Archive

For detailed release announcements and feature descriptions, see:
- [GitHub Releases](https://github.com/realgrapedrop/xrpl-validator-dashboard/releases)
