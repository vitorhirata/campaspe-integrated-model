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
            :farm_option => "",
            # Policy parameters
            :policy_path => "data/policy",
            :goulburn_alloc => "high",
            :restriction_type => "default",
            :max_carryover_perc => 0.25,
            :carryover_period => 1,
            :dam_extractions_path => "",
            :policy_option => "",
            # Surface water parameters
            :sw_climate_path => "data/climate/sw_climate.csv",
            :sw_network_path => "data/surface_water/two_node_network.yml",
        ))[1,:]

        # Run model and capture results
        farm_results, dam_level_ts, recreation_index, env_orders = CampaspeIntegratedModel.run_model(scenario)

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

        @test length(env_orders) > 0
        @test all(env_orders[1:end] .>= 0.0)
    end
end

@testset "run_scenarios functionality" begin
    # Create a simple scenarios DataFrame with 3 scenarios
    scenarios = DataFrame(
        :start_day => ["1981-01-10", "1981-01-10", "1981-01-10"],
        :end_day => ["1982-01-20", "1982-01-20", "1982-01-20"],
        # Farm parameters
        :farm_climate_path => fill("data/climate/farm_climate.csv", 3),
        :farm_path => fill("data/farm/basin", 3),
        :farm_step => fill(14, 3),
        :farm_option => ["", "improve_irrigation_efficiency", ""],
        # Policy parameters
        :policy_path => fill("data/policy", 3),
        :goulburn_alloc => fill("high", 3),
        :restriction_type => fill("default", 3),
        :max_carryover_perc => fill(0.25, 3),
        :carryover_period => fill(1, 3),
        :dam_extractions_path => fill("", 3),
        :policy_option => ["", "", "increase_environmental_water"],
        # Surface water parameters
        :sw_climate_path => fill("data/climate/sw_climate.csv", 3),
        :sw_network_path => fill("data/surface_water/two_node_network.yml", 3),
    )

    # Run scenarios without saving
    results = CampaspeIntegratedModel.run_scenarios(scenarios, false)

    # Test that results vector has correct length
    @test length(results) == 3

    # Test that each result has the expected fields
    for (i, result) in enumerate(results)
        @test result.scenario_id == i
        @test haskey(result, :farm_option)
        @test haskey(result, :policy_option)
        @test haskey(result, :farm_results)
        @test haskey(result, :dam_level)
        @test haskey(result, :recreational_index)
        @test haskey(result, :env_orders)
        @test nrow(result.farm_results) > 0
        @test length(result.dam_level) > 0
        @test all(result.dam_level .>= 0.0)
        @test all(result.dam_level .<= 204.0)
        @test length(result.recreational_index) > 0
        @test all(result.recreational_index .>= 0.0)
        @test all(result.recreational_index .<= 1.0)
        @test length(result.env_orders) > 0
        @test all(result.env_orders .>= 0.0)
    end
    @test results[1].farm_option == ""
    @test results[1].policy_option == ""
    @test results[2].farm_option == "improve_irrigation_efficiency"
    @test results[2].policy_option == ""
    @test results[3].farm_option == ""
    @test results[3].policy_option == "increase_environmental_water"
end
