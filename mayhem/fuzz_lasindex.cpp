// Fuzzes the LAX spatial-index parser (LASindex -> LASquadtree + LASinterval).
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "bytestreamout_nil.hpp"
#include "lasindex.hpp"
#include "lasmessage.hpp"
#include "lasquadtree.hpp"

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  set_message_log_level(LAS_QUIET);
  halt_on_error(false);  // laserror() would otherwise exit() the process
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size == 0) return -1;  // fmemopen cannot map an empty buffer
  FILE* file = fmemopen(const_cast<uint8_t*>(data), size, "rb");
  if (!file) return -1;
  int rc = 0;
  {
    LASindex index;
    if (!index.read(file)) {
      rc = -1;
    } else {
      // Query a small window at the corner of the indexed extent, as an embedder fetching one area would.
      LASquadtree* q = index.get_spatial();
      if (q) {
        const F64 x = q->get_min_x(), y = q->get_min_y();
        index.intersect_rectangle(x, y, x + 1.0, y + 1.0);
        index.get_intervals();
        index.intersect_tile((F32)x, (F32)y, 1.0f);
        index.get_intervals();
        index.intersect_circle(x, y, 1.0);
        index.get_intervals();
      }
      ByteStreamOutNil out;
      index.write(&out);
    }
  }
  fclose(file);
  return rc;
}
