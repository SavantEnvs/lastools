# QFIT bounding-box scan loops forever on a file with fewer than 50 points

`LASreaderQFIT::open` (LASlib/src/lasreader_qfit.cpp:283) samples points with
`for (i = n/50; i < n; i += n/50)`. For any well-formed QFIT file with 1 to 49 points `n/50` is 0, so the
step is 0 and the loop never ends. This repro is a valid 4-point, version-40 QFIT file (`.qi`, selector
byte 4). Fix: use a step of `max(1, n/50)`. Replay: `/mayhem/fuzz_lasreadopener -runs=1 repro` (hangs).
