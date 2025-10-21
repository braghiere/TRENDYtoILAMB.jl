# Examples

This directory contains example scripts for converting TRENDY model outputs to ILAMB format.

## Production Scripts

### `convert_all_trendy.jl` - Sequential Conversion

**Best for**: Small datasets, testing, simple deployments

```bash
julia --project=.. convert_all_trendy.jl
```

**Features**:
- Processes all TRENDY files sequentially
- Memory-efficient with automatic garbage collection
- Robust error handling
- Skip detection for resumable conversions

**Performance**: ~4.2 files/hour (~7 days for 840 files)

**Usage**:
```julia
# Edit paths in the script
const TRENDY_DIR = "/path/to/TRENDYv13"
const OUTPUT_DIR = "/path/to/ilamb_ready"

# Run in background
nohup julia --project=.. convert_all_trendy.jl > conversion.log 2>&1 &
```

---

### `convert_parallel_manual.jl` - Parallel Conversion

**Best for**: Large datasets, production use ⭐ **RECOMMENDED**

```bash
julia --project=.. convert_parallel_manual.jl  # Generate scripts
/home/renatob/launch_all_groups.sh            # Launch conversion
```

**Features**:
- Splits work across 6 independent processes
- 100× faster than sequential (~2 hours for 840 files)
- Model-based file distribution (no conflicts)
- Individual log files per group
- Resumable (skips already-converted files)

**Performance**: ~400 files/hour

**Monitoring**:
```bash
# Check status
/home/renatob/check_conversion_status.sh

# Watch logs
tail -f /home/renatob/group_*.log

# Count completed files
find /home/renatob/data/ilamb_ready -name "*.nc" | wc -l
```

See [docs/PARALLEL_CONVERSION.md](../docs/PARALLEL_CONVERSION.md) for detailed guide.

---

### `test_convert_single_model.jl` - Single Model Test

**Best for**: Testing, debugging specific models

```bash
julia --project=.. test_convert_single_model.jl
```

**Features**:
- Tests conversion for one model
- Detailed output for debugging
- Quick validation of changes

**Usage**:
```julia
# Edit the model name in the script
const TEST_MODEL = "CARDAMOM"  # Change this

# Run
julia --project=.. test_convert_single_model.jl
```

---

## Archive

The `archive/` directory contains experimental and obsolete scripts:

- `convert_all_trendy_parallel.jl` - Thread-based conversion (doesn't work with NetCDF)
- `convert_all_trendy_distributed*.jl` - Distributed computing attempts (poor scaling)
- `test_distributed*.jl` - Distributed conversion tests
- `test_parallel_conversion.jl` - Multi-threading tests
- `check_time_formats.jl` - Time encoding analysis
- `convert_clm.jl` - CLM-specific converter
- Other development/test scripts

**These are kept for reference but not recommended for production use.**

---

## Quick Comparison

| Script | Speed | Use Case | Complexity |
|--------|-------|----------|------------|
| `convert_all_trendy.jl` | Slow (7 days) | Testing, small datasets | Simple ⭐ |
| `convert_parallel_manual.jl` | Fast (2 hours) | Production, large datasets | Medium ⭐⭐ |
| `test_convert_single_model.jl` | N/A | Debugging | Simple ⭐ |

---

## Customization

### Change Output Directory

Edit the `OUTPUT_DIR` constant in any script:

```julia
const OUTPUT_DIR = "/your/custom/path"
```

### Filter Variables

Modify the `ilamb_vars` list to process only specific variables:

```julia
ilamb_vars = [
    "gpp", "npp", "nbp",  # Only carbon fluxes
]
```

### Adjust Parallelism

In `convert_parallel_manual.jl`, change the number of groups:

```julia
groups = split_by_model(remaining_files, 12)  # Change 6 → 12 for more parallelism
```

---

## See Also

- [Main README](../README.md) - Package overview and API
- [Parallel Conversion Guide](../docs/PARALLEL_CONVERSION.md) - Detailed parallel conversion documentation
- [Development Docs](../docs/dev/) - Technical documentation and development notes
