# EVLR count drives an unbounded calloc

`LASreaderLAS::open` (LASlib/src/lasreader_las.cpp:1011) callocs `number_of_extended_variable_length_records * sizeof(LASevlr)` from the 4-byte header field with no check against the stream length. Fix: bound the count by the bytes remaining after `start_of_first_extended_variable_length_record`. Replay: `/mayhem/fuzz_lasreader -runs=1 repro`.
