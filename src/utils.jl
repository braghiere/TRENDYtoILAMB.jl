# Dictionary of TRENDY to CF standard units conversions
const UNIT_CONVERSIONS = Dict(
    "gC/m^2" => "kg m-2",
    "gC/m2" => "kg m-2",
    "mm/yr" => "kg m-2 s-1",
    "mm/year" => "kg m-2 s-1",
    "gC m-2" => "kg m-2",
    "gC m-2 yr-1" => "kg m-2 s-1",
    "kgC m-2" => "kg m-2"
)

"""
    standardize_units(units::String)

Convert TRENDY units to CF-compliant units.
"""
function standardize_units(units::String)
    get(UNIT_CONVERSIONS, units, units)
end

"""
    list_trendy_files(root_dir::String, model::String, simulation::String)

List all NetCDF files for a given TRENDY model and simulation.
"""
function list_trendy_files(root_dir::String, model::String, simulation::String)
    pattern = joinpath(root_dir, model, simulation, "*.nc")
    return glob(pattern)
end

"""
    extract_variable_name(filepath::String)

Extract the variable name from a TRENDY NetCDF filename.
"""
function extract_variable_name(filepath::String)
    # Implementation depends on the actual filename pattern
    basename(filepath)
end

"""
    compare_datasets(ds1::Dataset, ds2::Dataset; name1::String="Dataset 1", name2::String="Dataset 2")

Compare two NetCDF datasets and print their key properties.
"""
function compare_datasets(ds1::Dataset, ds2::Dataset; name1::String="Dataset 1", name2::String="Dataset 2")
    println("\n$name1:")
    println("Dimensions: ", collect(keys(ds1.dim)))
    println("Variables: ", collect(keys(ds1)))
    for var in keys(ds1)
        println("  $var: ", Dict(ds1[var].attrib))
    end

    println("\n$name2:")
    println("Dimensions: ", collect(keys(ds2.dim)))
    println("Variables: ", collect(keys(ds2)))
    for var in keys(ds2)
        println("  $var: ", Dict(ds2[var].attrib))
    end
end

"""
    verify_conversion(dataset::TRENDYDataset, ilamb_dataset::ILAMBDataset)

Verify the conversion between a TRENDY dataset and its ILAMB counterpart.
"""
function verify_conversion(dataset::TRENDYDataset, ilamb_dataset::ILAMBDataset)
    ds_orig = Dataset(dataset.path)
    ds_ilamb = Dataset(ilamb_dataset.path)
    
    try
        compare_datasets(ds_orig, ds_ilamb, name1="Original TRENDY file", name2="Converted ILAMB file")
        
        # Verify data consistency
        var_name = dataset.variable
        data_orig = ds_orig[var_name][:]
        data_ilamb = ds_ilamb[var_name][:]
        
        if size(data_orig) == size(data_ilamb) && all(data_orig .≈ data_ilamb)
            println("\nData verification: ✓ Variable data matches (within floating-point tolerance)")
        else
            println("\nData verification: ✗ Variable data differs")
            println("Original size: ", size(data_orig))
            println("ILAMB size: ", size(data_ilamb))
            
            # Additional diagnostics
            if size(data_orig) == size(data_ilamb)
                diff = data_orig .- data_ilamb
                println("Max absolute difference: ", maximum(abs.(diff)))
                println("Mean absolute difference: ", mean(abs.(diff)))
            end
        end
    finally
        close(ds_orig)
        close(ds_ilamb)
    end
end