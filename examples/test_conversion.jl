#=
Test conversion on a few models first before running on all data
This helps identify issues quickly without processing all ~900+ files
=#

using TRENDYtoILAMB
using NCDatasets
using Printf

"""
Test conversion on a subset of models and variables
"""
function test_conversion(trendy_dir::String; output_base::String="test_output", max_models::Int=3)
    # List of variables to test
    test_vars = [
        "gpp", "nbp", "npp", "ra", "rh", "lai",
        "cSoil", "cVeg", "tas", "pr", "rsds"
    ]
    
    # Get available models
    all_models = filter(x -> isdir(joinpath(trendy_dir, x)) && !startswith(x, "."), readdir(trendy_dir))
    
    # Test on a subset of models
    test_models = all_models[1:min(max_models, length(all_models))]
    
    println("="^60)
    println("=== Testing Conversion ===")
    println("="^60)
    println("Testing models: $(join(test_models, ", "))")
    println("Testing variables: $(join(test_vars, ", "))")
    println("="^60)
    println()
    
    # Statistics
    total_files = 0
    converted_files = 0
    failed_files = String[]
    successful_vars = Dict{String,Int}()
    
    for model in test_models
        println("\n📦 Testing model: $model")
        model_dir = joinpath(trendy_dir, model)
        
        # Test S3 simulation only
        sim = "S3"
        sim_dir = joinpath(model_dir, sim)
        
        !isdir(sim_dir) && (println("  ⚠️  S3 directory not found, skipping"); continue)
        
        # Create output directory for this model (no simulation subdirectory)
        output_dir = joinpath(output_base, model)
        mkpath(output_dir)
        
        # Get NetCDF files
        nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
        
        for file in nc_files
            # Extract variable name
            parts = split(basename(file), "_")
            length(parts) < 3 && continue
            
            var = parts[end][1:end-3]  # Remove .nc extension
            
            # Skip if not a test variable
            !(lowercase(var) in lowercase.(test_vars)) && continue
            
            total_files += 1
            input_file = joinpath(sim_dir, file)
            println("  📄 Converting $file...")
            
            try
                # Read and convert
                dataset = TRENDYDataset(input_file, model, sim, var)
                ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
                
                # Verify
                verify_conversion(dataset, ilamb_dataset)
                
                # Get stats
                output_file = ilamb_dataset.path
                file_size = filesize(output_file)
                
                NCDataset(output_file) do ds
                    time_points = length(ds["time"])
                    println("    ✓ Success: $(basename(output_file)) ($(round(file_size/1024/1024, digits=2)) MB, $time_points time points)")
                end
                
                converted_files += 1
                successful_vars[var] = get(successful_vars, var, 0) + 1
                
            catch e
                println("    ❌ Failed: $(typeof(e))")
                println("       $e")
                push!(failed_files, joinpath(model, sim, file))
            end
        end
    end
    
    # Print summary
    println("\n" * "="^60)
    println("=== Test Summary ===")
    println("="^60)
    println("Models tested: $(length(test_models))")
    println("Total files processed: $total_files")
    println("  ✓ Successfully converted: $converted_files")
    println("  ❌ Failed conversions: $(length(failed_files))")
    
    if total_files > 0
        success_rate = round(100 * converted_files / total_files, digits=1)
        println("  📊 Success rate: $success_rate%")
    end
    
    println("\nSuccess by variable:")
    for var in sort(collect(keys(successful_vars)))
        println("  ✓ $var: $(successful_vars[var]) conversions")
    end
    
    if !isempty(failed_files)
        println("\n⚠️  Failed files:")
        for file in failed_files
            println("  - $file")
        end
    end
    
    println("\n" * "="^60)
    println("Output directory: $output_base")
    println("="^60)
    
    return (total=total_files, converted=converted_files, failed=length(failed_files))
end

# Run test on first 3 models
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const TEST_OUTPUT_DIR = "/home/renatob/data/ilamb_ready_test"

@info "Running test conversion on subset of data..."
results = test_conversion(TRENDY_DIR, output_base=TEST_OUTPUT_DIR, max_models=3)

println("\n✅ Test complete!")
if results.failed == 0
    println("🎉 All test conversions successful! Ready to run on full dataset.")
else
    println("⚠️  Some conversions failed. Review errors before running on full dataset.")
end
