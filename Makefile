SHELL         := /bin/bash
.RECIPEPREFIX := >
.ONESHELL:
.SILENT:
.NOTPARALLEL:

PY       ?= python3
TOP      ?= conv_top
NUMFMT   ?= dec            # set to "hex" if test_vectors/*.txt are hex
VCD_CASE ?=                # e.g. test_vectors/random_1 (default: first case matching "rand")
RTL      := $(sort $(wildcard rtl/*.v))
FMTARG   := $(if $(filter hex,$(NUMFMT)),+HEX,)
MODULES  := conv_top mac_unit line_buffer window_generator output_stage adder_tree multiplier control_fsm

.PHONY: all check versions lint vectors sim power yosys yosys_rtl yosys_max10 yosys_hier yosys_ltp bundle clean

all: check versions lint vectors sim power yosys bundle
> echo; echo "DONE. Send me: reports/ALL_RESULTS.txt"

yosys: yosys_rtl yosys_max10 yosys_hier yosys_ltp

check:
> mkdir -p reports sim scripts
> miss=0
> for t in iverilog vvp verilator yosys $(PY); do
>   command -v $$t >/dev/null 2>&1 || { echo "MISSING tool: $$t"; miss=1; }
> done
> for f in sim/tb_conv.v scripts/vcd_activity.py python/generate_tests.py; do
>   [ -f $$f ] || { echo "MISSING file: $$f"; miss=1; }
> done
> [ -n "$(RTL)" ] || { echo "MISSING rtl/*.v"; miss=1; }
> [ $$miss -eq 0 ] || exit 1
> echo "check: OK ($(words $(RTL)) RTL files)"

versions:
> { echo "date: $$(date -u +%FT%TZ)"; iverilog -V 2>&1 | head -1; verilator --version; yosys -V; $(PY) --version
>   echo "NUMFMT=$(NUMFMT) TOP=$(TOP)"; echo "RTL: $(RTL)"; } > reports/tool_versions.txt 2>&1

lint:
> mkdir -p reports
> verilator --lint-only -Wall -Wno-fatal -Irtl $(RTL) --top-module $(TOP) > reports/lint.txt 2>&1
> echo "verilator exit: $$?" >> reports/lint.txt
> echo "lint: $$(grep -c '%Warning' reports/lint.txt) warnings, $$(grep -c '%Error' reports/lint.txt) errors"

vectors:
> mkdir -p reports
> $(PY) python/golden_model.py > reports/golden_model.log 2>&1 || echo "golden_model.py nonzero exit (see reports/golden_model.log)"
> $(PY) python/generate_tests.py > reports/generate_tests.log 2>&1 || { echo "generate_tests.py FAILED"; exit 1; }
> ls -d test_vectors/*/ | sed 's|/$$||' > reports/cases.txt
> echo "test cases: $$(wc -l < reports/cases.txt)"
> d=$$(head -1 reports/cases.txt)
> { echo "--- format sample from $$d"
>   for f in image kernel expected; do echo "$$f.txt (lines: $$(wc -l < $$d/$$f.txt)):"; head -3 $$d/$$f.txt; done; } > reports/vector_format.txt
> if grep -qE '[a-fA-F]' $$d/image.txt $$d/kernel.txt; then echo "WARNING: vectors look hex -> rerun with: make NUMFMT=hex"; fi

sim/tb.vvp: sim/tb_conv.v $(RTL)
> mkdir -p sim reports
> iverilog -g2012 -Wall -s tb_conv -o $@ sim/tb_conv.v $(RTL) > reports/iverilog_build.log 2>&1 || { cat reports/iverilog_build.log; exit 1; }

sim: sim/tb.vvp
> [ -d test_vectors ] || { echo "run 'make vectors' first"; exit 1; }
> ls -d test_vectors/*/ | sed 's|/$$||' > reports/cases.txt
> ncase=$$(wc -l < reports/cases.txt)
> for mode in nominal bp; do
>   args=""; [ $$mode = bp ] && args="+BP"
>   log=reports/sim_$$mode.log; : > $$log
>   for d in $$(cat reports/cases.txt); do
>     n=$$(basename $$d)
>     vvp -n sim/tb.vvp +IMG=$$d/image.txt +KER=$$d/kernel.txt +EXP=$$d/expected.txt $$args $(FMTARG) \
>       | sed -e "s/^RESULT /RESULT case=$$n mode=$$mode /" -e "s/^MISMATCH /MISMATCH case=$$n mode=$$mode /" >> $$log
>   done
>   awk '/^RESULT/ { n=split($$0,a," "); h=""; l=""; for(i=2;i<=n;i++){ split(a[i],kv,"="); h=h (i>2?",":"") kv[1]; l=l (i>2?",":"") kv[2] } if(!p){print h; p=1} print l }' $$log > reports/sim_$$mode.csv
>   echo "sim[$$mode]: cases=$$ncase results=$$(grep -c '^RESULT' $$log) PASS=$$(grep -c 'verdict=PASS' $$log) FAIL=$$(grep -c 'verdict=FAIL' $$log) TIMEOUT=$$(grep -c 'verdict=TIMEOUT' $$log)"
> done

power: sim/tb.vvp
> ls -d test_vectors/*/ | sed 's|/$$||' > reports/cases.txt
> c="$(VCD_CASE)"
> [ -n "$$c" ] || c=$$(grep -i -m1 rand reports/cases.txt || head -1 reports/cases.txt)
> echo "power proxy: VCD from $$c"
> vvp -n sim/tb.vvp +IMG=$$c/image.txt +KER=$$c/kernel.txt +EXP=$$c/expected.txt $(FMTARG) +VCD \
>   | sed "s/^RESULT /RESULT case=$$c mode=vcd /" > reports/vcd_run.log
> $(PY) scripts/vcd_activity.py sim/conv.vcd > reports/activity.txt
> echo "wrote reports/activity.txt"

yosys_rtl:
> mkdir -p reports
> yosys -q -l reports/yosys_rtl.log -p "read_verilog $(RTL); hierarchy -check -top $(TOP); proc; opt_clean; memory -nomap; opt_clean; tee -o reports/rtl_cells.txt stat -width -top $(TOP); tee -o reports/rtl_mem.txt dump t:\$$mem*" || echo "yosys_rtl FAILED (reports/yosys_rtl.log)"
> echo "yosys_rtl done"

yosys_max10:
> mkdir -p reports
> yosys -q -l reports/yosys_max10.log -p "read_verilog $(RTL); hierarchy -check -top $(TOP); synth_intel -family max10 -top $(TOP); tee -o reports/stat_max10.txt stat -top $(TOP)" || echo "synth_intel FAILED (reports/yosys_max10.log)"
> echo "yosys_max10 done"

yosys_hier:
> mkdir -p reports
> yosys -q -l reports/yosys_hier.log -p "read_verilog $(RTL); hierarchy -check -top $(TOP); synth -top $(TOP) -lut 4; tee -o reports/stat_hier.txt stat -top $(TOP)" || echo "yosys_hier FAILED (reports/yosys_hier.log)"
> echo "yosys_hier done"

yosys_ltp:
> mkdir -p reports
> for m in $(MODULES); do
>   yosys -q -l reports/yosys_ltp_$$m.log -p "read_verilog $(RTL); hierarchy -check -top $$m; synth -flatten -top $$m -lut 4; tee -o reports/ltp_$$m.txt ltp -noff; tee -o reports/stat_flat_lut4_$$m.txt stat" || echo "ltp(lut4) $$m FAILED"
>   yosys -q -l reports/yosys_ltpg_$$m.log -p "read_verilog $(RTL); hierarchy -check -top $$m; synth -flatten -top $$m; tee -o reports/ltpg_$$m.txt ltp -noff" || echo "ltp(gate) $$m FAILED"
>   echo "$$m: LUT4 depth $$(grep -m1 -o 'length=[0-9]*' reports/ltp_$$m.txt)   gate depth $$(grep -m1 -o 'length=[0-9]*' reports/ltpg_$$m.txt)"
> done

bundle:
> out=reports/ALL_RESULTS.txt; : > $$out
> add() { echo; echo "=================== $$1 ==================="; cat "$$1"; }
> for f in reports/tool_versions.txt reports/vector_format.txt reports/sim_nominal.csv reports/sim_bp.csv \
>          reports/rtl_cells.txt reports/rtl_mem.txt reports/stat_max10.txt reports/stat_hier.txt \
>          reports/stat_flat_lut4_conv_top.txt reports/activity.txt reports/vcd_run.log; do
>   [ -f $$f ] && add $$f >> $$out
> done
> for f in reports/ltp_*.txt reports/ltpg_*.txt; do [ -f $$f ] && add $$f >> $$out; done
> { echo; echo "=================== lint (warnings/errors, first 60) ==================="
>   grep -E '%(Warning|Error)' reports/lint.txt | head -60
>   echo; echo "=================== mismatch lines ==================="
>   grep -h MISMATCH reports/sim_nominal.log reports/sim_bp.log 2>/dev/null | head -40; } >> $$out
> echo "bundle: $$out ($$(wc -l < $$out) lines)"

clean:
> rm -rf reports sim/tb.vvp sim/conv.vcd