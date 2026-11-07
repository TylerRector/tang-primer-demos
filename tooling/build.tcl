set demo dna_count
if {[info exists ::env(DEMO)]} {
    set demo $::env(DEMO)
}
if {$demo ni {blink dna_count}} {
    error "Unknown demo: $demo (choose blink or dna_count)"
}
set project_name $demo
set top_module $demo
set part_name GW2A-LV18PG256C8/I7
set device_version C

# Save original repo directory before Gowin changes cwd
set repo_dir [file normalize [pwd]]
set project_dir [file join $repo_dir build $demo]

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
    set top_module top
    add_file [file join $repo_dir src top_uart_smoke.v]
} else {
    add_file [file join $repo_dir demos ${demo}.v]
}
if {$demo eq "dna_count" || $uart_smoke} {
    foreach source {uart_tx uart_rx command_parser response_formatter dna_ascii_to_2bit kmer_shift_register exact_match_counter status_leds} {
        add_file [file join $repo_dir src ${source}.v]
    }
    add_file [file join $repo_dir constraints tang_primer_20k_dock.cst]
} else {
    add_file [file join $repo_dir constraints blink.cst]
}
add_file [file join $repo_dir constraints tang_primer_20k_timing.sdc]

set_option -top_module $top_module
set_option -output_base_name $project_name


puts "Running Gowin build"

run all

puts "Build finished."
exit
