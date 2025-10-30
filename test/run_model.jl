using Test
using CampaspeIntegratedModel
using DataFrames
using CSV

@testset "run_model basic functionality" begin
    @testset "run_model executes without errors and returns valid results" begin
        scenario = DataFrame(Dict(
            :start_day => "1981-01-10",
            :end_day => "1982-01-20",
            # Farm parameters
            :farm_climate_path => "data/climate/farm_climate.csv",
            :farm_path => "data/farm/basin",
            :farm_step => 14,
            # Policy parameters
            :policy_path => "data/policy",
            :goulburn_alloc => "high",
            :restriction_type => "default",
            :max_carryover_perc => 0.25,
            :carryover_period => 1,
            :dam_extractions_path => "",
            # Surface water parameters
            :sw_climate_path => "data/climate/sw_climate.csv",
            :sw_network_path => "data/surface_water/two_node_network.yml",
        ))[1,:]

        # Run model and capture results
        farm_results, dam_level_ts, recreation_index = CampaspeIntegratedModel.run_model(scenario)

        col_names = ["zone_id", "Date", "income_sum", "irrigated_volume_sum", "irrigated_yield_sum", "dryland_yield_sum",
            "growing_season_rainfall_sum", "irrigated_area_sum", "dryland_area_sum", "Dollar per ML",
            "ML per Irrigated Yield", "Dollar per Ha", "Mean Irrigated Yield", "Mean Dryland Yield",
            "surface_water_sum", "groundwater_sum"
        ]
        @test names(farm_results) == col_names
        @test size(farm_results)[1] > 0

        @test length(dam_level_ts) > 0
        @test all(dam_level_ts[1:end] .>= 0.0)
        @test all(dam_level_ts[1:end] .<= 204.0)

        @test length(recreation_index) > 0
        @test all(recreation_index[1:end] .>= 0.0)
        @test all(recreation_index[1:end] .<= 1.0)
    end
end
