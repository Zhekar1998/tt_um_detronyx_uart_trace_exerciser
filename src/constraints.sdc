# SPDX-License-Identifier: Apache-2.0

set clock_port clk
if { [info exists ::env(CLOCK_PORT)] } {
    set clock_port [lindex $::env(CLOCK_PORT) 0]
}

set clock_period $::env(CLOCK_PERIOD)
set input_delay_value [expr {$clock_period * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set output_delay_value [expr {$clock_period * $::env(IO_DELAY_CONSTRAINT) / 100.0}]

create_clock -name $clock_port -period $clock_period [get_ports $clock_port]
set clocks [get_clocks $clock_port]

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]

set clk_input [get_port $clock_port]
set clk_idx [lsearch [all_inputs] $clk_input]
set all_inputs_wo_clk [lreplace [all_inputs] $clk_idx $clk_idx ""]

set_input_delay $input_delay_value -clock $clocks $all_inputs_wo_clk
set_output_delay $output_delay_value -clock $clocks [all_outputs]

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    $all_inputs_wo_clk

set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    $clk_input

set_load [expr {$::env(OUTPUT_CAP_LOAD) / 1000.0}] [all_outputs]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks
set_timing_derate -early [expr {1.0 - ($::env(TIME_DERATING_CONSTRAINT) / 100.0)}]
set_timing_derate -late [expr {1.0 + ($::env(TIME_DERATING_CONSTRAINT) / 100.0)}]

set_propagated_clock [all_clocks]
