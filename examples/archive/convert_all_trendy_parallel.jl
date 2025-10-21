#=
Convert TRENDY NetCDF files to ILAMB format (PARALLEL VERSION)

This script uses multi-threading to process multiple files simultaneously,
dramatically reducing total conversion time.

Performance:
- Sequential: ~6 files/hour (1 core)
- Parallel (96 threads): ~200-300 files/hour (expected)
- Speedup: 30-50x faster

Usage:
    julia -t auto --project=. examples/convert_all_trendy_parallel.jl
    
    Or specify thread count:
    julia -t 48 --project=. examples/convert_all_trendy_parallel.jl
=#

using TRENDYtoILAMB
using NCDatasets
using Printf
using Base.Threads

"""
Thread-safe statistics tracker for parallel conversion
"""
mutable struct ConversionStats
    total_files::Int
    converted_files::Int
    failed_files::Vector{String}
    skipped_files::Vector{String}
    successful_vars::Dict{String,Int}
    error_types::Dict{String,Int}
    lock::ReentrantLock
    
    ConversionStats() = new(0, 0, String[], String[], Dict{String,Int}(), Dict{String,Int}(), ReentrantLock())
end

function increment_total!(stats::ConversionStats)
    Base.lock(stats.lock) do
        stats.total_files += 1
    end
end

function increment_converted!(stats::ConversionStats, var::String)
    Base.lock(stats.lock) do
        stats.converted_files += 1
        stats.successful_vars[var] = get(stats.successful_vars, var, 0) + 1
    end
end

function add_failed!(stats::ConversionStats, file::String, error_type::String)
    Base.lock(stats.lock) do
        push!(stats.failed_files, file)
        stats.error_types[error_type] = get(stats.error_types, error_type, 0) + 1
    end
end

function add_skipped!(stats::ConversionStats, file::String)
    Base.lock(stats.lock) do
        push!(stats.skipped_files, file)
    end
end

"""
Convert a single file (thread-safe)
"""
function convert_single_file(input_file::String, model::String, sim::String, 
                             var::String, output_dir::String, stats::ConversionStats)
    thread_id = Threads.threadid()
    file_name = basename(input_file)
    
    try
        # Quick validation
        NCDataset(input_file) do ds
            if !("time" in keys(ds.dim))
                error("No time dimension found")
            end
        end
        
        # Convert
        dataset = TRENDYDataset(input_file, model, sim, var)
        ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
        
        # Verify
        verify_conversion(dataset, ilamb_dataset)
        
        # Get file size
        file_size = filesize(ilamb_dataset.path)
        
        # Update stats
        increment_converted!(stats, var)
        
        # Thread-safe logging
        Base.lock(stats.lock) do
            println("[Thread $thread_id] ✓ $model/$sim/$file_name → $(basename(ilamb_dataset.path)) ($(round(file_size/1024/1024, digits=2)) MB)")
        end
        
        return true
        
    catch e
        error_type = string(typeof(e))
        add_failed!(stats, joinpath(model, sim, file_name), error_type)
        
        # Thread-safe error logging
        Base.lock(stats.lock) do
            println("[Thread $thread_id] ❌ $model/$sim/$file_name: $(typeof(e))")
            if isa(e, ErrorException)
                if occursin("NetCDF: HDF error", string(e))
                    println("       💡 Corrupted NetCDF file")
                elseif occursin("No time dimension", string(e))
                    println("       💡 Missing time dimension")
                end
            end
        end
        
        return false
    end
end

"""
Convert all TRENDY files using parallel processing
"""
function convert_all_trendy_files_parallel(trendy_dir::String; output_base::String="output")
    # ILAMB variables
    ilamb_vars = [
        "gpp", "nbp", "npp", "ra", "rh", "lai", 
        "mrro", "mrros", "mrso", "evapotrans",
        "cSoil", "cVeg", "cLitter", "cProduct",
        "burntArea", "fFire",
        "tas", "pr", "rsds",
    ]
    
    # Initialize stats
    stats = ConversionStats()
    
    # Collect all files to process
    all_tasks = []
    
    models = filter(x -> isdir(joinpath(trendy_dir, x)) && !startswith(x, "."), readdir(trendy_dir))
    
    println("="^80)
    println("🚀 PARALLEL TRENDY TO ILAMB CONVERSION")
    println("="^80)
    println("Threads available: $(Threads.nthreads())")
    println("Models to process: $(length(models))")
    println("Target variables: $(length(ilamb_vars))")
    println("="^80)
    println()
    
    for model in models
        model_dir = joinpath(trendy_dir, model)
        
        for sim in ["S0", "S1", "S2", "S3"]
            sim_dir = joinpath(model_dir, sim)
            !isdir(sim_dir) && continue
            
            # Create output directory
            output_dir = joinpath(output_base, model)
            mkpath(output_dir)
            
            # Find all relevant NetCDF files
            nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
            
            for file in nc_files
                parts = split(basename(file), "_")
                if length(parts) < 3
                    add_skipped!(stats, joinpath(model, sim, file))
                    continue
                end
                
                var = parts[end][1:end-3]  # Remove .nc
                
                if !(lowercase(var) in lowercase.(ilamb_vars))
                    add_skipped!(stats, joinpath(model, sim, file))
                    continue
                end
                
                increment_total!(stats)
                
                # Add to task list
                input_file = joinpath(sim_dir, file)
                push!(all_tasks, (input_file, model, sim, var, output_dir))
            end
        end
    end
    
    println("📊 Files to convert: $(stats.total_files)")
    println("📊 Files to skip: $(length(stats.skipped_files))")
    println()
    println("⏱️  Starting parallel conversion...")
    println()
    
    start_time = time()
    
    # Process files in parallel
    Threads.@threads for task in all_tasks
        input_file, model, sim, var, output_dir = task
        convert_single_file(input_file, model, sim, var, output_dir, stats)
        
        # Periodic progress update (thread-safe)
        if stats.converted_files % 10 == 0
            Base.lock(stats.lock) do
                elapsed = time() - start_time
                rate = stats.converted_files / (elapsed / 3600)
                remaining = stats.total_files - stats.converted_files - length(stats.failed_files)
                eta_hours = remaining / rate
                println()
                println("📈 Progress: $(stats.converted_files)/$(stats.total_files) files ($(round(100*stats.converted_files/stats.total_files, digits=1))%)")
                println("   Rate: $(round(rate, digits=1)) files/hour")
                println("   ETA: $(round(eta_hours, digits=1)) hours")
                println()
            end
        end
        
        # Garbage collection every 50 files (less aggressive than sequential version)
        if stats.converted_files % 50 == 0
            GC.gc()
        end
    end
    
    elapsed_time = time() - start_time
    
    # Print summary
    println()
    println("="^80)
    println("=== CONVERSION SUMMARY ===")
    println("="^80)
    println("⏱️  Total time: $(round(elapsed_time/60, digits=1)) minutes ($(round(elapsed_time/3600, digits=2)) hours)")
    println("🧵 Threads used: $(Threads.nthreads())")
    println()
    println("📊 Files processed: $(stats.total_files)")
    println("   ✓ Successfully converted: $(stats.converted_files)")
    println("   ❌ Failed conversions: $(length(stats.failed_files))")
    println("   ⏭️  Skipped (non-ILAMB): $(length(stats.skipped_files))")
    
    if stats.converted_files > 0
        success_rate = round(100 * stats.converted_files / stats.total_files, digits=1)
        avg_rate = round(stats.converted_files / (elapsed_time / 3600), digits=1)
        println()
        println("📈 Success rate: $success_rate%")
        println("⚡ Average speed: $avg_rate files/hour")
        
        # Calculate speedup vs sequential
        sequential_rate = 6.0  # files/hour from your current run
        speedup = avg_rate / sequential_rate
        println("🚀 Speedup vs sequential: $(round(speedup, digits=1))x faster")
    end
    
    println()
    println("Success by ILAMB variable:")
    for var in sort(ilamb_vars)
        successes = get(stats.successful_vars, var, 0)
        if successes > 0
            println("   ✓ $var: $successes conversions")
        end
    end
    
    if !isempty(stats.error_types)
        println()
        println("Error types encountered:")
        for (error_type, count) in sort(collect(stats.error_types), by=x->x[2], rev=true)
            println("   - $error_type: $count occurrences")
        end
    end
    
    if !isempty(stats.failed_files) && length(stats.failed_files) <= 20
        println()
        println("⚠️  Failed files:")
        for file in stats.failed_files
            println("   - $file")
        end
    elseif length(stats.failed_files) > 20
        println()
        println("⚠️  Failed files (showing first 20 of $(length(stats.failed_files))):")
        for file in stats.failed_files[1:20]
            println("   - $file")
        end
    end
    
    println()
    println("="^80)
    println("📁 Output directory: $output_base")
    println("="^80)
end

# Main execution
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"

@info "Starting parallel conversion with $(Threads.nthreads()) threads..."
convert_all_trendy_files_parallel(TRENDY_DIR, output_base=OUTPUT_DIR)
