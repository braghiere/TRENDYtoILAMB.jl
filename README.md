# TRENDYtoILAMB.jl

A Julia package for converting TRENDY model outputs to ILAMB-compatible format.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/your-username/TRENDYtoILAMB.jl")
```

## Usage

```julia
using TRENDYtoILAMB

# Convert a single TRENDY file to ILAMB format
dataset = TRENDYDataset(
    "/path/to/file.nc",
    "CLM5.0",
    "S3",
    "cVeg"
)

# Convert the file
ilamb_dataset = convert_to_ilamb(dataset, output_dir="output")
```

## Features

- Converts TRENDY NetCDF files to ILAMB-compatible format
- Handles time dimension conversion to ILAMB standard
- Implements CF-compliant unit conversions
- Supports all TRENDY models and variables
- Preserves metadata and adds required ILAMB attributes

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.