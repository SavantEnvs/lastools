# Quadtree cell queries run (nearly) forever on a hostile index

A 67-byte LAX makes `LASquadtree::has_more_cells` / `intersect_*_with_cells` (LASzip/src/lasquadtree.cpp:937-1535) spend more than the 15 s libFuzzer limit enumerating cells of a hostile quadtree (levels and extent come straight from the file). Fix: bound `levels` and reject non-finite extents in `LASquadtree::read`. Replay: `/mayhem/fuzz_lasindex -runs=1 repro`.
