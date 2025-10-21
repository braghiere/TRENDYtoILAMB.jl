# TRENDYtoILAMB.jl

A Julia package for converting TRENDY model outputs to ILAMB-compatible NetCDF format.

## Overview

TRENDYtoILAMB.jl provides tools to convert TRENDY (Trends in Net Land-Atmosphere Carbon Exchange) model outputs into the format required by ILAMB (International Land Model Benchmarking). The package handles complex time encodings, standardizes metadata, and ensures CF-compliance for seamless integration with ILAMB benchmarking workflows.

## Features

- ✅ **Multiple Time Encodings**: Handles various time representations
  - Days/months/years since reference dates (1700, 1850, etc.)
  - Month indices (e.g., CARDAMOM: 1-252 → 2003-01 to 2023-12)
  - CF-compliant datetime objects with noleap calendars
  
- ✅ **ILAMB-Compliant Outputs**: Generates standardized filenames
  - Format: `{var}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{YYYYMM}-{YYYYMM}.nc`
  - Example: `gpp_Lmon_ENSEMBLE-CARDAMOM_historical_r1i1p1f1_gn_200301-202312.nc`

- ✅ **Robust Error Handling**: 
  - Safe attribute access with fallback defaults
  - Validates NetCDF files before conversion
  - Skips corrupted or missing files with clear error messages

- ✅ **Model-Specific Handling**: Special cases for models with unique encodings
  - CARDAMOM: Month index conversion
  - CABLE-POP: 1700 reference year handling
  - Automatic detection of time encoding types

- ✅ **19 ILAMB Variables Supported**:
  - Carbon fluxes: `gpp`, `nbp`, `npp`, `ra`, `rh`, `lai`
  - Hydrology: `mrro`, `mrros`, `mrso`, `evapotrans`
  - Carbon pools: `cSoil`, `cVeg`, `cLitter`, `cProduct`
  - Fire: `burntArea`, `fFire`
  - Forcing: `tas`, `pr`, `rsds`

- ✅ **Data Verification**: Built-in validation comparing input and output data

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/braghiere/TRENDYtoILAMB.jl")
```

Or for development:

```bash
git clone https://github.com/braghiere/TRENDYtoILAMB.jl.git
cd TRENDYtoILAMB.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Quick Start

### Convert a Single File

```julia
using TRENDYtoILAMB

# Create a dataset object
dataset = TRENDYDataset(
    "/path/to/TRENDY/CARDAMOM/S3/CARDAMOM_S3_gpp.nc",
    "CARDAMOM",  # Model name
    "S3",        # Simulation type
    "gpp"        # Variable name
)

# Convert to ILAMB format
ilamb_dataset = convert_to_ilamb(dataset, output_dir="/path/to/output")

# Verify the conversion
verify_conversion(dataset, ilamb_dataset)
```

### Batch Convert All Models (Sequential)

For small datasets or testing:

```julia
using TRENDYtoILAMB

# Use the provided example script
include("examples/convert_all_trendy.jl")
```

Or run from command line:

```bash
cd TRENDYtoILAMB.jl
julia --project=. examples/convert_all_trendy.jl
```

**Performance**: ~4.2 files/hour (~7 days for full TRENDY dataset)

### Batch Convert with Parallel Processing ⭐ **RECOMMENDED**

For production use and large datasets:

```bash
cd TRENDYtoILAMB.jl

# 1. Generate parallel conversion scripts
julia --project=. examples/convert_parallel_manual.jl

# 2. Launch parallel conversion (6 independent processes)
/home/renatob/launch_all_groups.sh

# 3. Monitor progress
/home/renatob/check_conversion_status.sh
```

**Performance**: ~400 files/hour (~2 hours for full TRENDY dataset - **100× faster!**)

See [docs/PARALLEL_CONVERSION.md](docs/PARALLEL_CONVERSION.md) for detailed guide.

### Background Processing

For long-running conversions:

```bash
# Sequential
nohup julia --project=. examples/convert_all_trendy.jl > conversion.log 2>&1 &

# Parallel (already runs in background)
/home/renatob/launch_all_groups.sh
```

## Usage Examples

### Example 1: Convert with Verification

```julia
using TRENDYtoILAMB, NCDatasets

# Convert file
dataset = TRENDYDataset(
    "/data/TRENDY/CABLE-POP/S3/CABLE-POP_S3_cVeg.nc",
    "CABLE-POP", "S3", "cVeg"
)

output = convert_to_ilamb(dataset, output_dir="/data/ilamb_ready/CABLE-POP")

# Inspect output
ds = NCDataset(output.path)
println("Time range: ", ds["time"][1], " to ", ds["time"][end])
println("Variables: ", keys(ds))
close(ds)
```

### Example 2: Check Output Filename

```julia
# The output filename is automatically generated in ILAMB format
# For CARDAMOM gpp from 2003-01 to 2023-12:
# → gpp_Lmon_ENSEMBLE-CARDAMOM_historical_r1i1p1f1_gn_200301-202312.nc
```

### Example 3: Monitor Batch Conversion

```bash
# Sequential conversion
ps aux | grep julia | grep convert_all_trendy
tail -f conversion.log
find /data/ilamb_ready -name "*.nc" -type f | wc -l

# Parallel conversion
/home/renatob/check_conversion_status.sh
tail -f /home/renatob/group_*.log
```

### Example 4: Parallel Conversion

For fastest processing (100× speedup):

```bash
cd TRENDYtoILAMB.jl
julia --project=. examples/convert_parallel_manual.jl
/home/renatob/launch_all_groups.sh
```

Monitor progress:

```bash
/home/renatob/check_conversion_status.sh
```

See [examples/README.md](examples/README.md) for more examples.

## Performance

TRENDYtoILAMB.jl offers two conversion modes:

| Mode | Speed | Time (840 files) | Best For |
|------|-------|------------------|----------|
| **Sequential** | 4.2 files/hour | ~7 days | Testing, small datasets |
| **Parallel (6 workers)** ⭐ | 400 files/hour | ~2 hours | **Production, large datasets** |

**Parallel processing is ~100× faster** and recommended for production use.

See [docs/PARALLEL_CONVERSION.md](docs/PARALLEL_CONVERSION.md) for setup guide.

## Directory Structure

### Input (TRENDY v13 format)
```
TRENDYv13/
├── CABLE-POP/
│   ├── S0/
│   ├── S1/
│   ├── S2/
│   └── S3/
│       ├── CABLE-POP_S3_gpp.nc
│       ├── CABLE-POP_S3_npp.nc
│       └── ...
├── CARDAMOM/
├── CLASSIC/
└── ...
```

### Output (ILAMB format)
```
ilamb_ready/
├── CABLE-POP/
│   ├── gpp_Lmon_ENSEMBLE-CABLE-POP_historical_r1i1p1f1_gn_170001-202403.nc
│   ├── npp_Lmon_ENSEMBLE-CABLE-POP_historical_r1i1p1f1_gn_170001-202403.nc
│   └── ...
├── CARDAMOM/
│   ├── gpp_Lmon_ENSEMBLE-CARDAMOM_historical_r1i1p1f1_gn_200301-202312.nc
│   └── ...
└── CLASSIC/
    └── ...
```

## API Reference

### Core Types

- `TRENDYDataset`: Represents a TRENDY model output file
- `ILAMBDataset`: Represents a converted ILAMB-format file

### Main Functions

- `convert_to_ilamb(dataset; output_dir)`: Convert TRENDY to ILAMB format
- `verify_conversion(trendy_ds, ilamb_ds)`: Verify data integrity
- `convert_time_to_days(times, time_attrib)`: Handle time conversions
- `create_time_bounds(times)`: Generate time bounds for monthly data

### Utility Functions

- `list_trendy_files(dir)`: List all TRENDY NetCDF files
- `extract_variable_name(filename)`: Parse variable from filename
- `standardize_units(var, units)`: Convert to CF-compliant units
- `get_variable_metadata(var)`: Get ILAMB metadata for variable

## Supported Models

TRENDY v13 models tested:
- CABLE-POP
- CARDAMOM
- CLASSIC
- CLM5.0
- DLEM
- IBIS
- ISAM
- JSBACH
- JULES
- LPJ-GUESS
- LPJmL
- LPJwsl
- LPX-Bern
- OCN
- ORCHIDEE
- SDGVM
- VISIT
- And more...

## Time Handling

The package handles various time encodings:

| Format | Example | Reference Year |
|--------|---------|----------------|
| Days since | `days since 1699-12-31` | 1700 |
| Years since | `years since 1700-6-15` | 1700 |
| Months since | `months since 1700-1-16` | 1700 |
| Month indices | `1, 2, 3, ..., 252` | Model-specific |

All times are converted to: `days since 1850-01-01` with `noleap` calendar.

## Known Issues

- Some TRENDY files may be corrupted (HDF errors) - these are automatically skipped
- Variables not in the ILAMB list are skipped during batch conversion
- CARDAMOM uses month indices instead of proper time encoding (handled automatically)
- Some models may have missing variables (e.g., incomplete hydrology data)

## Development

### Running Tests

```bash
julia --project=. test/runtests.jl
```

### Testing Single Model

```bash
julia --project=. examples/test_convert_single_model.jl
```

Edit the `TEST_MODEL` constant to test different models.

### Documentation

- [Main README](README.md) - Package overview and usage
- [Examples README](examples/README.md) - Example scripts guide
- [Parallel Conversion Guide](docs/PARALLEL_CONVERSION.md) - Parallel processing setup
- [Development Docs](docs/dev/) - Technical documentation and development notes
- [CHANGELOG](CHANGELOG.md) - Version history and changes

## Citation

If you use this package in your research, please cite:

```bibtex
@software{trendytoilamb2024,
  author = {Braghiere, Renato K.},
  title = {TRENDYtoILAMB.jl: Convert TRENDY outputs to ILAMB format},
  year = {2024},
  url = {https://github.com/braghiere/TRENDYtoILAMB.jl}
}
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with clear commit messages
4. Add tests for new functionality
5. Update documentation as needed
6. Submit a pull request

## License

This project is licensed under the MIT License.

## Acknowledgments

- TRENDY project for providing model outputs
- ILAMB team for benchmarking framework specifications
- NCDatasets.jl for robust NetCDF handling