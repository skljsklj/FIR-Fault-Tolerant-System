This project is an implementation of a fault-tolerant FIR filter using triplex-duplex redundancy on MAC modules and applying pair-and-a-spare redundancy on the voter.

Running create_project.tcl will create all the neccesary files for the project.
Running the force_error_mac.tcl will generate errors on MAC modules and the system will eventually fail, as expected.
Running the force_error_voter.tcl will generate errors on voters and the system will eventually fail, as expected.
