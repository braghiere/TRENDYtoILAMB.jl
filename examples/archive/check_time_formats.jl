using NCDatasets
using Printf

function check_time_format(filepath)
    try
        ds = Dataset(filepath)
        if haskey(ds, "time")
            time_var = ds["time"]
            units = get(time_var.attrib, "units", "no units")
            calendar = get(time_var.attrib, "calendar", "no calendar")
            first_value = time_var[1]
            last_value = time_var[end]
            @printf("%-50s | %-40s | %-15s | First: %-10g | Last: %-10g\n", 
                    basename(filepath), units, calendar, first_value, last_value)
        end
        close(ds)
    catch e
        @warn "Error reading $filepath: $e"
    end
end

# Walk through the data directory and check all .nc files
function check_all_files(root_dir)
    println("\n=== Time Format Analysis for TRENDY Files ===")
    println("File" * " "^46 * "| Units" * " "^35 * "| Calendar" * " "^8 * "| Time Range")
    println("-"^120)
    
    for (root, _, files) in walkdir(root_dir)
        for file in files
            if endswith(file, ".nc")
                filepath = joinpath(root, file)
                check_time_format(filepath)
            end
        end
    end
end

# Assuming data is in /home/renatob/data/trendy
check_all_files("/home/renatob/data/trendy")