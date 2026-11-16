# Division by zero in the arithmetic decoder

`ArithmeticDecoder::decodeSymbol` (LASzip/src/arithmeticdecoder.cpp:190) divides by `length >>= DM__LengthShift`, which is 0 once the range coder state is corrupt; UBSan reports division by zero (SIGFPE without it). Fix: treat `length == 0` as a decode error. Replay: `/mayhem/fuzz_lasreader -runs=1 repro`.
