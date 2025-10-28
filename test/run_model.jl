using Test
using CampaspeIntegratedModel
using DataFrames
using CSV

@testset "run_model basic functionality" begin
    @testset "run_model executes without errors and returns valid results" begin
        scenario = DataFrame(Dict(
            :farm_climate_path => "data/climate/farm_climate.csv",
            :farm_path => "data/farm/basin",
            :start_day => "1981-01-10",
            :end_day => "1982-01-20",
            :farm_step => 14,
            # Policy
            :policy_path => "data/policy",
            :goulburn_alloc => "high",
            :restriction_type => "default",
            :max_carryover_perc => 0.25,
            :carryover_period => 1,
            :dam_extractions_path => "",
            # Surface water
            :sw_climate_path => "data/climate/sw_climate.csv",
            :sw_network_path => "data/surface_water/two_node_network.yml",
        ))[1,:]

        # Run model and capture results
        farm_results, dam_level_ts = CampaspeIntegratedModel.run_model(scenario)

        # Test dam level time series
        @test !isempty(dam_level_ts)
        @test length(dam_level_ts) > 0

        # Dam levels should be non-negative for days that were runned: one year + 19 days
        @test all(dam_level_ts[1:end] .>= 0.0)

        # Dam levels should have realistic values (between 0 and max capacity)
        @test all(dam_level_ts[1:end] .<= 400_000.0)

        # Test farm results structure
        @test farm_results isa Dict

        # Should contain zone results (check if keys exist)
        @test !isempty(farm_results)

        # Each zone should have results
        for (zone_name, zone_data) in farm_results
            @test !isempty(zone_data)
        end
    end
end
