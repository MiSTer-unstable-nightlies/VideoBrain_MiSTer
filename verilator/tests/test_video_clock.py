"""Check progressive PLL frequency error against the line-buffer margin."""

from fractions import Fraction
from pathlib import Path
import re


def main():
    pll = (Path(__file__).resolve().parents[2] / "rtl/pll/pll_video.v").read_text()

    def parameter(name):
        match = re.search(r"\." + name + r'\((?:"([^\"]*)"|([0-9]+))\)', pll)
        assert match, f"Missing PLL parameter: {name}"
        return match.group(1) or match.group(2)

    def counter(name):
        if parameter(name + "_bypass_en") == "true":
            return 1
        return int(parameter(name + "_hi_div")) + int(parameter(name + "_lo_div"))

    reference = Fraction(parameter("reference_clock_frequency").split()[0]) * 1_000_000
    control = (Path(__file__).resolve().parents[2] / "rtl/videobrain_video_clock.sv").read_text()
    native_k = int(re.search(r"NATIVE_K = 32'd([0-9]+)", control).group(1))
    progressive_k = int(re.search(r"PROGRESSIVE_K = 32'd([0-9]+)", control).group(1))
    assert int(parameter("pll_fractional_division")) == native_k, "PLL must start at the native video rate"
    multiplier = counter("m_cnt") + Fraction(progressive_k, 2 ** int(parameter("pll_fractional_cout")))
    output_divider = int(parameter("c_cnt_hi_div0")) + int(parameter("c_cnt_lo_div0"))
    output = reference * multiplier / counter("n_cnt") / output_divider
    native = Fraction(50_000_000 * 63, 5 * 44)
    native_output = reference * (counter("m_cnt") + Fraction(native_k, 2 ** int(parameter("pll_fractional_cout")))) / counter("n_cnt") / output_divider
    assert abs(native_output - 2*native) < Fraction(1, 1000), "Incorrect native video rate"
    target = native * Fraction(1052, 525)
    # 240p consumes one source pixel every eight video clocks.
    drift = abs(output - target) * 86400 / 8
    assert drift < 2, f"PLL error consumes {float(drift):.3f} pixels of buffer per day"
    print(f"Video PLL: {float(output):.9f} Hz; buffer drift {float(drift):.3f} pixels/day")


if __name__ == "__main__":
    main()
