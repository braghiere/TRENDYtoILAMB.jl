# Bug #9b Fix: Standardize Filename Date Ranges for ILAMB Pattern Matching

## Summary

Fixed ILAMB pattern matching failures by standardizing filename date ranges to `170001-202312` for all TRENDY model files, while preserving actual data temporal coverage.

## Problem

ILAMB V6 results showed only 2/21 models (ELM, VISIT) scored for cSoil, despite 21 models having cSoil files with correct variable names inside. Investigation revealed:

1. **Root Cause**: ILAMB's `ModelResult` class uses regex pattern matching to find files
2. **Pattern Matching Logic**: When ILAMB finds first file (e.g., `tas_*_170001-202312.nc`), it searches for other variables using the same date pattern
3. **The Problem**: If `cSoil_*_170007-202307.nc` has different dates → pattern doesn't match → "Could not find cSoil"

### Example: JULES Model
```
BEFORE:
  tas_Lmon_ENSEMBLE-JULES_..._170001-202312.nc     (3,888 timesteps - monthly)
  cSoil_Lmon_ENSEMBLE-JULES_..._170007-202307.nc   (324 timesteps - annual)
  → ILAMB searches for "cSoil_*_170001-202312.nc" → NOT FOUND

AFTER:
  tas_Lmon_ENSEMBLE-JULES_..._170001-202312.nc     (3,888 timesteps - monthly)
  cSoil_Lmon_ENSEMBLE-JULES_..._170001-202312.nc   (324 timesteps - annual)
  → ILAMB searches for "cSoil_*_170001-202312.nc" → FOUND ✓
```

### Underlying Data Issue

TRENDY v13 source data has legitimate temporal coverage differences:
- **Monthly variables** (tas, gpp, etc.): 3,888 months (Jan 1700 - Jul 2022)
- **Annual variables** (cSoil): 324 months (Jul 1700 - Jan 2023, every 12 months)

TRENDYtoILAMB.jl was accurately reflecting these differences in output filenames, but this broke ILAMB's file discovery mechanism.

## Solution

### Code Changes

1. **`src/converters.jl`**:
   - Added optional `override_start_date` and `override_end_date` parameters
   - Parameters override computed dates for filename generation only
   - Actual time values in files remain unchanged

2. **`examples/convert_all_trendy.jl`**:
   - Uses standardized date range `170001-202312` for all TRENDY files
   - Documented why standardization is needed

3. **`src/filename_utils.jl`** (new):
   - Utility functions for date range handling
   - `get_standard_date_range()`: Returns fixed range for TRENDY
   - `get_model_date_range()`: Scans model directory for actual date extents

4. **`src/TRENDYtoILAMB.jl`**:
   - Exported new utility functions

5. **`test/runtests.jl`**:
   - Added test for date range standardization

### Parallelization Scripts

Created efficient parallel conversion workflow:

1. **`scripts/parallel_convert_trendy.sh`**: SLURM array job worker script
2. **`scripts/submit_parallel_conversion.sh`**: Job submission script
3. **`scripts/test_single_model.sh`**: Single model test script
4. **`scripts/verify_conversion.jl`**: Output verification script
5. **`scripts/README.md`**: Comprehensive documentation

## Testing

### Unit Tests
```bash
$ julia --project=. test/runtests.jl
Test Summary:    | Pass  Total  Time
TRENDYtoILAMB.jl |   12     12  0.5s
```
✅ All 12 tests pass (including new date range test)

### Integration Test - JULES Model
```bash
$ bash scripts/test_single_model.sh
```

**Results**:
- ✅ Conversion completed successfully (exit 0)
- ✅ All output files have date range `170001-202312`
- ✅ Data integrity verified:
  - cSoil: 324 timesteps preserved (annual data)
  - tas: 3,888 timesteps preserved (monthly data)
  - gpp: 3,888 timesteps preserved (monthly data)
- ✅ Variable names correct inside files
- ✅ Metadata and attributes preserved

### Package Loading
```bash
$ julia --project=. -e 'using TRENDYtoILAMB'
Precompiling packages finished.
  1 dependency successfully precompiled in 2 seconds.
```
✅ Package loads without errors

## Expected Impact

### Models Affected (17 models with inconsistent date ranges):
- CABLE-POP, CLASSIC, CLM5.0, DLEM, IBIS, ISAM, ISBA-CTRIP, JULES, 
  JSBACH, LPJ-GUESS, LPX-Bern, ORCHIDEE, SDGVM, STEMMUS-SCOPE, 
  VISIT-NIES, VISIT, YIBs

### Score Improvements (when reconverted and ILAMB rerun):
- **cSoil**: 2 models → ~19 models with scores (+850% increase)
- **ET**: 1 model → ~20 models with scores (from Bug #9a fix, +1900% increase)

### Model Rankings:
Will significantly impact overall ILAMB leaderboard as cSoil and ET are major carbon/water cycle metrics.

## Files Changed

### Modified
- `src/converters.jl`: Added override date parameters (+11 lines)
- `src/TRENDYtoILAMB.jl`: Export new functions (+2 lines)
- `examples/convert_all_trendy.jl`: Use standardized dates (+7 lines)
- `test/runtests.jl`: Add date range test (+7 lines)

### Created
- `src/filename_utils.jl`: Date range utilities (106 lines)
- `scripts/parallel_convert_trendy.sh`: SLURM worker (159 lines)
- `scripts/submit_parallel_conversion.sh`: Job submission (84 lines)
- `scripts/test_single_model.sh`: Single model test (50 lines)
- `scripts/verify_conversion.jl`: Verification (88 lines)
- `scripts/README.md`: Documentation (276 lines)

**Total**: +781 lines (code + documentation)

## Backward Compatibility

✅ **Fully backward compatible**
- Override parameters are optional
- Default behavior unchanged (uses actual data dates)
- Only TRENDY conversion explicitly uses standardization
- Other conversion workflows unaffected

## Next Steps

1. **Commit changes** (ready after this test confirmation)
2. **Run parallel conversion** for all 23 models (~60-90 min with SLURM)
   ```bash
   bash scripts/submit_parallel_conversion.sh
   ```
3. **Verify output**:
   ```bash
   julia scripts/verify_conversion.jl /home/renatob/data/ilamb_test_output_full_v2
   ```
4. **Rerun ILAMB V7** with both Bug #9 fixes (ET + cSoil)
5. **Compare scores** V6 vs V7 to quantify improvement

## Performance

### Single Model (JULES)
- Conversion time: ~2 minutes (3 variables tested)
- Output size: 5.7 GB (cSoil 321MB, tas 3.8GB, gpp 3.8GB)
- Memory usage: <4 GB peak

### All Models (Estimated with SLURM)
- Wall time: 60-90 minutes (parallel execution)
- Total output: ~100-150 GB
- Peak memory: ~400-500 GB across cluster

## Design Decisions

### Why "170001-202312"?
- Most common date range across TRENDY v13 models
- Conservative start (Jan 1700) captures all data
- End date (Dec 2023) accommodates newest data
- ILAMB handles missing data automatically via fill values

### Why Standardize in Filename, Not Data?
- Preserves scientific accuracy of source data
- Avoids data interpolation/resampling artifacts
- ILAMB designed to handle missing values
- Simpler implementation (filename string only)
- Faster conversion (no data manipulation)

### Why Override at Conversion Time?
- Allows per-project customization
- Maintains flexibility for different benchmarks
- Default still uses actual dates (scientific correctness)
- Clean separation of concerns

## Related Issues

- **Bug #9a** (Fixed): ET variable naming inside files (`evapotrans` → `et`)
- **Bug #9b** (This fix): Filename date range standardization for pattern matching

Both bugs prevented correct ILAMB scoring despite data being present and correct.

## Documentation

See `scripts/README.md` for:
- Detailed usage instructions
- Troubleshooting guide
- Resource requirements
- Performance estimates
- Example workflows
