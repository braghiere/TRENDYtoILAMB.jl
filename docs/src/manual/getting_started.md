# Getting Started

## Installation

To install TRENDYtoILAMB.jl, use Julia's package manager:

```julia
using Pkg
Pkg.add(url="https://github.com/braghiere/TRENDYtoILAMB.jl.git")
```

## Basic Usage

Here's a simple example of converting a TRENDY NetCDF file to ILAMB format:

```julia
using TRENDYtoILAMB

# Create a TRENDY dataset
dataset = TRENDYDataset(
    "path/to/CLM5.0/S3/cVeg.nc",
    "CLM5.0",
    "S3",
    "cVeg"
)

# Convert to ILAMB format
ilamb_dataset = convert_to_ilamb(dataset, output_dir="output")

# Verify the conversion
verify_conversion(dataset, ilamb_dataset)
```

## Supported Variables

Currently supported TRENDY variables include:

- `cVeg`: Vegetation Carbon Content
- `cSoil`: Soil Carbon Content
- `gpp`: Gross Primary Production

Additional variables can be added by extending the `VARIABLE_MAPPINGS` dictionary in the package.