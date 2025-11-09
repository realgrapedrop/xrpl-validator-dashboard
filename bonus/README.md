# Bonus Utilities

This directory contains additional utility scripts for XRPL validator operators.

## watch_ledger_stream.py

Real-time viewer for XRPL ledger close events via WebSocket stream.

**Features:**
- Auto-detects rippled WebSocket port (tests 6006, 6005, 5005)
- Caches detected port for faster subsequent runs
- Shows detailed ledger information on each close
- Displays transaction counts, fees, reserves, and validation ranges

**Requirements:**
- Python 3.7+
- `websockets` library (auto-prompts to install if missing)
- rippled WebSocket API enabled in `rippled.cfg`

**Usage:**
```bash
cd bonus
python3 watch_ledger_stream.py
```

**WebSocket Configuration:**

Ensure your `rippled.cfg` has the WebSocket API enabled:
```ini
[port_ws_public]
port = 6006
ip = 0.0.0.0
protocol = ws
```

**Output Example:**
```
[2025-11-09 14:23:45] LEDGER CLOSED
├─ Ledger Index:      92,847,123
├─ Ledger Hash:       A1B2C3D4E5F6...
├─ Transactions:      42
├─ Fee Base:          10 drops
└─ Validated Range:   92847100-92847123
```

Press `Ctrl+C` to stop the stream viewer.
