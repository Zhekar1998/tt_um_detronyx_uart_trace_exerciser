# Testbench

This cocotb testbench drives the UART RX pin, checks the generated pattern
output, arms trace streaming, and reads trace/status packets from UART TX.

## Simulation parameters

- `CLOCK_PERIOD_NS=20`: 50 MHz Tiny Tapeout clock.
- `UART_BAUD=115200`: UART protocol rate used by the design.
- `UART_BIT_CYCLES=434`: cycles per UART bit at 50 MHz. This matches the RTL
  divider value.
- `DUT_BAUD_RELOAD=433`: compile-time DUT UART divider, equal to
  `round(clock_hz / baud) - 1`. The RTL default is 433 for 50 MHz/115200.
- `FST=-fst`: dump FST waveforms for GTKWave by default.

The waveform includes `tb.tb_phase[7:0]` as a visual marker:
`0x10` pattern hold, `0x11` pattern counter, `0x20` trace arm, `0x21` trace
event, `0x30` status, `0x40` snapshot, and `0x50` ping.

## Setting up

1. Install the Python requirements from [requirements.txt](requirements.txt).
2. Run the RTL test from this directory with `make -B`.

## How to run

To run the RTL simulation:

```sh
make -B CLOCK_PERIOD_NS=20 UART_BAUD=115200 UART_BIT_CYCLES=434 DUT_BAUD_RELOAD=433
gtkwave tb_rtl.fst tb.gtkw
```

For a different clock, keep `UART_BIT_CYCLES` equal to `DUT_BAUD_RELOAD + 1`.
For example, 32 MHz at 115200 baud is approximately:

```sh
make -B CLOCK_PERIOD_NS=31.25 UART_BAUD=115200 UART_BIT_CYCLES=278 DUT_BAUD_RELOAD=277
```

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
gtkwave tb_gl.fst tb_gl.gtkw
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb_rtl.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
