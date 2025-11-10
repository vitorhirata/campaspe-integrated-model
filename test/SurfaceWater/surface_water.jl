@testset "Surface Water Model - update_surface_water" begin
    @testset "runs without errors" begin
        # Load test network and climate data
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        # Create extraction DataFrame
        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 0.0)

        # Create exchange DataFrame (replaces Dict)
        exchange = DataFrame("Date" => climate.climate_data.Date, "406000_exchange_[ML]" => 0.0)

        # Test running on May 1st
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

    @testset "handles extractions correctly" begin
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        # Create extraction with non-zero releases
        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 100.0)
        exchange = DataFrame("Date" => climate.climate_data.Date, "406000_exchange_[ML]" => 0.0)

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
        exchange = DataFrame("Date" => climate.climate_data.Date, "406000_exchange_[ML]" => 0.0)

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

    @testset "handles groundwater exchange" begin
        network_path = "data/surface_water/two_node_network.yml"
        climate_path = "data/climate/sw_climate.csv"

        climate = CampaspeIntegratedModel.Streamfall.Climate(climate_path, "_rain", "_evap")
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)

        extraction = DataFrame("Date" => climate.climate_data.Date, "406000_releases_[ML]" => 0.0)

        # Create exchange with non-zero values
        # Negative = infiltration into aquifer, Positive = discharge from aquifer
        exchange = DataFrame("Date" => climate.climate_data.Date, "406000_exchange_[ML]" => 50.0)

        ts = 1
        date = Date("2000-05-01")

        # Should run without errors with groundwater exchange
        @test_nowarn CampaspeIntegratedModel.update_surface_water(
            sn, climate, ts, date, extraction, exchange
        )

        # Check that the model ran
        _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, "406000")
        @test dam_node.storage[ts] > 0.0
    end
end
