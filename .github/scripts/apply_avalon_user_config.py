#!/usr/bin/env python3
"""Force generated Tiny Tapeout configs back to the Avalon 7T3V3 SCL."""

from __future__ import annotations

import json
from pathlib import Path


SCL = "gf180mcu_as_sc_mcu7t3v3"
LIB_BASE = f"pdk_dir::libs.ref/{SCL}/lib/{SCL}"

AVALON_CONFIG = {
    "STD_CELL_LIBRARY": SCL,
    "VDD_PIN_VOLTAGE": 3.3,
    "LIB_SYNTH": f"{LIB_BASE}__tt_025C_3v30.lib",
    "LIB_FASTEST": f"{LIB_BASE}__ff_n40C_3v60.lib",
    "LIB_SLOWEST": f"{LIB_BASE}__ss_125C_3v00.lib",
    "DEFAULT_CORNER": "nom_tt_025C_3v30",
    "STA_CORNERS": [
        "nom_tt_025C_3v30",
        "nom_ss_125C_3v00",
        "nom_ff_n40C_3v60",
        "min_tt_025C_3v30",
        "min_ss_125C_3v00",
        "min_ff_n40C_3v60",
        "max_tt_025C_3v30",
        "max_ss_125C_3v00",
        "max_ff_n40C_3v60",
    ],
    "LIB": {
        "*_tt_025C_3v30": [f"{LIB_BASE}__tt_025C_3v30.lib"],
        "*_ss_125C_3v00": [f"{LIB_BASE}__ss_125C_3v00.lib"],
        "*_ff_n40C_3v60": [f"{LIB_BASE}__ff_n40C_3v60.lib"],
    },
    "PNR_SDC_FILE": "dir::constraints.sdc",
    "SIGNOFF_SDC_FILE": "dir::constraints.sdc",
    "MAX_FANOUT_CONSTRAINT": 16,
    "MAX_CAPACITANCE_CONSTRAINT": 0.65,
    "DESIGN_REPAIR_MAX_SLEW_PCT": 30,
    "GRT_DESIGN_REPAIR_MAX_SLEW_PCT": 25,
    "CTS_MAX_CAP": 0.65,
    "CTS_SINK_CLUSTERING_SIZE": 24,
    "CTS_SINK_CLUSTERING_MAX_DIAMETER": 200,
    "CTS_SINK_BUFFER_MAX_CAP_DERATE_PCT": 100,
}


def patch_config(path: Path) -> bool:
    if not path.exists():
        return False

    data = json.loads(path.read_text())
    data.update(AVALON_CONFIG)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return True


def main() -> None:
    patched = []
    for path in (Path("src/user_config.json"), Path("src/config_merged.json")):
        if patch_config(path):
            patched.append(str(path))

    if not patched:
        raise SystemExit("No Tiny Tapeout generated config files found to patch")

    print(f"Applied Avalon {SCL} configuration to: {', '.join(patched)}")


if __name__ == "__main__":
    main()
