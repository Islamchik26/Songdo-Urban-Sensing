#!/usr/bin/env python3
"""Independent S3 numerical reference, NOT execution or validation of MATLAB.

Run: python reference_checks.py [--plot]
Core checks use only Python's standard library. --plot additionally uses the
already-installed matplotlib and numpy packages. Results stay in this folder.

The reference keeps the handbook's delayed ZOH recurrence:
    y[n+1] = a*y[n] + (1-a)*x[n]
and its specified backward-difference compensator, not an exact ZOH inverse.
Each low-pass pole is matched to 0.2 Hz, rather than choosing the total cascade
cutoff to be 0.2 Hz. All initial states equal the pre-plunge equilibrium.
"""

import argparse
import cmath
import json
import math
import os
import random
import statistics
import unittest
from collections import deque
from pathlib import Path

FS = 10.0
DT = 1.0 / FS
TAU = 12.0
POLE_HZ = 0.2
CHANGE_TIME = 30.0
PRE, POST = 25.0, 20.0
HERE = Path(__file__).resolve().parent


def sensor_reference(truth, dt=DT, tau=TAU, initial=PRE):
    a = math.exp(-dt / tau)
    output = [initial]
    for previous_truth in truth[:-1]:
        output.append(a * output[-1] + (1 - a) * previous_truth)
    return output


class Compensator:
    """Scalar streaming reference; invalid readings hold without poisoning."""

    def __init__(self, cutoff=POLE_HZ, tau=TAU, fs=FS):
        self.tau, self.fs = tau, fs
        self.pole = math.exp(-2 * math.pi * cutoff / fs)
        self.previous_y = self.previous_time = None
        self.stages = None

    def process(self, rows):
        output = []
        for timestamp, raw in rows:
            if not math.isfinite(raw):
                output.append(math.nan if self.stages is None else self.stages[-1])
                continue
            if self.previous_y is None:
                inverse = raw
                self.stages = [raw] * 3
            else:
                elapsed = timestamp - self.previous_time
                if elapsed <= 0:
                    raise ValueError("Valid timestamps must increase")
                inverse = raw + self.tau / elapsed * (raw - self.previous_y)
            self.previous_y, self.previous_time = raw, timestamp
            value = inverse
            for k in range(3):
                self.stages[k] = self.pole * self.stages[k] + (1 - self.pole) * value
                value = self.stages[k]
            output.append(value)
        return output


def reference_trace():
    times = [i * DT for i in range(1800)]
    truth = [PRE if t < CHANGE_TIME else POST for t in times]
    sensor = sensor_reference(truth)
    filtered = Compensator().process(zip(times, sensor))
    return times, truth, sensor, filtered


def falling_delay(times, values, fraction):
    threshold = PRE + (POST - PRE) * fraction
    for i in range(1, len(times)):
        if times[i] < CHANGE_TIME or values[i] > threshold:
            continue
        elapsed = times[i] - times[i - 1]
        crossing = times[i - 1] + elapsed * (threshold - values[i - 1]) / (values[i] - values[i - 1])
        return crossing - CHANGE_TIME
    return math.nan


def lp_response(frequency):
    r = math.exp(-2 * math.pi * POLE_HZ / FS)
    z_inv = cmath.exp(-2j * math.pi * frequency / FS)
    return ((1 - r) / (1 - r * z_inv)) ** 3


def compensated_response(frequency):
    z_inv = cmath.exp(-2j * math.pi * frequency / FS)
    return (1 + TAU * FS * (1 - z_inv)) * lp_response(frequency)


def white_noise_rms_gain():
    """L2 impulse norm: output/input RMS for IID white sensor noise."""
    r = math.exp(-2 * math.pi * POLE_HZ / FS)
    stages = [0.0] * 3
    power = 0.0
    for i in range(5000):
        value = 1 + TAU * FS if i == 0 else (-TAU * FS if i == 1 else 0.0)
        for k in range(3):
            stages[k] = r * stages[k] + (1 - r) * value
            value = stages[k]
        power += value * value
    return math.sqrt(power)


def pressure_sea_level(station_hpa, height=6.2, temperature_kelvin=288.15):
    lapse, gravity, molar_mass, gas_constant = 0.0065, 9.80665, 0.0289644, 8.3144598
    base = 1 - lapse * height / temperature_kelvin
    if base <= 0:
        raise ValueError("Pressure model base must be positive")
    return station_hpa * base ** (-gravity * molar_mass / (gas_constant * lapse))


def vector_mean(uv):
    u = statistics.fmean(x[0] for x in uv)
    v = statistics.fmean(x[1] for x in uv)
    speed = math.hypot(u, v)
    direction = math.degrees(math.atan2(u, v)) % 360 if speed > 1e-8 else math.nan
    return speed, direction


def gust_reference(speed, samples=30):
    buffer, result = deque(maxlen=samples), []
    for value in speed:
        buffer.append(value)
        result.append(max(buffer))
    return result


def causal_median_reference(values, faults=None):
    """No rate rule imposed here: rejection versus slew limiting is a choice."""
    if faults is None:
        faults = [False] * len(values)
    slots, result = deque(maxlen=5), []
    for value, fault in zip(values, faults):
        slots.append(value if math.isfinite(value) and 0 <= value <= 100 and not fault else math.nan)
        valid = [v for v in slots if math.isfinite(v)]
        result.append(statistics.median(valid) if valid else math.nan)
    return result


def accepted_humidity_reference(times, values, faults=None, max_rate=2.0):
    """Validate median slope since last accepted sample; do not slew-limit.

    This deliberately exposes the accepted-data semantics chosen by MATLAB.
    Repeated held outputs are not new accepted observations. Consequently a
    persistent offset can eventually be accepted as a larger one-sample jump.
    """
    if faults is None:
        faults = [False] * len(values)
    medians = causal_median_reference(values, faults)
    accepted, accepted_time = math.nan, math.nan
    output, flags = [], []
    for timestamp, raw, fault, candidate in zip(times, values, faults, medians):
        if not math.isfinite(raw) or fault:
            flag = "DROPOUT"
        elif not 0 <= raw <= 100:
            flag = "OUT_OF_RANGE"
        elif not math.isfinite(accepted) or abs(candidate - accepted) <= max_rate * (timestamp - accepted_time) + 1e-10:
            accepted, accepted_time = candidate, timestamp
            flag = "GOOD"
        else:
            flag = "SUSPECT_JUMP"
        output.append(accepted)
        flags.append(flag)
    return output, flags


def numerical_report():
    times, truth, sensor, filtered = reference_trace()
    delays = {}
    for name, fraction in (("t50", 0.5), ("t63.2", 1 - math.exp(-1)), ("t90", 0.9)):
        raw = falling_delay(times, sensor, fraction)
        comp = falling_delay(times, filtered, fraction)
        delays[name] = {"raw_seconds": raw, "compensated_seconds": comp, "reduction_percent": 100 * (1 - comp / raw)}
    low, high = 0.0, FS / 2
    for _ in range(70):
        middle = (low + high) / 2
        if abs(lp_response(middle)) > 1 / math.sqrt(2):
            low = middle
        else:
            high = middle
    frequencies = [i * FS / 100000 for i in range(50001)]
    peak = max(frequencies, key=lambda f: abs(compensated_response(f)))
    sensitivity = {}
    for cutoff in (0.1, 0.15, 0.2, 0.3, 0.5):
        trace = Compensator(cutoff=cutoff).process(zip(times, sensor))
        delay = falling_delay(times, trace, 0.5)
        sensitivity[str(cutoff)] = {"t50_seconds": delay, "t50_reduction_percent": 100 * (1 - delay / delays["t50"]["raw_seconds"])}
    return {
        "verification_kind": "Independent Python reference only; MATLAB not executed",
        "model_assumptions": {"sample_rate_hz": FS, "sensor_tau_seconds": TAU, "sensor_gain": 1, "step_celsius": POST - PRE, "step_time_seconds": CHANGE_TIME, "per_pole_matched_cutoff_hz": POLE_HZ, "pole_count": 3, "initialization": "All states at pre-step equilibrium", "delay_metric": "First threshold crossing after known step, linearly interpolated"},
        "delays": delays,
        "cascade_3db_cutoff_hz": (low + high) / 2,
        "inverse_plus_lowpass_peak_gain": abs(compensated_response(peak)),
        "inverse_plus_lowpass_peak_frequency_hz": peak,
        "iid_white_sensor_noise_rms_gain": white_noise_rms_gain(),
        "pressure_example": {"station_hpa": 1010, "height_m": 6.2, "sea_level_hpa": pressure_sea_level(1010)},
        "cutoff_sensitivity": sensitivity,
        "limitations": ["A noiseless synthetic step is not a real-weather or KMA benchmark", "Derivative compensation amplifies some sensor-noise frequencies", "Frozen filter states during missing data are a hold policy, not integration across missing time", "Printed compensator is backward-difference compensation, not exact inversion of the delayed ZOH model"],
    }


class ReferenceChecks(unittest.TestCase):
    def test_sensor_closed_form_and_stability(self):
        times, _, sensor, _ = reference_trace()
        a = math.exp(-DT / TAU)
        self.assertTrue(0 < a < 1)
        for t, value in zip(times, sensor):
            exact = PRE if t < CHANGE_TIME else POST + (PRE - POST) * math.exp(-(t - CHANGE_TIME) / TAU)
            self.assertAlmostEqual(value, exact, places=11)

    def test_t50_reduction_default(self):
        times, _, sensor, filtered = reference_trace()
        before = falling_delay(times, sensor, .5)
        after = falling_delay(times, filtered, .5)
        self.assertGreaterEqual(1 - after / before, .65)
        self.assertAlmostEqual(after, 2.024601846848107, places=9)

    def test_nonzero_equilibrium_initialization(self):
        actual = Compensator().process((i * DT, 23.7) for i in range(200))
        self.assertTrue(all(abs(v - 23.7) < 1e-12 for v in actual))

    def test_block_state_continuity(self):
        times, _, sensor, _ = reference_trace()
        sensor[101:106] = [math.nan] * 5
        rows = list(zip(times, sensor))
        complete = Compensator().process(rows)
        random.seed(42)
        comp, actual, i = Compensator(), [], 0
        while i < len(rows):
            length = random.randrange(1, 40)
            actual.extend(comp.process(rows[i:i + length]))
            i += length
        self.assertEqual(actual, complete)

    def test_missing_start_and_recovery_are_finite(self):
        rows = [(0, math.nan), (.1, math.nan), (.2, 18), (.3, math.nan), (.4, 18)]
        actual = Compensator().process(rows)
        self.assertTrue(math.isnan(actual[0]) and math.isnan(actual[1]))
        self.assertEqual(actual[2:], [18.0, 18.0, 18.0])

    def test_wind_wrap_and_calm(self):
        uv = [(math.sin(math.radians(d)), math.cos(math.radians(d))) for d in (359, 1)]
        speed, direction = vector_mean(uv)
        self.assertAlmostEqual(speed, math.cos(math.radians(1)))
        self.assertLess(min(direction, 360 - direction), 1e-10)
        speed, direction = vector_mean([(1, 0), (-1, 0)])
        self.assertEqual(speed, 0)
        self.assertTrue(math.isnan(direction))

    def test_gust_inclusion_and_expiry(self):
        actual = gust_reference([0] * 10 + [9] + [0] * 40)
        self.assertTrue(all(value == 9 for value in actual[10:40]))
        self.assertEqual(actual[40], 0)

    def test_humidity_endpoints_need_fault_evidence(self):
        self.assertEqual(causal_median_reference([0] * 5), [0] * 5)
        self.assertEqual(causal_median_reference([100] * 5), [100] * 5)
        actual = causal_median_reference([50, 50, 0, 50], [False, False, True, False])
        self.assertEqual(actual, [50] * 4)

    def test_causal_median_no_future_dependency(self):
        prefix = [50, 51, 50, 100, 50, 49, 50]
        self.assertEqual(causal_median_reference(prefix), causal_median_reference(prefix + [0] * 8)[:len(prefix)])
        self.assertEqual(causal_median_reference(prefix)[3], 50.5)

    def test_humidity_accepted_sample_rate_not_output_slew(self):
        times = [i * DT for i in range(200)]
        values = [50.0] * 10 + [70.0] * 190
        output, flags = accepted_humidity_reference(times, values)
        first_jump = next(i for i in range(1, len(output)) if output[i] > output[i - 1])
        self.assertEqual(output[first_jump] - output[first_jump - 1], 20)
        self.assertEqual(flags[first_jump], "GOOD")
        self.assertTrue("SUSPECT_JUMP" in flags[:first_jump])
        self.assertGreater((output[first_jump] - output[first_jump - 1]) / DT, 2)

    def test_humidity_constant_ramp_acceptance_at_limit(self):
        times = [i * DT for i in range(100)]
        values = [30 + 2 * t for t in times]
        output, flags = accepted_humidity_reference(times, values)
        self.assertTrue(all(flag == "GOOD" for flag in flags))
        self.assertTrue(all(abs(b - a) <= 2 * DT + 1e-10 for a, b in zip(output, output[1:])))

    def test_pressure_units_and_height_zero(self):
        self.assertEqual(pressure_sea_level(1010, height=0), 1010)
        self.assertAlmostEqual(pressure_sea_level(1010), 1010.742737963901, places=10)
        self.assertAlmostEqual(pressure_sea_level(101000) / 100, pressure_sea_level(1010), places=10)

    def test_cascade_cutoff_is_not_each_pole_cutoff(self):
        self.assertLess(abs(lp_response(POLE_HZ)), .36)
        self.assertGreater(abs(lp_response(POLE_HZ)), .35)
        self.assertAlmostEqual(abs(lp_response(0)), 1.0, places=12)


def make_plot(report):
    os.environ.setdefault("MPLCONFIGDIR", str(HERE / ".matplotlib-cache"))
    os.environ.setdefault("XDG_CACHE_HOME", str(HERE / ".cache"))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    times, truth, sensor, filtered = (np.asarray(v) for v in reference_trace())
    relative = times - CHANGE_TIME
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11})
    fig, (ax, spectrum) = plt.subplots(2, 1, figsize=(12, 9), gridspec_kw={"height_ratios": [2.1, 1]}, constrained_layout=True)
    fig.patch.set_facecolor("#f6f8fb")
    fig.suptitle("S3 Micro Weather | Independent numerical design check", fontsize=18, fontweight="bold", x=.07, ha="left")
    for axis in (ax, spectrum):
        axis.set_facecolor("white")
        axis.grid(color="#dce3ed", alpha=.8)
        axis.spines[["top", "right"]].set_visible(False)
    ax.plot(relative, truth, color="#7a8799", lw=1.8, ls="--", label="True 5°C plunge")
    ax.plot(relative, sensor, color="#e09926", lw=2.5, label="PT100 probe, τ = 12 s")
    ax.plot(relative, filtered, color="#137d89", lw=2.5, label="Derivative compensation + 3 causal poles")
    ax.axhline(22.5, color="#596579", lw=1, ls=":")
    delay = report["delays"]["t50"]
    for key, color in (("raw_seconds", "#e09926"), ("compensated_seconds", "#137d89")):
        ax.scatter([delay[key]], [22.5], s=65, c=color, zorder=5)
        ax.vlines(delay[key], 19.65, 22.5, color=color, lw=1.4, linestyles=":")
    ax.text(.98, .95, f"t50 delay: {delay['raw_seconds']:.2f} s → {delay['compensated_seconds']:.2f} s\n{delay['reduction_percent']:.1f}% reduction (target ≥65%)", transform=ax.transAxes, ha="right", va="top", fontsize=13, color="#173148", bbox={"boxstyle": "round,pad=.6", "facecolor": "#ebf4f6", "edgecolor": "none"})
    ax.set(xlim=(-2, 40), ylim=(19.65, 25.5), xlabel="Seconds after the plunge", ylabel="Temperature (°C)")
    ax.legend(loc="lower right", framealpha=.95, fontsize=10)
    frequencies = np.logspace(-2.5, np.log10(FS/2), 1000)
    gains = [abs(compensated_response(float(f))) for f in frequencies]
    spectrum.semilogx(frequencies, gains, color="#7151a5", lw=2)
    spectrum.axhline(1, color="#7a8799", ls="--", lw=1)
    spectrum.set(xlabel="Sensor-noise frequency (Hz)", ylabel="Compensated chain gain", xlim=(frequencies[0], FS/2), ylim=(0, 6.5))
    spectrum.text(.98, .94, f"Noise tradeoff: peak gain {report['inverse_plus_lowpass_peak_gain']:.2f}×\nIID white-noise RMS gain {report['iid_white_sensor_noise_rms_gain']:.2f}×", transform=spectrum.transAxes, ha="right", va="top", fontsize=11)
    fig.supxlabel("Python reference only, NOT MATLAB output or a KMA benchmark.\n10 Hz sampling · each matched pole 0.2 Hz · total −3 dB cutoff 0.102 Hz · equilibrium startup\nDelay = first 50% crossing, linearly interpolated; clean synthetic 25→20°C input.", fontsize=10, color="#4a5b6f", ha="left", x=.07)
    path = HERE / "temperature_design_reference.png"
    fig.savefig(path, dpi=160, facecolor=fig.get_facecolor())
    plt.close(fig)
    return path


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--plot", action="store_true")
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ReferenceChecks)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = numerical_report()
    report["python_reference_checks"] = {"run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors)}
    (HERE / "numerical_reference_results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    if args.plot:
        print("Plot:", make_plot(report))
    raise SystemExit(0 if result.wasSuccessful() else 1)
