# POINT14 v3 decoder allocates by a stream-supplied size

`LASreadItemCompressed_POINT14_v3::init` (LASzip/src/lasreaditemcompressed_v3.cpp:484) does `new U8[num_bytes]` with `num_bytes` read from the compressed chunk, so a 550-byte LAZ requests gigabytes (the RGBNIR14 and chunk-table readers have the same shape). Fix: compare against the remaining stream size before allocating. Replay: `/mayhem/fuzz_lasreader -runs=1 repro`.
