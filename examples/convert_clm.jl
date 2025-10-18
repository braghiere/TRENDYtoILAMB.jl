using TRENDYtoILAMB
using NCDatasets
using Test

"""
Example script demonstrating the conversion of a CLM5.0 TRENDY dataset to ILAMB format.
"""

# Path to TRENDY data
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"

function main()
    # Test with cVeg from CLM5.0 S3 simulation
    dataset = TRENDYDataset(
        joinpath(TRENDY_DIR, "CLM5.0/S3/CLM6.0_S3_cVeg.nc"),
        "CLM5.0",
        "S3",
        "cVeg"
    )

    # Create output directory
    mkpath("output")

    @info "Converting $(dataset.model) $(dataset.simulation) $(dataset.variable) to ILAMB format..."
    
    # Convert to ILAMB format
    ilamb_dataset = convert_to_ilamb(dataset, output_dir="output")

    # Print some information about the conversion
    println("\nConverted file saved to: ", ilamb_dataset.path)

    # Verify the conversion
    @info "Verifying conversion..."
    verify_conversion(dataset, ilamb_dataset)
    
    @info "Conversion completed successfully!"
end

# Run the main function with error handling
try
    main()
catch e
    @error "Conversion failed" exception=(e, catch_backtrace())
    exit(1)
end