#=============================================================================
# build_diag.tcl
#   Build the STANDARD 640x480@60 full-screen DIAGNOSTIC bitstream for the
#   Mizar Z7 game console, without touching the existing project.
#
#   Usage:
#     vivado -mode batch -source tools/build_diag.tcl
#
#   Target device : xc7z020clg400-2   (Zynq-7020, CLG400 package, -2 speed)
#
#   NOTE: D:\FPGAproject is write-restricted in this environment, so the
#         Vivado project is created under the local Temp directory.
#=============================================================================

set prj_name  "mz7_diag"
set part_name "xc7z020clg400-2"

# directory that contains this script (tools/), the project root is its parent
set tools_dir  [file normalize [file dirname [info script]]]
set script_dir [file normalize [file join $tools_dir ".."]]

# project must live in Temp (D:\FPGAproject is not writable here)
set prj_dir [file normalize [file join "C:/Users/Liang/AppData/Local/Temp" $prj_name]]

puts "*** project root : $script_dir"
puts "*** project dir  : $prj_dir"

#-----------------------------------------------------------------------------
# Create project
#-----------------------------------------------------------------------------
create_project -force $prj_name $prj_dir -part $part_name

set_property target_language    Verilog [current_project]
set_property simulator_language Verilog [current_project]

#-----------------------------------------------------------------------------
# Sources : ONLY what the diagnostic design needs
#   (no top_game_console.v / scene_test.v / key_ctrl.v)
#-----------------------------------------------------------------------------
set rtl_dir [file join $script_dir rtl]

set src_files {}
lappend src_files [file join $rtl_dir top_diag.v]
lappend src_files [file join $rtl_dir scene_diag.v]
lappend src_files [file join $rtl_dir video_timing.v]
lappend src_files [file join $rtl_dir clk_hdmi.v]
lappend src_files [file join $rtl_dir hdmi_tx.v]
lappend src_files [file join $rtl_dir tmds_encoder.v]
lappend src_files [file join $rtl_dir serializer_10to1.v]
lappend src_files [file join $rtl_dir btn_debounce.v]

add_files -norecurse -fileset sources_1 $src_files
add_files -norecurse -fileset constrs_1 [file join $script_dir constr mizar_z7.xdc]

set_property top top_diag [get_filesets sources_1]

update_compile_order -fileset sources_1

puts "*** top : [get_property top [get_filesets sources_1]]"

#-----------------------------------------------------------------------------
# Build
#-----------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "*** ERROR: implementation did not complete"
    puts "*** STATUS: [get_property STATUS [get_runs impl_1]]"
    exit 1
}

#-----------------------------------------------------------------------------
# Report  (open the routed design so timing paths can be queried)
#-----------------------------------------------------------------------------
open_run impl_1

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_file [file normalize [file join $impl_dir top_diag.bit]]

puts "*** STATUS: [get_property STATUS [get_runs impl_1]]"
puts "*** WNS: [get_property SLACK [get_timing_paths -delay_type max]]"
puts "*** BITFILE: $bit_file"