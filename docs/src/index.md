# TRENDYtoILAMB.jl

Documentation for TRENDYtoILAMB.jl

## Overview

TRENDYtoILAMB.jl is a Julia package that converts TRENDY v13 model outputs into ILAMB-compatible format. It handles all necessary conversions including:

- Time dimension standardization
- Unit conversions to CF convention
- Metadata enrichment
- Variable name mapping

## Quick Start

```julia
using TRENDYtoILAMB

# Create a dataset object
dataset = TRENDYDataset(
    "/path/to/trendy/file.nc",
    "CLM5.0",
    "S3",
    "cVeg"
)

# Convert to ILAMB format
ilamb_dataset = convert_to_ilamb(dataset, output_dir="output")