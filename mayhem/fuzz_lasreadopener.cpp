// Fuzzes the file readers LASreadOpener dispatches by extension. The first input byte selects the
// extension, the rest is the file content. "qi" is the QFIT reader's extension (lasreader.cpp).
// "asc", "bil" and "dtm" are left out: all three readers attach a malloc'd Raster LAZ VLR payload that
// LASheader frees with delete[] (lasreader_asc.cpp:352, lasreader_bil.cpp:354,
// lasreader_dtm.cpp:1181), which ASan reports as alloc-dealloc-mismatch on every valid input.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lasmessage.hpp"
#include "lasreader.hpp"

static const char* const kExt[] = {"las", "laz", "bin", "shp", "qi", "ply", "txt"};
static char g_path[4096];

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  set_message_log_level(LAS_QUIET);
  halt_on_error(false);  // laserror() would otherwise exit() the process
  const char* tmp = getenv("TMPDIR");
  snprintf(g_path, sizeof(g_path), "%s/fuzz_lasreadopener-%d", (tmp && *tmp) ? tmp : "/tmp", (int)getpid());
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 2) return -1;
  const char* ext = kExt[data[0] % (sizeof(kExt) / sizeof(kExt[0]))];
  char path[4200];
  snprintf(path, sizeof(path), "%s.%s", g_path, ext);
  FILE* f = fopen(path, "wb");
  if (!f) return -1;
  fwrite(data + 1, 1, size - 1, f);
  fclose(f);

  int rc = 0;
  {
    LASreadOpener opener;
    opener.set_file_name(path);
    opener.set_parse_string("xyztirn");
    LASreader* reader = opener.open();
    if (!reader) {
      rc = -1;
    } else {
      volatile double sink = 0;
      while (reader->read_point()) {
        const LASpoint& p = reader->point;
        sink = sink + p.get_x() + p.get_y() + p.get_z() + p.intensity + p.classification;
      }
      reader->close();
      delete reader;
    }
  }
  unlink(path);
  return rc;
}
