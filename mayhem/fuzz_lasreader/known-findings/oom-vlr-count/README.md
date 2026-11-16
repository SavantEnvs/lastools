# VLR count drives an unbounded calloc

`LASreaderLAS::open` (LASlib/src/lasreader_las.cpp:449) callocs `number_of_variable_length_records * sizeof(LASvlr)` straight from the 4-byte header field, so a ~260-byte file asks for gigabytes. libFuzzer reports it as out-of-memory. Fix: reject counts that cannot fit in the bytes between the header and `offset_to_point_data`. Replay: `/mayhem/fuzz_lasreader -runs=1 repro`.
