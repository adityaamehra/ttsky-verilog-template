# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


# ── Helpers ───────────────────────────────────────────────────────────────────

def set_din(dut, value):
    """Write a signed 8-bit sample into ui_in."""
    dut.ui_in.value = int(value) & 0xFF


def set_valid_in(dut, val):
    """valid_in is uio_in[0]. Keep uio_in[7:1] = 0."""
    dut.uio_in.value = 0x01 if val else 0x00


def get_dout(dut):
    """Read signed 8-bit output from uo_out."""
    raw = int(dut.uo_out.value)
    return raw if raw < 128 else raw - 256   # sign-extend


def get_valid_out(dut):
    """valid_out is uio_out[0]."""
    return int(dut.uio_out.value) & 0x01


async def wait_valid_out(dut, timeout_cycles=200):
    """Wait until valid_out pulses high. Returns False if timeout."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if get_valid_out(dut):
            return True
    return False


# ── Reset helper ──────────────────────────────────────────────────────────────

async def do_reset(dut):
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    set_din(dut, 0)
    set_valid_in(dut, 0)
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


# ── Test 1: DC input → output should converge to same DC value ────────────────

@cocotb.test()
async def test_dc_input(dut):
    dut._log.info("Test 1: DC input")

    clock = Clock(dut.clk, 100, unit="ns")   # 10 MHz — matches your original tb
    cocotb.start_soon(clock.start())

    await do_reset(dut)

    # Feed constant DC value with valid_in always high
    DC_VALUE = 10
    set_valid_in(dut, 1)
    set_din(dut, DC_VALUE)

    dut._log.info(f"Feeding DC = {DC_VALUE}, waiting for valid_out pulses...")

    # Flush pipeline: wait for several valid_out pulses (decimation_ratio=8, order=6)
    # CIC takes roughly order * decimation_ratio cycles to fill
    for pulse in range(10):
        got = await wait_valid_out(dut, timeout_cycles=200)
        assert got, f"Timed out waiting for valid_out pulse {pulse}"
        dut._log.info(f"  pulse {pulse}: d_out = {get_dout(dut)}")

    # After pipeline is full, output should be stable (DC in → DC out after scaling)
    last = get_dout(dut)
    dut._log.info(f"Final stable d_out = {last}")


# ── Test 2: Zero input → output must stay zero ────────────────────────────────

@cocotb.test()
async def test_zero_input(dut):
    dut._log.info("Test 2: Zero input → output must be zero")

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    await do_reset(dut)

    set_valid_in(dut, 1)
    set_din(dut, 0)

    for pulse in range(8):
        got = await wait_valid_out(dut, timeout_cycles=200)
        assert got, f"Timed out waiting for valid_out pulse {pulse}"
        out = get_dout(dut)
        dut._log.info(f"  pulse {pulse}: d_out = {out}")
        assert out == 0, f"Expected 0 for zero input, got {out}"

    dut._log.info("Zero input test passed")


# ── Test 3: valid_in gating — no input when valid_in=0 ───────────────────────

@cocotb.test()
async def test_valid_in_gate(dut):
    dut._log.info("Test 3: valid_in gating")

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    await do_reset(dut)

    # Hold valid_in low — CIC should not process anything
    set_valid_in(dut, 0)
    set_din(dut, 127)   # max positive 8-bit signed value

    await ClockCycles(dut.clk, 100)

    # valid_out should never have fired
    assert get_valid_out(dut) == 0, "valid_out fired unexpectedly while valid_in=0"
    dut._log.info("valid_in gating test passed")


# ── Test 4: Alternating sign input ───────────────────────────────────────────

@cocotb.test()
async def test_alternating_input(dut):
    dut._log.info("Test 4: Alternating +/- input")

    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    await do_reset(dut)

    set_valid_in(dut, 1)

    # Feed alternating +10 / -10 at every clock
    async def feed_alternating():
        sign = 1
        while True:
            set_din(dut, sign * 10)
            await RisingEdge(dut.clk)
            sign = -sign

    cocotb.start_soon(feed_alternating())

    outputs = []
    for pulse in range(12):
        got = await wait_valid_out(dut, timeout_cycles=200)
        assert got, f"Timed out at pulse {pulse}"
        outputs.append(get_dout(dut))
        dut._log.info(f"  pulse {pulse}: d_out = {outputs[-1]}")

    dut._log.info(f"Alternating input outputs: {outputs}")
    # After settling, a perfect alternating signal through a CIC
    # (which is a low-pass filter) should approach zero
    assert abs(outputs[-1]) < 5, \
        f"Expected near-zero output for alternating input, got {outputs[-1]}"

    dut._log.info("Alternating input test passed")