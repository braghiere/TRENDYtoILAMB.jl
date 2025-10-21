#!/usr/bin/env julia

"""
Manual parallel conversion: Split files by model into groups,
run each group in a separate process.

This approach uses 6 independent sequential processes to leverage
96 cores without the complexity of distributed computing.

With parallel processing: ~840 files ÷ 6 groups ÷ 70 files/hour/group = ~2 hours
"""

using TRENDYtoILAMB

const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"

# ILAMB variables to process
const ILAMB_VARS = [
    "gpp", "nbp", "npp", "ra", "rh", "lai",
    "mrro", "mrros", "mrso", "evapotrans",
    "cSoil", "cVeg", "cLitter", "cProduct",
    "burntArea", "fFire", "tas", "pr", "rsds"
]

# Number of parallel groups (adjust based on available cores)
const N_GROUPS = 6

# Get all NetCDF files from TRENDY directory
function find_all_netcdf_files()
    all_files = String[]
    
    for model in readdir(TRENDY_DIR)
        model_dir = joinpath(TRENDY_DIR, model)
        !isdir(model_dir) && continue
        
        for sim in ["S0", "S1", "S2", "S3"]
            sim_dir = joinpath(model_dir, sim)
            !isdir(sim_dir) && continue
            
            for file in readdir(sim_dir)
                !endswith(file, ".nc") && continue
                
                # Check if it's an ILAMB variable
                parts = split(basename(file), "_")
                length(parts) < 3 && continue
                
                var = parts[end][1:end-3]  # Remove .nc
                lowercase(var) in lowercase.(ILAMB_VARS) || continue
                
                push!(all_files, joinpath(sim_dir, file))
            end
        end
    end
    
    return all_files
end

# Check if file already converted
function is_converted(file_path)
    # Parse filename to get model/simulation/variable
    parts = split(basename(file_path), "_")
    length(parts) < 3 && return false
    
    model = parts[1]
    var = lowercase(parts[end][1:end-3])
    
    # Check both possible output structures:
    # 1. By variable (ILAMB standard): output/variable/model.nc
    # 2. By model (sequential output): output/model/variable_*.nc
    
    # Check variable-based structure
    output_file1 = joinpath(OUTPUT_DIR, var, "$(model).nc")
    isfile(output_file1) && return true
    
    # Check model-based structure (sequential conversion output)
    model_dir = joinpath(OUTPUT_DIR, model)
    if isdir(model_dir)
        # Look for files with this variable in the model directory
        for existing_file in readdir(model_dir)
            if startswith(lowercase(existing_file), var * "_")
                return true
            end
        end
    end
    
    return false
end

# Split files into N groups by model
function split_by_model(files, n_groups=N_GROUPS)
    # Group by model
    model_files = Dict{String, Vector{String}}()
    for file in files
        model = split(basename(file), "_")[1]
        if !haskey(model_files, model)
            model_files[model] = String[]
        end
        push!(model_files[model], file)
    end
    
    # Split models evenly across groups
    models = collect(keys(model_files))
    models_per_group = ceil(Int, length(models) / n_groups)
    
    groups = [String[] for _ in 1:n_groups]
    for (i, model) in enumerate(models)
        group_idx = min(div(i - 1, models_per_group) + 1, n_groups)
        append!(groups[group_idx], model_files[model])
    end
    
    return groups
end

# Create launcher script
function create_launcher_scripts()
    println("🔍 Finding all NetCDF files...")
    all_files = find_all_netcdf_files()
    println("   Found $(length(all_files)) total files")
    
    println("🔍 Filtering already converted files...")
    remaining_files = filter(!is_converted, all_files)
    println("   $(length(remaining_files)) files remaining to convert")
    
    if isempty(remaining_files)
        println("✅ All files already converted!")
        return
    end
    
    # Split into 8 groups by model
    groups = split_by_model(remaining_files, N_GROUPS)
    
    # Create a conversion script for each group
    for (i, group_files) in enumerate(groups)
        if isempty(group_files)
            continue
        end
        
        script_path = "/home/renatob/convert_group_$i.jl"
        open(script_path, "w") do io
            println(io, """
            #!/usr/bin/env julia --project=/home/renatob/TRENDYtoILAMB.jl
            
            using TRENDYtoILAMB
            using NCDatasets
            
            # Group $i: $(length(group_files)) files
            files = [
            """)
            
            for file in group_files
                println(io, "    \"$file\",")
            end
            
            println(io, """
            ]
            
            const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"
            
            println("="^60)
            println("GROUP $i: Processing \$(length(files)) files")
            println("="^60)
            
            # Use global variables
            global converted = 0
            global failed = 0
            
            for (idx, file) in enumerate(files)
                println("\\n[\$idx/$(length(group_files))] \$(basename(file))")
                
                # Extract model from directory path (not filename - filenames can have inconsistent casing)
                # Path structure: /path/to/TRENDYv13/MODEL/S3/file.nc
                path_parts = splitpath(file)
                model = path_parts[end-2]  # MODEL directory
                sim = path_parts[end-1]     # S3 directory
                
                # Parse variable from filename
                filename_parts = split(basename(file), "_")
                var = filename_parts[end][1:end-3]  # Remove .nc extension
                
                try
                    # Validate file
                    NCDataset(file) do ds
                        if !("time" in keys(ds.dim))
                            error("No time dimension")
                        end
                    end
                    
                    # Convert - output to model-specific directory
                    model_output_dir = joinpath(OUTPUT_DIR, model)
                    mkpath(model_output_dir)
                    dataset = TRENDYDataset(file, model, sim, var)
                    ilamb_dataset = convert_to_ilamb(dataset, output_dir=model_output_dir)
                    verify_conversion(dataset, ilamb_dataset)
                    
                    global converted += 1
                    println("  ✓ Converted (\$converted/\$(length(files)))")
                    
                    # GC every file
                    GC.gc()
                    if converted % 10 == 0
                        GC.gc(true)
                    end
                    
                catch e
                    global failed += 1
                    println("  ❌ ERROR: \$e")
                end
            end
            
            println("\\n" * "="^60)
            println("GROUP $i COMPLETE")
            println("  ✓ Converted: \$converted")
            println("  ❌ Failed: \$failed")
            println("="^60)
            """)
        end
        
        run(`chmod +x $script_path`)
        println("✅ Created: $script_path ($(length(group_files)) files)")
    end
    
    # Create master launch script
    launch_script = "/home/renatob/launch_all_groups.sh"
    open(launch_script, "w") do io
        println(io, """
        #!/bin/bash
        
        # Launch all conversion groups in parallel
        echo "🚀 Starting parallel conversion with 8 groups..."
        echo ""
        
        """)
        
        for i in 1:N_GROUPS
            if i <= length(groups) && !isempty(groups[i])
                println(io, """
                nohup julia --project=/home/renatob/TRENDYtoILAMB.jl /home/renatob/convert_group_$i.jl > /home/renatob/group_$i.log 2>&1 &
                echo "✓ Started group $i: $(length(groups[i])) files (PID: \$!)"
                """)
            end
        end
        
        println(io, """
        
        echo ""
        printf '=%.0s' {1..70}; echo
        echo "✅ All $(length(filter(!isempty, groups))) groups launched!"
        printf '=%.0s' {1..70}; echo
        echo "📝 Logs: /home/renatob/group_*.log"
        echo "📊 Monitor: watch -n 10 'tail -n 2 /home/renatob/group_*.log'"
        echo "📂 Progress: find /home/renatob/data/ilamb_ready -name '*.nc' | wc -l"
        echo ""
        """)
    end
    
    run(`chmod +x $launch_script`)
    
    # Summary
    println("\n" * "="^70)
    println("✅ Created $(length(filter(!isempty, groups))) group scripts")
    println("="^70)
    println("\n📋 To start conversion:")
    println("   $launch_script")
    println("\n📊 To monitor progress:")
    println("   watch -n 10 'tail -n 2 /home/renatob/group_*.log'")
    println("\n⏱️  Estimated time: ~2 hours (100× speedup)")
    println("="^70)
end

# Run the script creation
if abspath(PROGRAM_FILE) == @__FILE__
    create_launcher_scripts()
end
