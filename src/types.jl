# Abstract types for the package
abstract type AbstractTRENDYDataset end
abstract type AbstractILAMBDataset end

"""
    TRENDYDataset

Represents a TRENDY model output dataset.

# Fields
- `path::String`: Path to the NetCDF file
- `model::String`: Name of the TRENDY model
- `simulation::String`: Simulation type (S0, S1, S2, S3)
- `variable::String`: Variable name
"""
struct TRENDYDataset <: AbstractTRENDYDataset
    path::String
    model::String
    simulation::String
    variable::String
end

"""
    ILAMBDataset

Represents an ILAMB-compatible dataset.

# Fields
- `path::String`: Path to the output NetCDF file
- `variable::String`: Variable name in ILAMB convention
- `units::String`: Units in CF convention
- `time_units::String`: Time units (typically "days since YYYY-MM-DD")
- `calendar::String`: Calendar type (typically "noleap")
"""
struct ILAMBDataset <: AbstractILAMBDataset
    path::String
    variable::String
    units::String
    time_units::String
    calendar::String
end