# Run from the repository root: quartus_sta -t tools/report_timing.tcl
package require ::quartus::project
package require ::quartus::sta

project_open VideoBrain -revision VideoBrain
create_timing_netlist
read_sdc
update_timing_netlist

set report_dir [file join output_files timing_audit]
file mkdir $report_dir
report_clocks -file [file join $report_dir clocks.rpt]
report_clock_transfers -file [file join $report_dir transfers.rpt]
report_ucp -file [file join $report_dir unconstrained.rpt]

# Keep each destination visible even when another domain dominates the failures.
set clock_index 0
set index_file [open [file join $report_dir index.txt] w]
foreach_in_collection clock [get_clocks *] {
    set clock_name [get_clock_info -name $clock]
    puts $index_file "$clock_index $clock_name"
    foreach analysis {setup hold recovery removal} {
        report_timing -$analysis -to_clock $clock_name -npaths 10 \
            -detail full_path \
            -file [file join $report_dir clock_${clock_index}_${analysis}.rpt]
    }
    incr clock_index
}
close $index_file

delete_timing_netlist
project_close
puts "Timing audit complete: $report_dir"
