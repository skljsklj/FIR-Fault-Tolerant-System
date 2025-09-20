set root_dir [pwd]
set project_dir vivado_project

file mkdir $project_dir

create_project fir_fault_tolerant_system $project_dir -part xc7z010clg400-1
set_property board_part digilentinc.com:zybo:part0:2.0 [current_project]

add_files -norecurse hdl/util_pkg.vhd
add_files -norecurse hdl/txt_util.vhd
add_files -norecurse hdl/mac.vhd
add_files -norecurse hdl/mac_triplex_duplex.vhd
add_files -norecurse hdl/tb.vhd

update_compile_order -fileset sources_1

# set_property SOURCE_SET sources_1 [get_filesets sim_1]
# add_files -fileset sim_1 -norecurse tb/test_tb.vhd

add_files -fileset constrs_1 -norecurse constraint/clock_constraint.xdc
# add_files -fileset sim_1 -norecurse ../waveform_tb_behav.wcfg

update_compile_order -fileset sources_1
set_property target_language Verilog [current_project]
# update_compile_order -fileset sim_1

