# SPDX-License-Identifier: Apache-2.0

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


CLOCK_PERIOD_NS = float(os.getenv("CLOCK_PERIOD_NS", "20"))
UART_BAUD = int(os.getenv("UART_BAUD", "115200"))
BIT_CYCLES = int(
    os.getenv(
        "UART_BIT_CYCLES",
        str(round(1_000_000_000 / (CLOCK_PERIOD_NS * UART_BAUD))),
    )
)

CMD_TRACE_MASK = 0x10
CMD_TRACE_CTRL = 0x12
CMD_PATTERN_MODE = 0x20
CMD_PATTERN_DIV = 0x21
CMD_PATTERN_A = 0x22
CMD_STATUS = 0x30
CMD_PING = 0x31

PKT_TRACE = 0xE1
PKT_STATUS = 0xA5
PKT_PING = 0xD7

PHASE_RESET = 0x01
PHASE_PATTERN_HOLD = 0x10
PHASE_PATTERN_COUNTER = 0x11
PHASE_TRACE_ARM = 0x20
PHASE_TRACE_EVENT = 0x21
PHASE_STATUS = 0x30
PHASE_MASKED_CHANGE = 0x31
PHASE_SNAPSHOT = 0x40
PHASE_PING = 0x50


def set_phase(dut, phase):
    dut.tb_phase.value = phase


def set_uart_rx(dut, bit):
    dut.uio_in.value = bit & 1


async def uart_write_byte(dut, value):
    set_uart_rx(dut, 0)
    await ClockCycles(dut.clk, BIT_CYCLES)
    for bit_index in range(8):
        set_uart_rx(dut, (value >> bit_index) & 1)
        await ClockCycles(dut.clk, BIT_CYCLES)
    set_uart_rx(dut, 1)
    await ClockCycles(dut.clk, BIT_CYCLES)


async def uart_write_cmd(dut, command, argument=None):
    await uart_write_byte(dut, command)
    if argument is not None:
        await uart_write_byte(dut, argument)


async def uart_read_byte(dut, timeout_cycles=20000):
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if ((dut.uio_out.value.to_unsigned() >> 1) & 1) == 0:
            break
    else:
        raise AssertionError("UART TX start bit timeout")

    await ClockCycles(dut.clk, BIT_CYCLES + BIT_CYCLES // 2)
    value = 0
    for bit_index in range(8):
        tx_bit = (dut.uio_out.value.to_unsigned() >> 1) & 1
        value |= tx_bit << bit_index
        await ClockCycles(dut.clk, BIT_CYCLES)

    assert ((dut.uio_out.value.to_unsigned() >> 1) & 1) == 1
    await ClockCycles(dut.clk, BIT_CYCLES // 2)
    return value


def uart_tx_pin(dut):
    return (dut.uio_out.value.to_unsigned() >> 1) & 1


@cocotb.test()
async def test_uart_trace_exerciser(dut):
    cocotb.start_soon(Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns").start())

    set_phase(dut, PHASE_RESET)
    dut.ena.value = 1
    dut.ui_in.value = 0
    set_uart_rx(dut, 1)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 8)

    assert dut.uio_oe.value.to_unsigned() == 0xFE
    assert ((dut.uio_out.value.to_unsigned() >> 1) & 1) == 1

    set_phase(dut, PHASE_PATTERN_HOLD)
    await uart_write_cmd(dut, CMD_PATTERN_A, 0x5A)
    await uart_write_cmd(dut, CMD_PATTERN_MODE, 0)
    await ClockCycles(dut.clk, 40)
    assert dut.uo_out.value.to_unsigned() == 0x5A

    set_phase(dut, PHASE_PATTERN_COUNTER)
    await uart_write_cmd(dut, CMD_PATTERN_DIV, 0)
    await uart_write_cmd(dut, CMD_PATTERN_MODE, 1)
    before_count = dut.uo_out.value.to_unsigned()
    await ClockCycles(dut.clk, 6)
    assert dut.uo_out.value.to_unsigned() != before_count

    set_phase(dut, PHASE_TRACE_ARM)
    await uart_write_cmd(dut, CMD_TRACE_MASK, 0x0F)
    await uart_write_cmd(dut, CMD_TRACE_CTRL, 0x03)
    await ClockCycles(dut.clk, 8)

    set_phase(dut, PHASE_TRACE_EVENT)
    dut.ui_in.value = 0x03
    trace_packet = [await uart_read_byte(dut) for _ in range(4)]
    assert trace_packet[0] == PKT_TRACE
    assert trace_packet[1] == 0x03
    assert trace_packet[3] == 0x03

    set_phase(dut, PHASE_STATUS)
    await uart_write_cmd(dut, CMD_STATUS)
    status_packet = [await uart_read_byte(dut) for _ in range(4)]
    assert status_packet[0] == PKT_STATUS
    assert status_packet[1] & 0x18 == 0x18
    assert status_packet[2] >= 1
    assert status_packet[3] == 0

    set_phase(dut, PHASE_MASKED_CHANGE)
    dut.ui_in.value = 0x83
    await ClockCycles(dut.clk, 32)
    assert uart_tx_pin(dut) == 1
    try:
        assert dut.user_project.u_core.event_count_q.value.to_unsigned() == status_packet[2]
    except AttributeError:
        pass

    set_phase(dut, PHASE_SNAPSHOT)
    await uart_write_cmd(dut, CMD_TRACE_CTRL, 0x0B)
    snapshot_packet = [await uart_read_byte(dut) for _ in range(4)]
    assert snapshot_packet[0] == PKT_TRACE
    assert snapshot_packet[1] == 0x83
    assert snapshot_packet[3] == 0x00

    set_phase(dut, PHASE_PING)
    await uart_write_cmd(dut, CMD_PING)
    ping_packet = [await uart_read_byte(dut) for _ in range(4)]
    assert ping_packet[0] == PKT_PING
    assert ping_packet[1] == 0x54
    assert ping_packet[2] == 0x01
