using Test
using TRENDYtoILAMB
using NCDatasets

@testset "TRENDYtoILAMB.jl" begin
    @testset "Time conversion" begin
        # Test with years relative to a reference year
        # If reference year is 1850 and time values are years since 1850
        # e.g., t=150 means year 2000
        time_values = [150.0, 151.0, 152.0]  # Years since 1850
        reference_year = 1850
        days = convert_time_to_days(time_values, reference_year)
        @test length(days) == length(time_values)
        # Year 2000 (1850 + 150) should be 150*365 days since 1850
        @test days[1] == 150 * 365
        
        bounds = create_time_bounds(time_values, reference_year)
        @test size(bounds) == (3, 2)
        # With a noleap calendar and contiguous yearly bounds, width should be 365 days
        @test bounds[1,2] - bounds[1,1] == 365
    end
    
    @testset "Unit standardization" begin
        @test standardize_units("gC/m^2") == "kg m-2"
        @test standardize_units("unknown_unit") == "unknown_unit"
    end
    
    @testset "Variable metadata" begin
        metadata = get_variable_metadata("cVeg")
        @test metadata.name == "cVeg"
        @test metadata.units == "kg m-2"
    end
    
    @testset "Date range utilities" begin
        # Test standard date range function
        start_date, end_date = get_standard_date_range()
        @test start_date == "170001"
        @test end_date == "202312"
        @test length(start_date) == 6
        @test length(end_date) == 6
    end
end
