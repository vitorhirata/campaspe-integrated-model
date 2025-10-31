@testset "sample_individual_options functionality" begin
    start_day = "1981-01-10"
    end_day = "1982-01-20"
    climate_type = "historic"

    scenarios = CampaspeIntegratedModel.sample_individual_options(start_day, end_day, climate_type)
    required_cols = [:start_day, :end_day, :farm_climate_path, :farm_path, :farm_step,
                     :policy_path, :goulburn_alloc, :restriction_type, :max_carryover_perc,
                     :carryover_period, :dam_extractions_path, :sw_climate_path,
                     :sw_network_path, :farm_option, :policy_option]

    @test nrow(scenarios) == 13
    for col in required_cols
        @test hasproperty(scenarios, col)
    end
    @test all(scenarios.start_day .== start_day)
    @test all(scenarios.end_day .== end_day)
    @test all(scenarios.farm_climate_path .== "data/climate/historic/farm_climate.csv")
    @test all(scenarios.sw_climate_path .== "data/climate/historic/sw_climate.csv")
    @test scenarios[1, :farm_option] == ""
    @test scenarios[1, :policy_option] == ""

    # Test with different climate type
    climate_type_future = "best_case_rcp45"
    scenarios_future = CampaspeIntegratedModel.sample_individual_options(start_day, end_day, climate_type_future)

    @test nrow(scenarios_future) == 13
    @test all(scenarios_future.farm_climate_path .== "data/climate/$(climate_type_future)_2016-2045/farm_climate.csv")
    @test all(scenarios_future.sw_climate_path .== "data/climate/$(climate_type_future)_2016-2045/sw_climate.csv")
end
