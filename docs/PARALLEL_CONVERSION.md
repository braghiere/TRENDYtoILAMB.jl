# Parallel Conversion Guide

This guide explains how to convert TRENDY files in parallel for significantly faster processing.

## Performance Comparison

| Method | Speed | Time for 840 files | Best For |
|--------|-------|-------------------|----------|
| Sequential | 4.2 files/hour | ~7 days | Small datasets, testing |
| Manual Parallel (6 workers) | ~400 files/hour | ~2 hours | **Recommended for production** |

## Quick Start

### 1. Generate Parallel Scripts

```bash
cd TRENDYtoILAMB.jl
julia --project=. examples/convert_parallel_manual.jl
```

This creates:
- `/home/renatob/convert_group_*.jl` - 6 conversion scripts (one per group)
- `/home/renatob/launch_all_groups.sh` - Master launcher

### 2. Launch Parallel Conversion

```bash
/home/renatob/launch_all_groups.sh
```

### 3. Monitor Progress

```bash
# Quick status check
/home/renatob/check_conversion_status.sh

# Watch live progress
watch -n 10 'find /home/renatob/data/ilamb_ready -name "*.nc" | wc -l'

# Check individual group logs
tail -f /home/renatob/group_*.log
```

## How It Works

### File Distribution Strategy

Files are split by **model** across 6 independent Julia processes:

```
launch_all_groups.sh
├── Group 1 (48 files) → CABLE-POP, CARDAMOM models
├── Group 2 (40 files) → CLASSIC, CLM5.0 models  
├── Group 3 (50 files) → DLEM, ED models
├── Group 4 (49 files) → ELM, IBIS models
├── Group 5 (35 files) → ISAM, JSBACH models
└── Group 6 (35 files) → JULES, LPJ-GUESS models
```

**Why split by model?**
- Prevents file conflicts (each model's files written by single process)
- Even workload distribution
- Simpler error tracking

### Architecture

Each group:
1. Runs as independent Julia process
2. Has its own log file (`group_N.log`)
3. Processes only its assigned files
4. Outputs to model-specific directories

**No coordination needed** - groups work completely independently!

## Customization

### Adjust Number of Groups

Edit `examples/convert_parallel_manual.jl`:

```julia
# Change from 6 to desired number (e.g., 12 for more parallelism)
groups = split_by_model(remaining_files, 12)  # Line ~108
```

Then regenerate scripts:

```bash
julia --project=. examples/convert_parallel_manual.jl
```

### Modify File Filters

To process only specific variables, edit the `ILAMB_VARS` constant:

```julia
const ILAMB_VARS = [
    "gpp", "nbp", "npp",  # Only carbon fluxes
    # Comment out unwanted variables
]
```

### Change Output Directory

Modify `OUTPUT_DIR` in `convert_parallel_manual.jl`:

```julia
const OUTPUT_DIR = "/your/custom/output/path"
```

## Memory Management

Each group includes automatic garbage collection:

```julia
GC.gc()              # After each file
GC.gc(true)          # Every 10 files (aggressive)
```

**Typical memory usage**: 0.3-0.5 GB per process (~2-3 GB total for 6 groups)

## Troubleshooting

### Processes Stall

**Symptom**: Processes running but no new files created

**Solutions**:
1. Check logs for errors: `tail -100 /home/renatob/group_*.log`
2. Restart specific group: `julia --project=. /home/renatob/convert_group_N.jl`
3. Check disk space: `df -h`

### Output Files in Wrong Location

**Symptom**: Files in `/ilamb_ready/` instead of `/ilamb_ready/{model}/`

**Cause**: Old version of parallel script

**Fix**: Regenerate scripts with latest version

### Group Finishes Too Fast

**Symptom**: Group completes but fewer files than expected

**Cause**: Files already converted (skip detection working)

**Verify**: Check `is_converted()` function detects existing files correctly

## Technical Details

### Why Not Distributed Computing?

We tried Julia's `Distributed` package but encountered:
- ❌ Package loading overhead (minutes per worker)
- ❌ Stalls during initialization
- ❌ Complex debugging

Manual parallel approach is:
- ✅ Simple and reliable
- ✅ Fast startup (<1 second)
- ✅ Easy to monitor and debug
- ✅ 100× faster than sequential

### Why Not Multi-Threading?

**NetCDF/HDF5 libraries are not thread-safe**

Using `Threads.@threads` causes:
- Segmentation faults
- Memory corruption
- Unaligned chunk errors

**Must use separate processes** (not threads) for parallel NetCDF writes.

## Advanced Usage

### Resume After Interruption

The conversion is **resumable** - already-converted files are automatically skipped:

```bash
# Conversion interrupted? Just relaunch
/home/renatob/launch_all_groups.sh

# Or regenerate to get updated file counts
julia --project=. examples/convert_parallel_manual.jl
/home/renatob/launch_all_groups.sh
```

### Process Subset of Models

Edit a group script manually to process only specific models:

```julia
# In /home/renatob/convert_group_1.jl
files = [
    # Keep only files for desired models
    "/path/to/CABLE-POP/S3/CABLE-POP_S3_gpp.nc",
    "/path/to/CABLE-POP/S3/CABLE-POP_S3_npp.nc",
]
```

### Monitor Resource Usage

```bash
# Check CPU and memory per group
ps aux | grep convert_group

# Monitor total resource usage
htop  # or top
```

## Performance Tips

1. **SSD Storage**: Use SSD for input/output for 2-3× faster I/O
2. **More Groups**: Increase from 6 to 12 groups if you have >50 cores
3. **Batch Size**: Process models separately if single model has many files
4. **Disk Space**: Ensure 2× input size available for output

## See Also

- `examples/convert_all_trendy.jl` - Sequential conversion (slower but simpler)
- `docs/dev/PARALLEL_STRATEGY.md` - Technical deep-dive
- `docs/dev/PARALLEL_EXPLORATION_SUMMARY.md` - Alternative approaches tried
