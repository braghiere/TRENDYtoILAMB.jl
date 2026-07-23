#!/usr/bin/env julia
# Targeted reconversion of files affected by Bug #6 (mixed-case variables)

using TRENDYtoILAMB

# Models and variables that need reconversion
reconvert_list = [
    # Biomass (cVeg)
    ("ELM", "cVeg"),
    ("ISBA-CTRIP", "cVeg"),
    ("VISIT", "cVeg"),
    ("CLM5.0", "cVeg"),
    ("ED", "cVeg"),
    ("JULES", "cVeg"),
    ("LPJwsl", "cVeg"),
    ("CARDAMOM", "cVeg"),
    # Burned Area (burntArea)
    ("ELM", "burntArea"),
    ("ISBA-CTRIP", "burntArea"),
    ("VISIT", "burntArea"),
    ("CLM5.0", "burntArea"),
    ("ED", "burntArea"),
    ("JULES", "burntArea"),
    ("LPJwsl", "burntArea"),
]

# Base paths
trendy_dir = "/home/renatob/data/TRENDYv13"
output_base = "/home/renatob/data/ilamb_test_output_full"
sim = "S3"

# Model name mappings for source files
model_prefixes = Dict(
    "ELM" => "E3SM",
    "CLM5.0" => "CLM6.0",
    "ED" => "EDv3",
    "ISBA-CTRIP" => "ISBA-CTRIP",
    "VISIT" => "VISIT",
    "JULES" => "JULES",
    "LPJwsl" => "LPJwsl",
    "CARDAMOM" => "CARDAMOM"
)

println("=" ^ 80)
println("Targeted Reconversion: Bug #6 Fix (Mixed-Case Variables)")
println("=" ^ 80)
println()

total = length(reconvert_list)
success_count = 0
failed_count = 0

for (i, (model, var)) in enumerate(reconvert_list)
    global success_count, failed_count
    println("[$i/$total] Converting $model - $var")
    
    # Construct input file path
    prefix = model_prefixes[model]
    input_file = joinpath(trendy_dir, model, sim, "$(prefix)_$(sim)_$(var).nc")
    
    if !isfile(input_file)
        println("  ⚠️  Source file not found: $input_file")
        failed_count += 1
        continue
    end
    
    # Create output directory
    output_dir = joinpath(output_base, model)
    mkpath(output_dir)
    
    try
        # Create dataset with ORIGINAL variable name (not lowercased)
        dataset = TRENDYDataset(input_file, model, sim, var)
        
        # Convert to ILAMB format
        ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
        
        # Check file size
        file_size = filesize(ilamb_dataset.path)
        if file_size < 1000
            println("  ❌ Output file suspiciously small: $(file_size) bytes")
            failed_count += 1
        else
            println("  ✓ Success: $(basename(ilamb_dataset.path))")
            println("    File size: $(round(file_size/1024/1024, digits=2)) MB")
            success_count += 1
        end
    catch e
        println("  ❌ Error: $e")
        failed_count += 1
    end
    println()
end

println("=" ^ 80)
println("Reconversion Summary")
println("=" ^ 80)
println("  Total files:  $total")
println("  Successful:   $success_count")
println("  Failed:       $failed_count")
println("  Success rate: $(round(100 * success_count / total, digits=1))%")
println()
