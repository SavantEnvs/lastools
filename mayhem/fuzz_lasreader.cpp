// Fuzzes the LAS/LAZ reader: header, VLRs/EVLRs, LASzip decompression of every point, and a seek.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "lasmessage.hpp"
#include "lasreader.hpp"
#include "lasreader_las.hpp"

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
    LASreadOpener opener;
    LASreaderLAS reader(&opener);
    if (!reader.open(file)) {
      rc = -1;
    } else {
      volatile double sink = 0;
      while (reader.read_point()) {
        const LASpoint& p = reader.point;
        sink = sink + p.get_x() + p.get_y() + p.get_z() + p.get_gps_time() + p.intensity + p.classification;
      }
      if (reader.npoints > 1 && reader.seek(reader.npoints / 2)) {
        for (int i = 0; i < 8 && reader.read_point(); i++) sink = sink + reader.point.get_x();
      }
      reader.close();
    }
  }
  fclose(file);
  return rc;
}
