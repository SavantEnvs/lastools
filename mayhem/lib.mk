# Out-of-tree build of LASlib (+LASzip) and, optionally, the CLI tools the oracle drives.
# Mirrors LASlib/src/CMakeLists.txt and src/CMakeLists.txt without their in-tree output dirs.
#   make -f mayhem/lib.mk BUILD=mayhem/build-fuzz NDEBUG= lib
#   make -f mayhem/lib.mk BUILD=mayhem/build-tests tools
BUILD ?= mayhem/build-fuzz
CC    ?= clang
CXX   ?= clang++

INC := -ILASzip/include/laszip -ILASzip/src -ILASlib/inc -Isrc
# NDEBUG as upstream's CMake sets it, for the oracle tools; the fuzz build passes NDEBUG= so asserts stay on.
NDEBUG ?= -DNDEBUG
DEFS := $(NDEBUG) -DUNORDERED -DHAVE_UNORDERED_MAP

LAS_SRC := lasreader lasignore laswriter lasreader_las lasreader_bin lasreader_shp lasreader_asc \
  lasreader_bil lasreader_dtm lasreader_ply lasreader_qfit lasreader_txt lasreadermerged \
  lasreaderbuffered lasreaderstored lasreaderpipeon laswriter_las laswriter_bin laswriter_qfit \
  laswriter_wrl laswriter_txt laswritercompatible laswaveform13reader laswaveform13writer \
  lasutility lasfilter lastransform laskdtree lascopc lasformula_api_stub fopen_compressed
LAZ_SRC := lasreadpoint lasreaditemcompressed_v1 lasreaditemcompressed_v2 lasreaditemcompressed_v3 \
  lasreaditemcompressed_v4 laswritepoint laswriteitemcompressed_v1 laswriteitemcompressed_v2 \
  laswriteitemcompressed_v3 laswriteitemcompressed_v4 integercompressor arithmeticdecoder \
  arithmeticencoder arithmeticmodel lasindex lasquadtree lasinterval laszip mydefs lasmessage

OBJS := $(addprefix $(BUILD)/obj/,$(addsuffix .o,$(LAS_SRC) $(LAZ_SRC)))
TOOL_COMMON := wktparser geoprojectionconverter proj_loader proj_wrapper
TOOLS := laszip lasinfo las2las lasindex

vpath %.cpp LASlib/src LASzip/src src

# Per-file UBSan relaxations (a no-op without -fsanitize=undefined). The LASzip decoders let predictor
# arithmetic wrap on corrupt streams (signed-integer-overflow, thousands of hits per run); laszip.cpp
# switches on an enum built from raw header bytes (enum).
WRAP := -fno-sanitize=signed-integer-overflow
RELAX_integercompressor := $(WRAP)
RELAX_lasreaditemcompressed_v1 := $(WRAP)
RELAX_lasreaditemcompressed_v2 := $(WRAP)
RELAX_lasreaditemcompressed_v3 := $(WRAP)
RELAX_lasreaditemcompressed_v4 := $(WRAP)
RELAX_laszip := -fno-sanitize=enum

$(BUILD)/obj/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) -std=c++17 -MMD -MP $(DEFS) $(INC) $(CXXFLAGS) $(RELAX_$*) -c $< -o $@

$(BUILD)/liblaslib.a: $(OBJS)
	rm -f $@ && ar rcs $@ $^

lib: $(BUILD)/liblaslib.a

$(BUILD)/obj/tool_%.o: src/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) -std=c++17 -MMD -MP $(DEFS) $(INC) -Wno-deprecated -Wno-write-strings $(CXXFLAGS) -c $< -o $@

$(BUILD)/bin/%: $(BUILD)/obj/tool_%.o $(addprefix $(BUILD)/obj/,$(addsuffix .o,$(TOOL_COMMON))) $(BUILD)/liblaslib.a
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $^ -ldl -o $@

tools: $(addprefix $(BUILD)/bin/,$(TOOLS))

-include $(wildcard $(BUILD)/obj/*.d)

.PHONY: lib tools
.SECONDARY:
