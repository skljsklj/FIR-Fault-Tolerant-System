# This script forces errors on voters which are implemented using pair and spare redudancy.

# We force errors one by one on the same filter stage(19th stage) to demonstrate that it will keep working correctly until the last one fails to operate properly.

add_force {/tb/mac_triplex_duplex/data_o_pair[90]} -radix hex {4221 500ns}
add_force {/tb/mac_triplex_duplex/data_o_pair[91]} -radix hex {5433 700ns}
add_force {/tb/mac_triplex_duplex/data_o_pair[92]} -radix hex {4534 900ns}
add_force {/tb/mac_triplex_duplex/data_o_pair[93]} -radix hex {7381 1100ns}

# After the final voter has stopped working correctly we expect that the filter stops working correctly.
add_force {/tb/mac_triplex_duplex/data_o_pair[94]} -radix hex {7865 1300ns}
