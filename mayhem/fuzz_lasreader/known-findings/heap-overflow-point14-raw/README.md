# Heap-buffer-overflow writing a converted POINT14 record

`LASreadItemRaw_POINT14_LE::read` (LASzip/src/lasreaditemraw.hpp:257) writes `gps_time` (8 bytes) into the converted point item; reached from `LASreaderLAS::seek` -> `LASreadPoint::seek` (lasreadpoint.cpp:440), so a LAS whose declared point record length is shorter than the point-14 layout overruns the heap point buffer. Fix: validate `point_data_record_length` against the point format in `LASreaderLAS::open`. Replay: `/mayhem/fuzz_lasreader -runs=1 repro`.
