
V     = verilator
.DEFAULT_GOAL := all
GHDL  = ghdl
RTL   = ../rtl
GEN   = gen
WORK  = ghdl_work
TEST_INCLUDE = out/include
TEST_BUILD_ID = $(TEST_INCLUDE)/build_id.v

-include roms.local.mk
RES1_ROM ?=
RES2_ROM ?=
EXPANDER1_ROM ?=
APL_ROM ?=
MT1_ROM ?=
TIMESHARE_ROM ?=
INFOMAN_ROM ?=
APL_TAPE ?=

define check_input
@test -n "$($(1))" && test -f "$($(1))" || { echo "Set $(1) to an existing input file."; exit 1; }
endef

.PHONY: check-res1-rom check-res2-rom check-expander1-rom check-apl-rom check-mt1-rom check-timeshare-rom check-infoman-rom check-apl-tape check-infoman-apple-cart
check-res1-rom:
	$(call check_input,RES1_ROM)
check-res2-rom:
	$(call check_input,RES2_ROM)
check-expander1-rom:
	$(call check_input,EXPANDER1_ROM)
check-apl-rom:
	$(call check_input,APL_ROM)
check-mt1-rom:
	$(call check_input,MT1_ROM)
check-timeshare-rom:
	$(call check_input,TIMESHARE_ROM)
check-infoman-rom:
	$(call check_input,INFOMAN_ROM)
check-apl-tape:
	$(call check_input,APL_TAPE)
check-infoman-apple-cart:
	$(call check_input,INFOMAN_APPLE_CART)

TOP      = --top-module top
GEN_V    = $(GEN)/videobrain.v
VHD_TOP  = videobrain_core

VHD_SRC = \
	$(RTL)/f8/base_pack.vhd \
	$(RTL)/f8/f8_pack.vhd \
	$(RTL)/uv201/uv201_pack.vhd \
	$(RTL)/uv202/uv202_pack.vhd \
	$(RTL)/f8/f8_cpu.vhd \
	$(RTL)/uv202/f8_busif.vhd \
	$(RTL)/uv202/uv202_clkgen.vhd \
	$(RTL)/uv202/uv202_cpu_gate.vhd \
	$(RTL)/uv202/uv202_timing.vhd \
	$(RTL)/uv202/uv202_arbiter.vhd \
	$(RTL)/uv202/uv202_top.vhd \
	$(RTL)/uv201/uv201_regs.vhd \
	$(RTL)/uv201/uv201_fetcher.vhd \
	$(RTL)/uv201/uv201_fifo.vhd \
	$(RTL)/uv201/uv201_yint.vhd \
	$(RTL)/uv201/uv201_render.vhd \
	$(RTL)/f3853.vhd \
	$(RTL)/buffered_bus.vhd \
	$(RTL)/sys_bus.vhd \
	$(RTL)/videobrain_io.vhd \
	$(RTL)/f3870_timer.vhd \
	$(RTL)/expander1.vhd \
	$(RTL)/videobrain_core.vhd

# replace listed netlist modules with rtl_v/<name>.v
CONVERTED =

CONVERTED_V = $(patsubst %,rtl_v/%.v,$(CONVERTED))
V_SRC = sim.v $(GEN_V) $(RTL)/videobrain_audio.sv $(RTL)/apl_source_loader.sv $(CONVERTED_V)

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S), Darwin)
	LIBS += -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo `sdl2-config --libs`
	LIBS += -L/usr/local/lib -L/opt/local/lib
	CXXFLAGS += `sdl2-config --cflags` -Iimgui
	# include both sdl.h and sdl2/sdl.h paths
	CXXFLAGS += `sdl2-config --cflags | sed 's|include/SDL2|include/|'`
	CXXFLAGS += -I/usr/local/include -I/opt/local/include
endif

ifeq ($(UNAME_S), Linux)
	LIBS += -lGL -ldl `sdl2-config --libs`
	CXXFLAGS += `sdl2-config --cflags` -Iimgui
endif

CXXFLAGS += -I../sim/imgui -I../sim/ -O3 -std=c++17
LDFLAGS   = $(LIBS)

V_OPT = -O3 --x-assign fast --x-initial fast --noassert --public-flat-rw \
	-Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME

EXE = ./obj_dir/Vtop
C_SRC = \
	sim_main.cpp \
	sim/sim_bus.cpp sim/sim_clock.cpp sim/sim_console.cpp sim/sim_video.cpp sim/sim_input.cpp \
	sim/imgui/imgui_impl_sdl.cpp sim/imgui/imgui_impl_opengl2.cpp sim/imgui/imgui_draw.cpp \
	sim/imgui/imgui_widgets.cpp sim/imgui/imgui_tables.cpp sim/imgui/imgui.cpp \
	sim/imgui/ImGuiFileDialog.cpp

HL_DIR = obj_dir_headless
HL_EXE = ./$(HL_DIR)/Vtop
HL_SRC = sim_headless.cpp

all: $(EXE)

headless: $(HL_EXE)

$(GEN_V): $(VHD_SRC) $(CONVERTED_V) Makefile
	@mkdir -p $(GEN) $(WORK)
	$(GHDL) -a --std=08 --workdir=$(WORK) -Wno-hide $(VHD_SRC)
	$(GHDL) synth --std=08 --workdir=$(WORK) --out=verilog $(VHD_TOP) > $@.tmp
	@if [ -n "$(CONVERTED)" ]; then python3 strip_modules.py $@.tmp $(CONVERTED); fi
	@mv $@.tmp $@

netlist: $(GEN_V)

$(HL_EXE): $(V_SRC) $(HL_SRC) Makefile
	$V -cc $(V_OPT) -exe --Mdir ./$(HL_DIR) $(TOP) \
		-CFLAGS "-O2 -std=c++17" -LDFLAGS "-lz" $(V_SRC) $(HL_SRC)
	$(MAKE) -C $(HL_DIR) -f Vtop.mk

$(EXE): $(V_SRC) $(C_SRC) Makefile
	$V -cc $(V_OPT) -LDFLAGS "$(LDFLAGS)" -exe --trace --Mdir ./obj_dir \
		$(TOP) -CFLAGS "$(CXXFLAGS)" $(V_SRC) $(C_SRC)
	$(MAKE) -C obj_dir -f Vtop.mk

lint: $(GEN_V)
	$V --lint-only -Wall -Wno-DECLFILENAME -Wno-fatal $(TOP) $(V_SRC)

test-cpu-clock: $(GEN_V)
	$(GHDL) -a --std=08 --workdir=$(WORK) tests/tb_cpu_clock.vhd
	$(GHDL) -r --std=08 --workdir=$(WORK) tb_cpu_clock --assert-level=error

.PHONY: test-cpu-ports
test-cpu-ports:
	mkdir -p out/cpu_ports
	$(GHDL) -a --std=08 --workdir=out/cpu_ports -Wno-hide $(VHD_SRC) tests/tb_cpu_ports.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_ports tb_cpu_ports --assert-level=error --ieee-asserts=disable

.PHONY: test-cpu-opcode-timing
test-cpu-opcode-timing:
	mkdir -p out/cpu_opcode_timing
	$(GHDL) -a --std=08 --workdir=out/cpu_opcode_timing $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_cpu_opcode_timing.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_opcode_timing tb_cpu_opcode_timing --assert-level=error --ieee-asserts=disable

.PHONY: test-cpu-branches
test-cpu-branches:
	mkdir -p out/cpu_branches
	$(GHDL) -a --std=08 --workdir=out/cpu_branches $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_cpu_branches.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_branches tb_cpu_branches --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/cpu_branches tb_cpu_branches -gcheck_br7=false --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/cpu_branches tb_cpu_branches -gcheck_br7=false -gcheck_bt=true --assert-level=error

.PHONY: test-cpu-reset
test-cpu-reset:
	mkdir -p out/cpu_reset
	$(GHDL) -a --std=08 --workdir=out/cpu_reset $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/uv202_clkgen.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_cpu_reset.vhd tests/tb_cpu_power_cycle.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_reset tb_cpu_reset --assert-level=error --ieee-asserts=disable
	$(GHDL) -r --std=08 --workdir=out/cpu_reset tb_cpu_power_cycle --assert-level=error --ieee-asserts=disable

.PHONY: test-cpu-interrupt
test-cpu-interrupt:
	mkdir -p out/ghdl_cpu_interrupt
	$(GHDL) -a --std=08 --workdir=out/ghdl_cpu_interrupt $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_cpu_interrupt.vhd
	$(GHDL) -r --std=08 --workdir=out/ghdl_cpu_interrupt tb_cpu_interrupt --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/ghdl_cpu_interrupt tb_cpu_interrupt -glate_request=true --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/ghdl_cpu_interrupt tb_cpu_interrupt -glong_cycle=true --assert-level=error

test-cpu-irq-chain:
	mkdir -p out/cpu_irq_chain
	$(GHDL) -a --std=08 --workdir=out/cpu_irq_chain $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_cpu_irq_chain.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_irq_chain tb_cpu_irq_chain --assert-level=error

.PHONY: test-cpu-irq-chain

test-cpu-bus-wait:
	mkdir -p out/cpu_bus_wait
	$(GHDL) -a --std=08 --workdir=out/cpu_bus_wait $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_cpu_gate.vhd $(RTL)/uv202/uv202_timing.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd $(RTL)/uv202/uv202_arbiter.vhd $(RTL)/uv202/uv202_top.vhd tests/tb_cpu_bus_wait.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_bus_wait tb_cpu_bus_wait --assert-level=error --ieee-asserts=disable $(BUS_WAIT_ARGS)

.PHONY: test-cpu-bus-wait

test-cpu-gate:
	mkdir -p out/cpu_gate
	$(GHDL) -a --std=08 --workdir=out/cpu_gate $(RTL)/f8/base_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_cpu_gate.vhd $(RTL)/uv202/uv202_timing.vhd $(RTL)/uv202/uv202_arbiter.vhd $(RTL)/uv202/uv202_top.vhd tests/tb_cpu_gate.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_gate tb_cpu_gate --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/cpu_gate tb_cpu_gate -glegacy_gate=true --assert-level=error

.PHONY: test-cpu-gate

.PHONY: test-smi-clock
test-smi-clock:
	mkdir -p out/smi_clock
	$(GHDL) -a --std=08 --workdir=out/smi_clock -Wno-hide $(VHD_SRC) tests/tb_smi_clock.vhd
	$(GHDL) -r --std=08 --workdir=out/smi_clock tb_smi_clock --assert-level=error --ieee-asserts=disable

.PHONY: test-smi
test-smi:
	mkdir -p out/ghdl_smi
	$(GHDL) -a --std=08 --workdir=out/ghdl_smi $(RTL)/f8/base_pack.vhd $(RTL)/f3853.vhd $(RTL)/uv201/uv201_yint.vhd tests/tb_f3853.vhd tests/tb_f3853_timer.vhd
	$(GHDL) -r --std=08 --workdir=out/ghdl_smi tb_f3853 --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/ghdl_smi tb_f3853_timer --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/ghdl_smi tb_f3853_timer -gdivider=1 --assert-level=error
	$(GHDL) -a --std=08 --workdir=out/ghdl_smi $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_smi_vector.vhd
	$(GHDL) -r --std=08 --workdir=out/ghdl_smi tb_smi_vector --assert-level=error

test-yint: $(GEN_V)
	$(GHDL) -a --std=08 --workdir=$(WORK) tests/tb_yint.vhd
	$(GHDL) -r --std=08 --workdir=$(WORK) tb_yint --assert-level=error

test-render: $(GEN_V)
	$(GHDL) -a --std=08 --workdir=$(WORK) tests/tb_render.vhd
	$(GHDL) -r --std=08 --workdir=$(WORK) tb_render --assert-level=error

.PHONY: test-audio-io
test-audio-io:
	mkdir -p out/ghdl_audio_io
	$(GHDL) -a --std=08 --workdir=out/ghdl_audio_io $(RTL)/f8/base_pack.vhd $(RTL)/videobrain_io.vhd tests/tb_audio_io.vhd
	$(GHDL) -r --std=08 --workdir=out/ghdl_audio_io tb_audio_io --assert-level=error

test-audio: test-audio-io
	PYTHONDONTWRITEBYTECODE=1 python3 tests/audio_filter_design.py
	$V -cc --exe --build --top-module videobrain_audio --Mdir out/obj_audio \
		$(RTL)/videobrain_audio.sv $(abspath tests/tb_audio.cpp)
	./out/obj_audio/Vvideobrain_audio --sweep out/audio_sweep.bin
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_audio_alias.py out/audio_sweep.bin
	$V -cc --exe --build --top-module videobrain_audio_fir --Mdir out/obj_audio_fir \
		$(RTL)/videobrain_audio.sv $(abspath tests/tb_audio_fir.cpp)
	./out/obj_audio_fir/Vvideobrain_audio_fir $(RTL)/videobrain_audio.sv

.PHONY: test-audio-path
test-audio-path:
	python3 -B tests/check_audio_path.py --run

test-expander1:
	@mkdir -p out/expander1
	$(GHDL) -a --std=08 --workdir=out/expander1 $(RTL)/f8/base_pack.vhd \
		$(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd \
		$(RTL)/f3870_timer.vhd $(RTL)/expander1.vhd \
		tests/tb_f3870_timer.vhd tests/tb_expander1.vhd
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_f3870_timer --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1 --assert-level=error

test-cartridges:
	@mkdir -p out/cartridges
	$(GHDL) -a --std=08 --workdir=out/cartridges $(RTL)/f8/base_pack.vhd \
		$(RTL)/uv201/uv201_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/uv201/uv201_regs.vhd $(RTL)/buffered_bus.vhd \
		$(RTL)/sys_bus.vhd tests/tb_cartridges.vhd
	$(GHDL) -r --std=08 --workdir=out/cartridges tb_cartridges --assert-level=error

test-expander1-serial: check-expander1-rom test-expander1
	$(GHDL) -a --std=08 --workdir=out/expander1 tests/tb_expander1_serial.vhd
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_serial \
		"-gfirmware=$(EXPANDER1_ROM)" --assert-level=error --ieee-asserts=disable
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_serial \
		"-gfirmware=$(EXPANDER1_ROM)" -gbaud_rate=110 --assert-level=error --ieee-asserts=disable

.PHONY: test-expander1-serial

test-printer: test-tools test-expander1-serial test-printer-uart test-printer-image test-printer-hps test-printer-rom
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_serial \
		"-gfirmware=$(EXPANDER1_ROM)" -gprinter_only=true --assert-level=error --ieee-asserts=disable
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_serial \
		"-gfirmware=$(EXPANDER1_ROM)" -gprinter_only=true -gbaud_rate=110 --assert-level=error --ieee-asserts=disable

.PHONY: test-printer

test-printer-uart: $(TEST_BUILD_ID)
	@mkdir -p out/expander1
	iverilog -g2012 -i -I$(TEST_INCLUDE) -I.. -s tb_printer_uart -o out/expander1/printer_uart \
		tests/tb_printer_uart.sv ../VideoBrain.sv $(RTL)/videobrain_reset.sv $(RTL)/videobrain_printer_rx.sv $(RTL)/videobrain_printer_capture.sv
	vvp out/expander1/printer_uart

.PHONY: test-printer-uart

test-expander1-record: check-expander1-rom test-expander1
	$(GHDL) -a --std=08 --workdir=out/expander1 tests/tb_expander1_record.vhd
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_record \
		"-gfirmware=$(EXPANDER1_ROM)" --assert-level=error --ieee-asserts=disable
	PYTHONDONTWRITEBYTECODE=1 python3 tests/check_expander1_record.py out/expander1/record.csv
	$(GHDL) -r --std=08 --workdir=out/expander1 tb_expander1_record \
		"-gfirmware=$(EXPANDER1_ROM)" -gbad_crc=true \
		-gcapture_file=out/expander1/record-bad.csv --assert-level=error --ieee-asserts=disable

.PHONY: test-expander1-record

test-tape:
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal --top-module tb_tape \
		--Mdir out/expander1/obj_tape $(RTL)/videobrain_tape.sv \
		tests/tape_sd_model.sv tests/tb_tape.sv
	./out/expander1/obj_tape/Vtb_tape

test-dual-tape:
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal --top-module tb_dual_tape \
		--Mdir out/expander1/obj_dual_tape $(RTL)/videobrain_tape.sv \
		$(RTL)/videobrain_tapes.sv tests/tape_dual_sd_model.sv tests/tb_dual_tape.sv
	./out/expander1/obj_dual_tape/Vtb_dual_tape

.PHONY: test-dual-tape

test-expander1-edit: check-expander1-rom test-expander1 test-dual-tape
	$(GHDL) synth --std=08 --workdir=out/expander1 --out=verilog expander1 > out/expander1/expander1.v
	$(V) --binary --timing -Wno-fatal --top-module tb_expander1_edit \
		--Mdir out/expander1/obj_edit out/expander1/expander1.v \
		$(RTL)/videobrain_tape.sv $(RTL)/videobrain_tapes.sv \
		tests/tape_dual_sd_model.sv tests/tb_expander1_edit.sv
	./out/expander1/obj_edit/Vtb_expander1_edit "+firmware=$(EXPANDER1_ROM)"

.PHONY: test-expander1-edit

test-expander1-playback: check-expander1-rom test-expander1 test-tape
	$(GHDL) synth --std=08 --workdir=out/expander1 --out=verilog expander1 > out/expander1/expander1.v
	$(V) --binary --timing -Wno-fatal --top-module tb_expander1_playback \
		--Mdir out/expander1/obj_playback out/expander1/expander1.v \
		$(RTL)/videobrain_tape.sv tests/tape_sd_model.sv tests/tb_expander1_playback.sv
	./out/expander1/obj_playback/Vtb_expander1_playback "+firmware=$(EXPANDER1_ROM)"

.PHONY: test-tape test-expander1-playback

capture-apl-save: check-res1-rom check-res2-rom check-apl-rom check-expander1-rom headless
	@mkdir -p out/expander1/apl-save
	PYTHONDONTWRITEBYTECODE=1 python3 ../tools/keyboard_input.py tests/apl_save.txt out/expander1/apl-save/save.vbk
	$(HL_EXE) \
		--res1 "$(RES1_ROM)" --res2 "$(RES2_ROM)" --cart "$(APL_ROM)" \
		--expander1 "$(EXPANDER1_ROM)" \
		--source out/expander1/apl-save/save.vbk@210 --frames 7000 \
		--record out/expander1/apl-save/record.csv \
		--shot-last --prefix save --outdir out/expander1/apl-save
	PYTHONDONTWRITEBYTECODE=1 python3 tests/check_expander1_record.py out/expander1/apl-save/record.csv --workspace

.PHONY: capture-apl-save

replay-apl-tape: check-res1-rom check-res2-rom check-apl-rom check-expander1-rom check-apl-tape headless
	@mkdir -p out/expander1/apl-load
	PYTHONDONTWRITEBYTECODE=1 python3 ../tools/keyboard_input.py tests/apl_load.txt out/expander1/apl-load/load.vbk
	$(HL_EXE) \
		--res1 "$(RES1_ROM)" --res2 "$(RES2_ROM)" --cart "$(APL_ROM)" \
		--expander1 "$(EXPANDER1_ROM)" --playback "$(APL_TAPE)" \
		--expander-trace out/expander1/apl-load/host.csv \
		--source out/expander1/apl-load/load.vbk@210 --frames 1600 \
		--shot-last --prefix load --outdir out/expander1/apl-load

.PHONY: replay-apl-tape

test-joystick:
	@mkdir -p out/joystick_test
	$(V) --binary --timing --assert --top-module tb_joystick \
		--Mdir out/joystick_test $(RTL)/videobrain_joystick.sv tests/tb_joystick.sv
	./out/joystick_test/Vtb_joystick

.PHONY: test-joystick

# fixed build date avoids generating quartus files
$(TEST_BUILD_ID):
	@mkdir -p $(@D)
	@printf '%s\n' '`define BUILD_DATE "simulation"' > $@

test-video: $(TEST_BUILD_ID)
	@mkdir -p out/video
	$(GHDL) -a --std=08 --workdir=out/video $(RTL)/f8/base_pack.vhd \
		$(RTL)/uv201/uv201_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_timing.vhd \
		$(RTL)/uv201/uv201_render.vhd tests/video_test_source.vhd
	$(GHDL) synth --std=08 --workdir=out/video --out=verilog video_test_source > out/video/source.v
	iverilog -g2012 -i -I$(TEST_INCLUDE) -I.. -s tb_video -o out/video/test \
		tests/tb_video.sv out/video/source.v ../VideoBrain.sv $(RTL)/videobrain_reset.sv \
		../sys/video_freak.sv $(RTL)/videobrain_linedoubler.sv
	vvp out/video/test

.PHONY: test-video

out/joystick_timing/core.v: $(VHD_SRC)
	@mkdir -p out/joystick_timing
	$(GHDL) -a --std=08 --workdir=out/joystick_timing -Wno-hide $(VHD_SRC)
	$(GHDL) synth --std=08 --workdir=out/joystick_timing --out=verilog $(VHD_TOP) > $@.tmp
	@mv $@.tmp $@

test-joystick-timing: out/joystick_timing/core.v
	iverilog -g2012 -s tb_joystick_timing -o out/joystick_timing/test \
		tests/tb_joystick_timing.sv out/joystick_timing/core.v
	vvp out/joystick_timing/test

.PHONY: test-joystick-timing

clean:
	rm -rf obj_dir $(HL_DIR) $(GEN) $(WORK)

.PHONY: all headless netlist lint test-cpu-clock test-yint test-render test-audio test-expander1 test-cartridges clean

test-apl-input: check-apl-rom test-cartridges
	$(GHDL) -r --std=08 --workdir=out/cartridges tb_cartridges --assert-level=error \
		"-gapl_image=$(APL_ROM)"

MT1_PATCHED_ROM ?=

test-music-input: check-mt1-rom test-cartridges
	$(GHDL) -r --std=08 --workdir=out/cartridges tb_cartridges --assert-level=error "-gmusic_image=$(MT1_ROM)"
	@if [ -n "$(MT1_PATCHED_ROM)" ]; then \
		$(GHDL) -r --std=08 --workdir=out/cartridges tb_cartridges --assert-level=error "-gmusic_image=$(MT1_PATCHED_ROM)"; \
	fi

.PHONY: test-tools
test-tools:
	MT1_ROM="$(MT1_ROM)" python3 -B tests/run_tools.py

out/logic_captures/analyze_logic_csv: tests/analyze_logic_csv.cpp
	mkdir -p out/logic_captures
	$(CXX) -std=c++17 -O3 -Wall -Wextra $< -o $@

.PHONY: test-logic-csv
test-logic-csv: out/logic_captures/analyze_logic_csv
	python3 -B tests/check_logic_csv.py $<

.PHONY: test-sean-diag
test-sean-diag:
	mkdir -p out/sean_diag
	$(GHDL) -a --std=08 --workdir=out/sean_diag $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd tests/tb_sean_diag.vhd
	$(GHDL) -r --std=08 --workdir=out/sean_diag tb_sean_diag --assert-level=error --ieee-asserts=disable

.PHONY: test-uv201-wait
test-uv201-wait:
	mkdir -p out/uv201_wait
	$(GHDL) -a --std=08 --workdir=out/uv201_wait $(RTL)/f8/base_pack.vhd $(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_cpu_gate.vhd $(RTL)/uv202/uv202_timing.vhd $(RTL)/f8/f8_cpu.vhd $(RTL)/uv202/f8_busif.vhd $(RTL)/uv202/uv202_arbiter.vhd $(RTL)/uv202/uv202_top.vhd tests/tb_uv201_wait.vhd
	$(GHDL) -r --std=08 --workdir=out/uv201_wait tb_uv201_wait --assert-level=error --ieee-asserts=disable -ggap_csv=out/uv201_wait/read.csv
	$(GHDL) -r --std=08 --workdir=out/uv201_wait tb_uv201_wait --assert-level=error --ieee-asserts=disable -gwrite_test=true -ggap_csv=out/uv201_wait/write.csv
	$(GHDL) -r --std=08 --workdir=out/uv201_wait tb_uv201_wait --assert-level=error --ieee-asserts=disable -gdma_mode=true -ggap_csv=out/uv201_wait/read-dma.csv
	$(GHDL) -r --std=08 --workdir=out/uv201_wait tb_uv201_wait --assert-level=error --ieee-asserts=disable -gwrite_test=true -gdma_mode=true -ggap_csv=out/uv201_wait/write-dma.csv

test-source-loader:
	@mkdir -p out/source_test
	$(V) --binary --timing -Wno-fatal --top-module tb_apl_source_loader \
		--Mdir out/source_test $(RTL)/apl_source_loader.sv tests/tb_apl_source_loader.sv
	./out/source_test/Vtb_apl_source_loader

test-apl-source: test-apl-input test-cpu-interrupt test-tools test-source-loader

test-rtc-boot: check-res1-rom check-res2-rom $(GEN_V)
	@mkdir -p out/rtc_boot
	$(V) --binary --timing -Wno-fatal --top-module tb_rtc_boot \
		--Mdir out/rtc_boot $(GEN_V) tests/tb_rtc_boot.sv
	./out/rtc_boot/Vtb_rtc_boot +bios1="$(RES1_ROM)" +bios2="$(RES2_ROM)"

.PHONY: test-rtc-boot

.PHONY: test-apl-input test-apl-source test-music-input test-source-loader

replay-clock-source: check-res1-rom check-res2-rom check-apl-rom headless
	@mkdir -p out/clock-source
	$(HL_EXE) \
		--res1 "$(RES1_ROM)" --res2 "$(RES2_ROM)" --cart "$(APL_ROM)" \
		--source "../examples/21-apl_s-games-james-price/21-clock.vbk@210" \
		--source-trace --frames 14000 --max-cycles 6000000000 \
		--shot-every 500 --shot-last --prefix clock --outdir out/clock-source \
		> out/clock-source/run.log 2>&1

.PHONY: replay-clock-source

test-arbiter:
	@mkdir -p out/arbiter
	$(GHDL) -a --std=08 --workdir=out/arbiter $(RTL)/f8/base_pack.vhd \
		$(RTL)/uv202/uv202_pack.vhd $(RTL)/uv202/uv202_arbiter.vhd tests/tb_arbiter.vhd
	$(GHDL) -r --std=08 --workdir=out/arbiter tb_arbiter --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/arbiter tb_arbiter --assert-level=error -gdma_test=true

.PHONY: test-arbiter

test-fetcher-bus:
	@mkdir -p out/fetcher_bus
	$(GHDL) -a --std=08 --workdir=out/fetcher_bus $(RTL)/f8/base_pack.vhd \
		$(RTL)/uv201/uv201_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_arbiter.vhd \
		$(RTL)/uv201/uv201_fetcher.vhd tests/tb_fetcher_bus.vhd
	$(GHDL) -r --std=08 --workdir=out/fetcher_bus tb_fetcher_bus --assert-level=error
	$(GHDL) -r --std=08 --workdir=out/fetcher_bus tb_fetcher_bus --assert-level=error -gcopy_mode=true
	$(GHDL) -r --std=08 --workdir=out/fetcher_bus tb_fetcher_bus --assert-level=error -gbackpressure=true
	$(GHDL) -r --std=08 --workdir=out/fetcher_bus tb_fetcher_bus --assert-level=error -gcopy_mode=true -gbackpressure=true

.PHONY: test-fetcher-bus

test-cpu-audio:
	@mkdir -p out/cpu_audio
	$(GHDL) -a --std=08 --workdir=out/cpu_audio $(RTL)/f8/base_pack.vhd \
		$(RTL)/f8/f8_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/uv202/uv202_clkgen.vhd $(RTL)/f8/f8_cpu.vhd \
		$(RTL)/uv202/f8_busif.vhd $(RTL)/videobrain_io.vhd tests/tb_cpu_audio.vhd
	$(GHDL) -r --std=08 --workdir=out/cpu_audio tb_cpu_audio --assert-level=error -gdelay_count=96
	$(GHDL) -r --std=08 --workdir=out/cpu_audio tb_cpu_audio --assert-level=error -gdelay_count=46
	$(GHDL) -r --std=08 --workdir=out/cpu_audio tb_cpu_audio --assert-level=error -gdelay_count=21
	$(GHDL) -r --std=08 --workdir=out/cpu_audio tb_cpu_audio --assert-level=error -gdelay_count=8

.PHONY: test-cpu-audio

test-download-reset: $(TEST_BUILD_ID)
	@mkdir -p out/download_reset
	iverilog -g2012 -i -I$(TEST_INCLUDE) -I.. -s tb_download_reset -o out/download_reset/test \
		tests/tb_download_reset.sv ../VideoBrain.sv $(RTL)/videobrain_joystick.sv $(RTL)/videobrain_reset.sv
	vvp out/download_reset/test
	iverilog -g2012 -s tb_master_control -o out/download_reset/master \
		tests/tb_master_control.sv $(RTL)/videobrain_reset.sv
	vvp out/download_reset/master

.PHONY: test-download-reset

.PHONY: test-reset-video
test-reset-video: $(TEST_BUILD_ID)
	@mkdir -p out/reset_video
	$(GHDL) -a --std=08 --workdir=out/reset_video $(RTL)/f8/base_pack.vhd \
		$(RTL)/uv201/uv201_pack.vhd $(RTL)/uv202/uv202_pack.vhd \
		$(RTL)/uv202/uv202_clkgen.vhd $(RTL)/uv202/uv202_timing.vhd \
		$(RTL)/uv201/uv201_render.vhd tests/reset_video_source.vhd
	$(GHDL) synth --std=08 --workdir=out/reset_video --out=verilog reset_video_source > out/reset_video/source.v
	iverilog -g2012 -i -I$(TEST_INCLUDE) -I.. -s tb_reset_video -o out/reset_video/test \
		tests/tb_reset_video.sv out/reset_video/source.v ../VideoBrain.sv $(RTL)/videobrain_reset.sv
	vvp out/reset_video/test


test-apl-reload: check-res1-rom check-res2-rom check-apl-rom check-expander1-rom $(GEN_V)
	$(V) --binary --timing -Wno-fatal -Wno-PINMISSING --top-module tb_apl_reload \
		--Mdir out/apl_reload $(GEN_V) $(RTL)/videobrain_tape.sv $(RTL)/videobrain_tapes.sv tests/tb_apl_reload.sv
	./out/apl_reload/Vtb_apl_reload \
		"+bios1=$(RES1_ROM)" \
		"+bios2=$(RES2_ROM)" \
		"+expander=$(EXPANDER1_ROM)" \
		"+cart=$(APL_ROM)" $(APL_RELOAD_ARGS)

.PHONY: test-apl-reload

test-status-messages: $(TEST_BUILD_ID)
	@mkdir -p out/status_messages
	iverilog -g2012 -i -I$(TEST_INCLUDE) -I.. -s tb_status_messages -o out/status_messages/test \
		tests/tb_status_messages.sv ../VideoBrain.sv $(RTL)/videobrain_reset.sv $(RTL)/videobrain_printer_rx.sv $(RTL)/videobrain_printer_capture.sv
	vvp out/status_messages/test

.PHONY: test-status-messages


test-printer-image:
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal --top-module tb_printer_capture \
		--Mdir out/expander1/obj_printer $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv tests/tb_printer_capture.sv
	./out/expander1/obj_printer/Vtb_printer_capture
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_printer_image.py PrinterImageTests.test_rtl_capture

.PHONY: test-printer-image


test-printer-hps:
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING --top-module tb_printer_hps \
		--Mdir out/expander1/obj_printer_hps ../sys/hps_io.sv \
		$(RTL)/videobrain_printer_rx.sv $(RTL)/videobrain_printer_capture.sv \
		tests/printer_hps_model.sv tests/tb_printer_hps.sv
	./out/expander1/obj_printer_hps/Vtb_printer_hps
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_printer_image.py PrinterImageTests.test_hps_capture

.PHONY: test-printer-hps




test-printer-rom: check-expander1-rom test-expander1
	$(GHDL) synth --std=08 --workdir=out/expander1 --out=verilog expander1 > out/expander1/expander1.v
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING \
		--top-module tb_printer_rom --Mdir out/expander1/obj_printer_rom \
		../sys/hps_io.sv out/expander1/expander1.v $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv tests/printer_hps_model.sv tests/tb_printer_rom.sv
	./out/expander1/obj_printer_rom/Vtb_printer_rom "+firmware=$(EXPANDER1_ROM)"
	PYTHONDONTWRITEBYTECODE=1 python3 tests/test_printer_image.py PrinterImageTests.test_original_rom

.PHONY: test-printer-rom


test-printer-cartridge: check-res1-rom check-res2-rom check-expander1-rom check-timeshare-rom $(GEN_V)
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING \
		--top-module tb_printer_cartridge --Mdir out/expander1/obj_printer_cartridge \
		../sys/hps_io.sv $(GEN_V) $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv tests/printer_hps_model.sv tests/tb_printer_cartridge.sv
	./out/expander1/obj_printer_cartridge/Vtb_printer_cartridge \
		"+bios1=$(RES1_ROM)" \
		"+bios2=$(RES2_ROM)" \
		"+firmware=$(EXPANDER1_ROM)" \
		"+cart=$(TIMESHARE_ROM)"
	python3 tests/test_printer_image.py PrinterImageTests.test_timeshare

.PHONY: test-printer-cartridge


test-printer-infoman: check-res1-rom check-res2-rom check-expander1-rom check-infoman-rom $(GEN_V)
	@mkdir -p out/expander1
	python3 tests/make_printer_fixture.py out/expander1/infoman-printer.vbt
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING \
		--top-module tb_printer_infoman --Mdir out/expander1/obj_printer_infoman \
		../sys/hps_io.sv $(GEN_V) $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv $(RTL)/videobrain_tape.sv $(RTL)/videobrain_tapes.sv \
		tests/printer_hps_model.sv tests/tb_printer_infoman.sv
	./out/expander1/obj_printer_infoman/Vtb_printer_infoman \
		"+bios1=$(RES1_ROM)" \
		"+bios2=$(RES2_ROM)" \
		"+firmware=$(EXPANDER1_ROM)" \
		"+cart=$(INFOMAN_ROM)" \
		"+fixture=out/expander1/infoman-printer.vbt"
	python3 tests/test_printer_image.py PrinterImageTests.test_infoman

INFOMAN_APPLE_ARGS ?= +trace_serial +trace_transfer
INFOMAN_APPLE_CART ?= $(INFOMAN_ROM)

test-printer-infoman-apple: check-res1-rom check-res2-rom check-expander1-rom check-infoman-apple-cart $(GEN_V)
	@mkdir -p out/expander1
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING \
		--top-module tb_printer_infoman --Mdir out/expander1/obj_printer_infoman_apple \
		../sys/hps_io.sv $(GEN_V) $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv $(RTL)/videobrain_tape.sv $(RTL)/videobrain_tapes.sv \
		tests/printer_hps_model.sv tests/tb_printer_infoman.sv
	./out/expander1/obj_printer_infoman_apple/Vtb_printer_infoman \
		"+bios1=$(RES1_ROM)" \
		"+bios2=$(RES2_ROM)" \
		"+firmware=$(EXPANDER1_ROM)" \
		"+cart=$(INFOMAN_APPLE_CART)" \
		"+fixture=../examples/saves/Information Manager - APPLE.vbt" +apple $(INFOMAN_APPLE_ARGS)

.PHONY: test-printer-infoman test-printer-infoman-apple


test-printer-tapes: check-expander1-rom test-expander1
	test -f out/expander1/printer-tape-blank.vbp || python3 ../tools/new_printer.py out/expander1/printer-tape-blank.vbp --size 32768
	$(GHDL) synth --std=08 --workdir=out/expander1 --out=verilog expander1 > out/expander1/expander1.v
	$(V) --binary --timing -Wno-fatal -Wno-PROCASSWIRE -Wno-BLKANDNBLK -Wno-PINMISSING \
		--top-module tb_printer_tapes --Mdir out/expander1/obj_printer_tapes \
		../sys/hps_io.sv out/expander1/expander1.v $(RTL)/videobrain_printer_rx.sv \
		$(RTL)/videobrain_printer_capture.sv $(RTL)/videobrain_tape.sv $(RTL)/videobrain_tapes.sv \
		tests/printer_hps_model.sv tests/tb_printer_tapes.sv
	./out/expander1/obj_printer_tapes/Vtb_printer_tapes "+firmware=$(EXPANDER1_ROM)" +capture=0
	./out/expander1/obj_printer_tapes/Vtb_printer_tapes "+firmware=$(EXPANDER1_ROM)" +capture=1
	python3 tests/test_printer_image.py PrinterImageTests.test_tape_contention

.PHONY: test-printer-tapes

.PHONY: check-regression-roms
check-regression-roms: check-expander1-rom check-apl-rom check-mt1-rom

.PHONY: test-power-cycle
test-power-cycle:
	mkdir -p out/power_cycle
	$(GHDL) -a --std=08 --workdir=out/power_cycle -Wno-hide $(VHD_SRC) tests/tb_power_cycle_core.vhd
	$(GHDL) -r --std=08 --workdir=out/power_cycle tb_power_cycle_core --assert-level=error --ieee-asserts=disable
