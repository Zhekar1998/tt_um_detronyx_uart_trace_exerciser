# Detronyx UART Trace Exerciser

TinyTapeout GF 1x1 project for a small hardware bring-up instrument:

- `ui_in[7:0]`: trace probe inputs
- `uo_out[7:0]`: programmable pattern generator outputs
- `uio[0]`: UART RX input, idle high, 115200 baud by default at 50 MHz
- `uio[1]`: UART TX output
- `uio[7:2]`: live status outputs

The design combines two useful lab functions without overlapping the submitted
VGA/CPU/MAC/TPU style projects:

- A UART-configurable 8-bit pattern generator with hold, counter, walking-one,
  LFSR, alternating, mirror, and xor modes.
- A streaming event analyzer that samples `ui_in[7:0]`, detects masked changes,
  and emits compact UART packets containing the new sample, saturated delta time,
  and changed-bit mask.

The implementation is pure digital RTL and the project config targets the
AvalonSemiconductors `gf180mcu_as_sc_mcu7t3v3` native-3.3 V GF180 cell library.
See [docs/info.md](docs/info.md) for the UART command map and packet format.

The UART divider is the top-level `BAUD_RELOAD` parameter. The default value
is `433`, matching 50 MHz / 115200 baud. For a different system clock, set
`BAUD_RELOAD` at synthesis/simulation time to `round(clock_hz / baud) - 1`.
