module TRENDYtoILAMB

using NCDatasets
using Dates

# Export main functionality
export TRENDYDataset, ILAMBDataset
export convert_to_ilamb, verify_conversion, compare_datasets
export standardize_units, list_trendy_files, extract_variable_name

# Include submodules
include("types.jl")
include("utils.jl")
include("converters.jl")
include("time.jl")
include("variables.jl")

end # module