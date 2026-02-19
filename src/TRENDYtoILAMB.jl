module TRENDYtoILAMB

using NCDatasets
using Dates
using Statistics

# Export main functionality
export TRENDYDataset, ILAMBDataset
export convert_to_ilamb, verify_conversion, compare_datasets
export standardize_units, list_trendy_files, extract_variable_name
export convert_time_to_days, create_time_bounds
export get_variable_metadata, normalize_variable_case, get_ilamb_variables
export convert_data_values, convert_precipitation_values

# Include submodules
include("types.jl")
include("utils.jl")
include("ilamb_variables.jl")
include("unit_conversions.jl")
include("converters.jl")
include("time.jl")
include("variables.jl")

end # module