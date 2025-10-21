#=
Safe full model conversion test with memory monitoring

This script:
1. Converts all variables for a SINGLE model
2. Monitors memory usage
3. Forces garbage collection between files
4. Validates all fixes work with real data
=#

using TRENDYtoILAMB
using NCDatasets
using Printf

# Configuration
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready_test"
const TEST_MODEL = "CARDAMOM"  # Start with CARDAMOM to test month index handling

# ILAMB variables to test
const TEST_VARS = [
    "gpp", "nbp", "npp", "ra", "rh", "lai",
    "cSoil", "cVeg", "cLitter"
]

function get_memory_usage()
    """Get current process memory usage in GB"""
    try
        pid = getpid()
        # Read from /proc/[pid]/status
        status = read("/proc/$pid/status", String)
        for line in split(status, '\n')
            if startswith(line, "VmRSS:")
                # Extract memory in kB and convert to GB
                mem_kb = parse(Int, split(line)[2])
                return mem_kb / 1024 / 1024  # Convert to GB
            end
        end
    catch
        return -1.0
    end
    return -1.0
end

function test_model_conversion(model::String)
    println("\n" * "="^70)
    println("Testing Full Model Conversion: $model")
    println("="^70)
    
    model_dir = joinpath(TRENDY_DIR, model)
    if !isdir(model_dir)
        println("❌ Model directory not found: $model_dir")
        return
    end
    
    # Create output directory
    output_dir = joinpath(OUTPUT_DIR, model)
    mkpath(output_dir)
    
    # Track statistics
    total_files = 0
    successful = 0
    failed = 0
    failed_files = String[]
    
    initial_memory = get_memory_usage()
    println("\n📊 Initial memory usage: $(round(initial_memory, digits=2)) GB")
    
    # Process each simulation
    for sim in ["S0", "S1", "S2", "S3"]
        sim_dir = joinpath(model_dir, sim)
        !isdir(sim_dir) && continue
        
        println("\n--- Processing $model/$sim ---")
        
        # Find files for test variables
        for var in TEST_VARS
            # Look for file matching this variable
            files = filter(x -> occursin(var, lowercase(x)) && endswith(x, ".nc"), 
                          readdir(sim_dir))
            
            if isempty(files)
                continue
            end
            
            input_file = joinpath(sim_dir, files[1])
            total_files += 1
            
            print("  $(basename(input_file))... ")
            flush(stdout)
            
            try
                # Track memory before conversion
                mem_before = get_memory_usage()
                
                # Convert
                dataset = TRENDYDataset(input_file, model, sim, var)
                ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
                
                # Track memory after conversion
                mem_after = get_memory_usage()
                mem_delta = mem_after - mem_before
                
                # Get output file size
                file_size_mb = filesize(ilamb_dataset.path) / 1024 / 1024
                
                println("✅ ($(round(file_size_mb, digits=1)) MB, Δmem: $(round(mem_delta, digits=2)) GB)")
                
                # Verify the output file can be read
                NCDataset(ilamb_dataset.path) do ds
                    @assert haskey(ds, "time") "Missing time dimension"
                    @assert haskey(ds, var) "Missing variable $var"
                    @assert haskey(ds, "time_bounds") "Missing time_bounds"
                end
                
                successful += 1
                
                # Force garbage collection to free memory
                GC.gc()
                
            catch e
                println("❌ Error: $(typeof(e))")
                if isa(e, ErrorException) && occursin("NetCDF", string(e))
                    println("       Likely corrupted file")
                else
                    println("       $e")
                end
                failed += 1
                push!(failed_files, basename(input_file))
            end
            
            # Check memory periodically
            current_mem = get_memory_usage()
            if current_mem > initial_memory + 10  # If memory grew by 10GB
                println("\n⚠️  Memory increased significantly: $(round(current_mem, digits=2)) GB")
                println("    Running aggressive garbage collection...")
                GC.gc(true)  # Full GC
                sleep(1)
                new_mem = get_memory_usage()
                println("    After GC: $(round(new_mem, digits=2)) GB")
            end
        end
    end
    
    # Final statistics
    final_memory = get_memory_usage()
    memory_increase = final_memory - initial_memory
    
    println("\n" * "="^70)
    println("Conversion Summary for $model")
    println("="^70)
    println("Total files processed: $total_files")
    println("  ✅ Successful: $successful")
    println("  ❌ Failed: $failed")
    
    if successful > 0
        success_rate = round(100 * successful / total_files, digits=1)
        println("  📊 Success rate: $success_rate%")
    end
    
    println("\n💾 Memory Usage:")
    println("  Initial: $(round(initial_memory, digits=2)) GB")
    println("  Final: $(round(final_memory, digits=2)) GB")
    println("  Increase: $(round(memory_increase, digits=2)) GB")
    
    if !isempty(failed_files)
        println("\n⚠️  Failed files:")
        for file in failed_files
            println("  - $file")
        end
    end
    
    # List output files
    println("\n📁 Output Files:")
    output_files = filter(x -> endswith(x, ".nc"), readdir(output_dir))
    for (i, file) in enumerate(output_files)
        if i <= 5
            println("  - $file")
        elseif i == 6
            println("  ... and $(length(output_files) - 5) more")
            break
        end
    end
    
    println("\n✅ Test complete!")
    println("="^70)
end

# Run the test
println("🧪 Starting Safe Full Model Conversion Test")
println("Model: $TEST_MODEL")
println("Variables: $(join(TEST_VARS, ", "))")
println("\nThis test will:")
println("  1. Convert all variables for $TEST_MODEL")
println("  2. Monitor memory usage")
println("  3. Force garbage collection between files")
println("  4. Validate all outputs")

test_model_conversion(TEST_MODEL)
