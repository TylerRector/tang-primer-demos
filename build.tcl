set project_name blink
set top_module top
set part_name GW2A-LV18PG256C8/I7
set device_version C

# Save original repo directory before Gowin changes cwd
set repo_dir [file normalize [pwd]]
set project_dir [file join $repo_dir build]

puts "Repo dir: $repo_dir"
puts "Project dir: $project_dir"

file mkdir $project_dir

puts "Creating Gowin project: $project_name"

create_project -name $project_name -dir $project_dir -pn $part_name -device_version $device_version -force

puts "Adding source and constraint files"

set uart_smoke 0
if {[info exists ::env(UART_SMOKE)] && $::env(UART_SMOKE) == "1"} {
    set uart_smoke 1
}

if {$uart_smoke} {
    puts "UART smoke-test top enabled"
    add_file [file join $repo_dir src top_uart_smoke.v]
} else {
    add_file [file join $repo_dir src top.v]
}
add_file [file join $repo_dir src uart_tx.v]
add_file [file join $repo_dir src uart_rx.v]
add_file [file join $repo_dir src command_parser.v]
add_file [file join $repo_dir src response_formatter.v]
add_file [file join $repo_dir src dna_ascii_to_2bit.v]
add_file [file join $repo_dir src kmer_shift_register.v]
add_file [file join $repo_dir src exact_match_counter.v]
add_file [file join $repo_dir src status_leds.v]
add_file [file join $repo_dir src fixed_math.vh]
add_file [file join $repo_dir src video_timing.v]
add_file [file join $repo_dir src sphere_intersect.v]
add_file [file join $repo_dir src render_core.v]
add_file [file join $repo_dir src debug_overlay.v]
add_file [file join $repo_dir constraints tang_primer_20k_dock.cst]
add_file [file join $repo_dir constraints tang_primer_20k_timing.sdc]

set_option -top_module $top_module
set_option -output_base_name $project_name


puts "Running Gowin build"

run all

puts "Build finished."
exit
