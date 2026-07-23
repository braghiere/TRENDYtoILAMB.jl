# Parallel TRENDY Conversion Scripts

This directory contains scripts for efficiently converting TRENDY v13 data to ILAMB format using parallel processing.

## Problem Solved

**Bug #9b**: ILAMB's ModelResult class searches for files using regex pattern matching. When different variables have different date ranges in their filenames (e.g., `cSoil_*_170007-202307.nc` vs `tas_*_170001-202312.nc`), ILAMB fails to find all files. This fix standardizes all filenames per model to use `170001-202312` while preserving actual data coverage.

## Scripts

### 1. `submit_parallel_conversion.sh`
**Main script** - Submits parallel conversion jobs for all TRENDY models.

```bash
bash scripts/submit_parallel_conversion.sh
```

- **With SLURM**: Submits array job with one model per node (23 jobs)
- **Without SLURM**: Runs sequentially (slow, ~2-4 hours total)

**SLURM monitoring:**
```bash
# Check job status
squeue -u $USER

# Monitor specific job
tail -f logs/convert_JOBID_0.out

# Check completion status
sacct -j JOBID --format=JobID,JobName,State,ExitCode,Elapsed
```

### 2. `parallel_convert_trendy.sh`
**Worker script** - Converts one model (called by submit script).

Environment variables:
- `TRENDY_DIR`: Input directory (default: `/home/renatob/data/TRENDYv13`)
- `OUTPUT_DIR`: Output directory (default: `/home/renatob/data/ilamb_test_output_full_v2`)
- `MODEL`: Model name (set by SLURM array task ID)

Features:
- Standardized date ranges (`170001-202312`) for all files
- Resume support (skips already converted files)
- Memory efficient (GC after each file)
- Validates NetCDF files before conversion

### 3. `test_single_model.sh`
**Test script** - Converts only JULES to verify setup before full run.

```bash
bash scripts/test_single_model.sh
```

Use this to:
- Test SLURM configuration
- Verify conversion logic
- Check output format
- Estimate timing (~30min for JULES)

### 4. `verify_conversion.jl`
**Verification script** - Checks all converted files have standardized date ranges.

```bash
julia scripts/verify_conversion.jl [OUTPUT_DIR]
```

Verifies:
- All files per model have same date pattern (`170001-202312`)
- Identifies models with inconsistent patterns
- Reports statistics

## Usage Workflow

### Quick Start (Recommended)
```bash
# 1. Test with single model
cd /home/renatob/TRENDYtoILAMB.jl
bash scripts/test_single_model.sh

# 2. If test passes, submit full conversion
bash scripts/submit_parallel_conversion.sh

# 3. Monitor progress
squeue -u $USER

# 4. After completion, verify
julia scripts/verify_conversion.jl /home/renatob/data/ilamb_test_output_full_v2
```

### Manual Control
```bash
# Convert specific model
export MODEL="CABLE-POP"
export TRENDY_DIR="/home/renatob/data/TRENDYv13"
export OUTPUT_DIR="/home/renatob/data/ilamb_test_output_full_v2"
bash scripts/parallel_convert_trendy.sh

# Submit subset of models
sbatch --array=0-5 scripts/parallel_convert_trendy.sh  # First 6 models
```

## Output Structure

```
ilamb_test_output_full_v2/
├── CABLE-POP/
│   ├── cSoil_Lmon_ENSEMBLE-CABLE-POP_historical_r1i1p1f1_gn_170001-202312.nc
│   ├── et_Lmon_ENSEMBLE-CABLE-POP_historical_r1i1p1f1_gn_170001-202312.nc
│   └── ...
├── JULES/
│   ├── cSoil_Lmon_ENSEMBLE-JULES_historical_r1i1p1f1_gn_170001-202312.nc
│   ├── et_Lmon_ENSEMBLE-JULES_historical_r1i1p1f1_gn_170001-202312.nc
│   └── ...
└── ...
```

**Key Point**: ALL files within each model directory have the **same date range** in filename (`170001-202312`), even though actual data coverage may differ. This allows ILAMB pattern matching to work.

## Timing Estimates

### With SLURM (Parallel)
- **Single model**: 10-60 minutes (depends on number of variables and file sizes)
- **All 23 models**: ~60-90 minutes wall time (all run in parallel)

### Without SLURM (Sequential)
- **All 23 models**: ~2-4 hours total

### Specific Models
- JULES: ~30 min (12 variables, large files)
- CABLE-POP: ~20 min (10 variables)
- Smaller models: ~10 min

## Resource Requirements

### Per Job
- **Memory**: 32 GB (conservative; most models use <16GB)
- **CPUs**: 4 (for NetCDF I/O)
- **Time**: 4 hours (generous; most finish in 30-60min)

### Total (23 jobs)
- **Peak memory**: 736 GB (if all run simultaneously)
- **Typical peak**: ~400-500 GB (staggered starts)

## Troubleshooting

### Job fails immediately
```bash
# Check log files
tail -20 logs/convert_JOBID_TASKID.err

# Common issues:
# - Module load failures: Check if Julia is in PATH
# - Permission errors: Check OUTPUT_DIR is writable
# - Missing input: Verify TRENDY_DIR exists
```

### Some files missing
```bash
# Check which models completed
julia scripts/verify_conversion.jl OUTPUT_DIR

# Resubmit failed models only
# (script automatically skips completed files)
bash scripts/submit_parallel_conversion.sh
```

### Out of memory
```bash
# Reduce memory usage by processing sequentially
# Edit parallel_convert_trendy.sh: Add GC.gc() more frequently
```

### Wrong date ranges in output
```bash
# Verify scripts use override parameters:
grep "override_start_date" scripts/parallel_convert_trendy.sh

# Should show: override_start_date="170001", override_end_date="202312"
```

## Comparison: Before vs After

### Before Fix
```
JULES/
├── cSoil_Lmon_*_170007-202307.nc    ← Different dates
├── et_Lmon_*_170001-202312.nc       ← Different dates
└── gpp_Lmon_*_170001-202312.nc
```
**Result**: ILAMB finds only `et` and `gpp`, misses `cSoil`

### After Fix
```
JULES/
├── cSoil_Lmon_*_170001-202312.nc    ← Standardized
├── et_Lmon_*_170001-202312.nc       ← Standardized
└── gpp_Lmon_*_170001-202312.nc      ← Standardized
```
**Result**: ILAMB finds all variables ✓

## Expected Impact

After reconversion and ILAMB rerun:
- **cSoil scores**: 2/21 models → ~19/21 models
- **ET scores**: 1/23 models → ~20/23 models
- **Fixed models**: JULES, CABLE-POP, CLM5.0, DLEM, and 13 others

## Notes

- Actual time values inside NetCDF files remain unchanged
- Only filename dates are standardized
- ILAMB handles missing data with fill values automatically
- Resume support allows restarting interrupted jobs
- Logs are saved to `logs/` directory
