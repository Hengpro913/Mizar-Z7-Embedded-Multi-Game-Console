#=============================================================================
# create_project.tcl
#   Build the Mizar Z7 game console Vivado project from scratch.
#
#   Usage:
#     vivado -mode batch -source create_project.tcl
#   or from the Vivado Tcl console:
#     source create_project.tcl
#
#   Target device : xc7z020clg400-2   (Zynq-7020, CLG400 package, -2 speed)
#=============================================================================

set prj_name  "MizarZ7_GameConsole"
set part_name "xc7z020clg400-2"

# directory that contains this script (rtl/, constr/, sim/ live next to it)
set script_dir [file normalize [file dirname [info script]]]
set prj_dir    [file normalize [file join $script_dir "vivado_prj"]]

puts "*** project root : $script_dir"
puts "*** project dir  : $prj_dir"

#-----------------------------------------------------------------------------
# Create project
#-----------------------------------------------------------------------------
create_project -force $prj_name $prj_dir -part $part_name

set_property target_language      Verilog [current_project]
set_property simulator_language   Verilog [current_project]

#-----------------------------------------------------------------------------
# Sources
#-----------------------------------------------------------------------------
add_files -norecurse -fileset sources_1 [glob -nocomplain -directory [file join $script_dir rtl]  *.v]
add_files -norecurse -fileset constrs_1 [file join $script_dir constr mizar_z7.xdc]
add_files -norecurse -fileset sim_1     [glob -nocomplain -directory [file join $script_dir sim]  *.v]

set_property top top_game_console [get_filesets sources_1]
set_property top tb_tmds_encoder  [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "*** project created : [get_property directory [current_project]]"
puts "*** top            : [get_property top [get_filesets sources_1]]"