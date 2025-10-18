#=
Test conversion script - processes a single model to verify functionality
=#

using TRENDYtoILAMB
using NCDatasets
using Printf

# Path to TRENDY data
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready_test"
const TEST_MODEL = "CABLE-POP"  # Change this to test different models

# List of variables that ILAMB uses
ilamb_vars = [
    "gpp", "nbp", "npp", "ra", "rh", "lai", 
    "mrro", "mrros", "mrso", "evapotrans",
    "cSoil", "cVeg", "cLitter", "cProduct",
    "burntArea", "fFire",
]

# Statistics tracking
total_files = 0
converted_files = 0
failed_files = String[]
skipped_files = String[]
successful_vars = Dict{String,Int}()
error_types = Dict{String,Int}()

println("="^60)
println("Testing conversion for model: $TEST_MODEL")
println("="^60)

model_dir = joinpath(TRENDY_DIR, TEST_MODEL)

if !isdir(model_dir)
    @error "Model directory not found: $model_dir"
    exit(1)
end

# Process each simulation type (S0-S3)
for sim in ["S0", "S1", "S2", "S3"]
    sim_dir = joinpath(model_dir, sim)
    
    # Skip if simulation directory doesn't exist
    if !isdir(sim_dir)
        println("\nSkipping $sim (directory not found)")
        continue
    end
    
    println("\n" * "-"^60)
    println("Processing simulation: $sim")
    println("-"^60)
    
    # Create output directory
    output_dir = joinpath(OUTPUT_DIR, TEST_MODEL, sim)
    mkpath(output_dir)
    
    # Get all NetCDF files
    nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
    println("Found $(length(nc_files)) NetCDF files in $sim")
    
    for file in nc_files
        # Extract variable name from filename
        parts = split(basename(file), "_")
        if length(parts) < 3
            println("  ⚠️  Skipping $file (unexpected filename format)")
            push!(skipped_files, joinpath(TEST_MODEL, sim, file))
            continue
        end
        
        var = parts[end][1:end-3]  # Remove .nc extension
        
        # Skip if not an ILAMB variable
        if !(lowercase(var) in lowercase.(ilamb_vars))
            push!(skipped_files, joinpath(TEST_MODEL, sim, file))
            continue
        end
        
        global total_files += 1
        input_file = joinpath(sim_dir, file)
        println("\n  Converting: $file")
        println("  Variable: $var")
        
        try
            # Quick validation
            println("    📖 Validating NetCDF file...")
            try
                NCDataset(input_file) do ds
                    # Check basic structure
                    if !("time" in keys(ds.dim))
                        error("No time dimension found")
                    end
                    println("       ✓ Time dimension found: $(length(ds["time"])) points")
                    
                    # Check for spatial dimensions
                    has_lat = any(x -> x in keys(ds.dim), ["lat", "latitude"])
                    has_lon = any(x -> x in keys(ds.dim), ["lon", "longitude"])
                    println("       ✓ Latitude dimension: $has_lat")
                    println("       ✓ Longitude dimension: $has_lon")
                end
            catch e
                if isa(e, ErrorException) && occursin("NetCDF: HDF error", string(e))
                    error("Corrupted NetCDF file (HDF error)")
                end
                rethrow(e)
            end
            
            println("    📖 Reading input file...")
            dataset = TRENDYDataset(
                input_file,
                TEST_MODEL,
                sim,
                var
            )
            
            println("    🔄 Converting to ILAMB format...")
            ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
            
            # Get output file size
            output_file = ilamb_dataset.path
            file_size = filesize(output_file)
            
            println("    ✓ Created $(basename(output_file)) ($(round(file_size/1024/1024, digits=2)) MB)")
            
            println("    🔍 Verifying conversion...")
            verify_conversion(dataset, ilamb_dataset)
            
            # Analyze the output file
            NCDataset(output_file) do ds
                dims = dimnames(ds)
                vars = keys(ds)
                println("    📊 Output file stats:")
                println("       - Dimensions: $dims")
                println("       - Variables: $vars")
                println("       - Time points: $(length(ds["time"]))")
            end
            
            global converted_files += 1
            successful_vars[var] = get(successful_vars, var, 0) + 1
            println("    ✅ SUCCESS!")
            
        catch e
            error_type = string(typeof(e))
            error_types[error_type] = get(error_types, error_type, 0) + 1
            
            println("    ❌ FAILED!")
            println("    Error: $(typeof(e))")
            println("    Message: $e")
            
            # Provide helpful error context
            if isa(e, ErrorException)
                if occursin("NetCDF: HDF error", string(e))
                    println("    💡 Corrupted NetCDF file")
                elseif occursin("No time dimension", string(e))
                    println("    💡 File lacks required time dimension")
                elseif occursin("time", lowercase(string(e)))
                    println("    💡 Time-related error")
                end
            end
            
            # Print stack trace for debugging
            println("\n    Stack trace:")
            for (i, frame) in enumerate(stacktrace(catch_backtrace())[1:min(5, end)])
                println("      $i. $frame")
            end
            
            push!(failed_files, joinpath(TEST_MODEL, sim, file))
        end
    end
end

# Print summary
println("\n" * "="^60)
println("=== Test Conversion Summary ===")
println("="^60)
println("Model: $TEST_MODEL")
println("Total NetCDF files found: $(total_files + length(skipped_files))")
println("  - ILAMB-relevant files processed: $total_files")
println("  - Non-ILAMB files skipped: $(length(skipped_files))")
println("\nConversion Results:")
println("  ✓ Successfully converted: $converted_files")
println("  ❌ Failed conversions: $(length(failed_files))")

if total_files > 0
    success_rate = round(100 * converted_files / total_files, digits=1)
    println("  📊 Success rate: $success_rate%")
end

println("\nSuccess by ILAMB variable:")
for var in sort(ilamb_vars)
    successes = get(successful_vars, var, 0)
    if successes > 0
        println("  ✓ $var: $successes conversions")
    end
end

if !isempty(error_types)
    println("\nError types encountered:")
    for (error_type, count) in sort(collect(error_types), by=x->x[2], rev=true)
        println("  - $error_type: $count occurrences")
    end
end

if !isempty(failed_files)
    println("\n⚠️  Failed files:")
    for file in failed_files
        println("  - $file")
    end
end

println("\n" * "="^60)
println("Output directory: $OUTPUT_DIR")
println("="^60)
