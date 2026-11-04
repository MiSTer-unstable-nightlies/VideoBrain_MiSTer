derive_pll_clocks
derive_clock_uncertainty

# The reconfigurable video PLL is independent of MiSTer's other clock domains.
# Keep machine-to-video transfers timed separately.
set_clock_groups -asynchronous \
    -group [get_clocks {emu|pll|video_inst|*|divclk}] \
    -group [get_clocks {pll_hdmi|*|divclk pll_audio|*|divclk spi_sck hdmi_sck *|h2f_user0_clk FPGA_CLK1_50 FPGA_CLK2_50 FPGA_CLK3_50}]

set_false_path -to [get_ports {LED[0]}]
