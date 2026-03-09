# FlexSpin Pin Constants Plan

## Problem
FlexSpin 7.6.1 cannot compile the driver — 10 methods use local variables as pin operands in inline PASM org/end blocks, which FlexSpin cannot handle when vars are forced to memory.

## Solution — 7 Changes (A-G)

### A. Driver CON pin constants
Replace 6 VAR pin fields (cs, mosi, miso, sck, flash_cs_pin, flash_sck_pin) with CON constants:
- PIN_SD_CS=60, PIN_MOSI=59, PIN_MISO=58, PIN_SD_SCK=61, PIN_FL_CS=61, PIN_FL_SCK=60

### B. Simplify init() signature
Remove 4 pin parameters: `init(sd_cs, _mosi, _miso, sd_sck)` -> `init()`

### C. Replace local pin vars in 10 PASM methods
Use #PIN_xxx immediate constants in PASM, bare PIN_xxx in Spin2 code.
Methods: fl_command, fl_send, fl_receive, sp_transfer_8, sp_transfer_32, sp_transfer_variable, readSector, readSectors, writeSector, writeSectors.

### D. fl_command @command workaround
Use {$flexspin} conditional to copy command to DAT var before @command call.

### E. Lowercase preprocessor directives (40 files, 473 occurrences)
#IFDEF -> #ifdef, #IFNDEF -> #ifndef, #ENDIF -> #endif, #DEFINE -> #define, #PRAGMA EXPORTDEF -> #pragma exportdef

### F. Update all callers — remove pin args from init()
42 call sites across ~38 files.

### G. Update utility libs — remove pin pass-through
isp_fsck_utility.spin2 (startFsck, startAudit, doStart) and isp_format_utility.spin2 (format, formatWithLabel, startFormat, startFormatWithLabel).

## Execution Order
1. A+B+C+D (driver only)
2. Compile-check both compilers
3. E (lowercase directives, all files)
4. F+G (caller updates)
5. Final verification with both compilers
