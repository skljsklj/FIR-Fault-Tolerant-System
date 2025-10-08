# This script forces errors on MAC modules which are implemented using triplex duplex redundancy.

# First, we force a couple of random errors on MAC modules at different stages in the FIR filter to demonstrate that everything is working fine. 
add_force {/tb/mac_triplex_duplex/mac_out[21]} -radix hex {0 100ns}
add_force {/tb/mac_triplex_duplex/mac_out[32]} -radix hex {0 110ns}
add_force {/tb/mac_triplex_duplex/mac_out[63]} -radix hex {0 120ns}
add_force {/tb/mac_triplex_duplex/mac_out[55]} -radix hex {0 140ns}
add_force {/tb/mac_triplex_duplex/mac_out[91]} -radix hex {0 150ns}
add_force {/tb/mac_triplex_duplex/mac_out[99]} -radix hex {0 160ns}

# Then, we force an error on MAC module 108 at the 19th order of the FIR filter to demonstrate that everything is working fine.
add_force {/tb/mac_triplex_duplex/mac_out[108]} -radix hex {0 600ns}

# After that, we add another error on MAC module 109, which is paired with MAC module 108, and we expect everything to still work fine.
add_force {/tb/mac_triplex_duplex/mac_out[109]} -radix hex {123 800ns}

# Finally, we add a third error on MAC module 110, which is not paired with the previous MAC modules (108 and 109), and we expect the filter to stop working correctly.
# This is due to the logic of the majority voter, which must have at least 2 out of 3 correct inputs.  
add_force {/tb/mac_triplex_duplex/mac_out[110]} -radix hex {554 1100ns}
