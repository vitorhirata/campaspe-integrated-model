@testset "Surface Water Model - update_surface_water" begin
    @testset "runs during irrigation season without errors" begin
        # Load test network and climate data
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        # Create extraction DataFrame
        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 0.0)

        # Create exchange dictionary
        exchange = Dict{String, Float64}("406219" => 0.0, "406000" => 0.0)

        # Test running during irrigation season (May)
        ts = 1
        date = Date("2000-05-01")

        # Should run without errors
        @test_nowarn CampaspeIntegratedModel.update_surface_water(
            sn, climate, ts, date, extraction, exchange
        )

        # Check that the model updated storage
        _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, "406000")
        @test dam_node.storage[ts] > 0.0
    end

    @testset "returns early outside irrigation season" begin
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 0.0)
        exchange = Dict{String, Float64}("406219" => 0.0, "406000" => 0.0)

        # Test with a date outside irrigation season (March)
        ts = 1
        date = Date("2000-03-15")

        # Should return nothing (early return)
        result = CampaspeIntegratedModel.update_surface_water(
            sn, climate, ts, date, extraction, exchange
        )
        @test result === nothing
    end

    @testset "handles extractions correctly" begin
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        # Create extraction with non-zero releases
        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 100.0)
        exchange = Dict{String, Float64}("406219" => 0.0, "406000" => 0.0)

        ts = 1
        date = Date("2000-05-01")

        # Should run without errors with extractions
        @test_nowarn CampaspeIntegratedModel.update_surface_water(
            sn, climate, ts, date, extraction, exchange
        )
    end

    @testset "runs multiple timesteps sequentially" begin
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 0.0)
        exchange = Dict{String, Float64}("406219" => 0.0, "406000" => 0.0)

        # Run for 5 timesteps
        for ts in 1:5
            date = Date("2000-05-01") + Dates.Day(ts - 1)
            CampaspeIntegratedModel.update_surface_water(
                sn, climate, ts, date, extraction, exchange
            )
        end

        # Check that storage was updated for all timesteps
        _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, "406000")
        @test all(dam_node.storage[1:5] .> 0.0)
    end
end
