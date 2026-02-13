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
    clean = strip(units)
    # Remove LaTeX-style markers (e.g., kg m$^{-2}$ s$^{-1}$ → kg m-2 s-1)
    clean = replace(clean, "\$" => "")
    clean = replace(clean, r"\^\{(-?\d+)\}" => SubstitutionString("\\1"))
    clean = replace(clean, r"\^(-?\d+)" => SubstitutionString("\\1"))
    clean = replace(clean, r"\s+" => " ") # Collapse repeated spaces
    clean = strip(clean)
    get(UNIT_CONVERSIONS, clean, clean)
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
        
        # Handle missing values and NaN in comparison
        if size(data_orig) == size(data_ilamb)
            # Compare only valid (non-missing, non-NaN) values
            mask_orig = .!ismissing.(data_orig) .& .!isnan.(Float64.(data_orig))
            mask_ilamb = .!ismissing.(data_ilamb) .& .!isnan.(Float64.(data_ilamb))

            if all(mask_orig .== mask_ilamb)
                # Same missing pattern
                valid_data_orig = data_orig[mask_orig]
                valid_data_ilamb = data_ilamb[mask_ilamb]

                if isempty(valid_data_orig)
                    println("\nData verification: ⚠️  All values are missing or NaN")
                elseif all(valid_data_orig .≈ valid_data_ilamb)
                    println("\nData verification: ✓ Variable data matches (within floating-point tolerance)")
                else
                    println("\nData verification: ⚠️  Variable data differs slightly")
                    diff = abs.(valid_data_orig .- valid_data_ilamb)
                    # Filter out any NaN values in diff before computing statistics
                    valid_diff = diff[.!isnan.(diff)]
                    if !isempty(valid_diff)
                        println("Max absolute difference: ", maximum(valid_diff))
                        println("Mean absolute difference: ", mean(valid_diff))
                    else
                        println("Unable to compute difference statistics (all NaN)")
                    end
                end
            else
                println("\nData verification: ⚠️  Missing value patterns differ")
                println("Original missing/NaN count: ", sum(.!mask_orig))
                println("ILAMB missing/NaN count: ", sum(.!mask_ilamb))
            end
        else
            println("\nData verification: ⚠️  Variable data differs")
            println("Original size: ", size(data_orig))
            println("ILAMB size: ", size(data_ilamb))

            # Additional diagnostics
            if size(data_orig) == size(data_ilamb)
                diff = data_orig .- data_ilamb
                abs_diff = abs.(diff)
                # Filter out NaN values
                valid_diff = abs_diff[.!isnan.(abs_diff)]
                if !isempty(valid_diff)
                    println("Max absolute difference: ", maximum(valid_diff))
                    println("Mean absolute difference: ", mean(valid_diff))
                else
                    println("Unable to compute difference statistics (all NaN)")
                end
            end
        end
    catch e
        println("\n⚠️  Warning: Verification failed with error: $e")
        println("Conversion may still be valid - check output manually if needed")
    finally
        close(ds_orig)
        close(ds_ilamb)
    end
end
