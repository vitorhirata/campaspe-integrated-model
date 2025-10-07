@testset "Farm Model - update_farm" begin
    @testset "returns zero orders outside plant season" begin
        # Load test basin
        basin_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/TestBasin.yml")[:TestBasin]
        zone_specs = basin_spec[:zone_spec]
        OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
        manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )

        basin = CampaspeIntegratedModel.Agtor.Basin(
            name=basin_spec[:name],
            zone_spec=zone_specs,
            managers=manage_zones,
            climate_data="data/farm/climate/test_climate.csv"
        )

        # Create farm state with fortnight dates
        farm_dates = Date("2000-05-25"):Day(14):Date("2000-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates)

        # Create inputs (outside plant season)
        gw_levels = Dict("1" => 10.0)
        water_allocs::Dict{String, Any} = Dict("1" => Dict(
            "SW" => Dict("HR" => 1000.0, "LR" => 500.0),
            "GW" => Dict("HR" => 800.0, "LR" => 0.0)
        ))

        dt = Date("2000-01-15")  # Outside plant season (before May 25)
        ts = 1

        # Call update_farm
        sw_orders, gw_orders = CampaspeIntegratedModel.update_farm(
            basin, gw_levels, water_allocs, dt, ts, farm_state
        )

        # Should return zero orders
        @test sw_orders["1"] == 0.0
        @test gw_orders["1"] == 0.0
        @test farm_state.is_plant_season == false
    end

    @testset "resets allocations on plant season start" begin
        # Load test basin
        basin_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/TestBasin.yml")[:TestBasin]
        zone_specs = basin_spec[:zone_spec]
        OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
        manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )

        basin = CampaspeIntegratedModel.Agtor.Basin(
            name=basin_spec[:name],
            zone_spec=zone_specs,
            managers=manage_zones,
            climate_data="data/farm/climate/test_climate.csv"
        )

        # Create farm state
        farm_dates = Date("2000-05-25"):Day(14):Date("2000-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates)

        # Create inputs
        gw_levels = Dict("1" => 10.0)
        water_allocs::Dict{String, Any} = Dict("1" => Dict(
            "SW" => Dict("HR" => 0.0, "LR" => 0.0),  # Zero allocation initially
            "GW" => Dict("HR" => 0.0, "LR" => 0.0)
        ))

        dt = Date("2000-05-25")  # Plant season start
        ts = 1

        # Call update_farm
        sw_orders, gw_orders = CampaspeIntegratedModel.update_farm(
            basin, gw_levels, water_allocs, dt, ts, farm_state
        )

        # Should set is_plant_season to true
        @test farm_state.is_plant_season == true

        # Check that allocations were reset to entitlements
        zone = basin.zones[1]
        for ws in zone.water_sources
            @test ws.allocation == ws.entitlement
        end
    end

    @testset "runs on fortnight dates during season" begin
        # Load test basin
        basin_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/TestBasin.yml")[:TestBasin]
        zone_specs = basin_spec[:zone_spec]
        OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
        manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )

        basin = CampaspeIntegratedModel.Agtor.Basin(
            name=basin_spec[:name],
            zone_spec=zone_specs,
            managers=manage_zones,
            climate_data="data/farm/climate/test_climate.csv"
        )

        # Create farm state
        farm_dates = Date("2000-05-25"):Day(14):Date("2000-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates)
        farm_state.is_plant_season = true  # Already in season

        # Create inputs
        gw_levels = Dict("1" => 10.0)
        water_allocs::Dict{String, Any} = Dict("1" => Dict(
            "SW" => Dict("HR" => 1000.0, "LR" => 500.0),
            "GW" => Dict("HR" => 800.0, "LR" => 0.0)
        ))

        dt = Date("2000-06-08")  # Fortnight date (14 days after May 25)
        ts = 15

        # Call update_farm
        @test_nowarn CampaspeIntegratedModel.update_farm(
            basin, gw_levels, water_allocs, dt, ts, farm_state
        )
    end

    @testset "skips non-fortnight dates" begin
        # Load test basin
        basin_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/TestBasin.yml")[:TestBasin]
        zone_specs = basin_spec[:zone_spec]
        OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
        manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )

        basin = CampaspeIntegratedModel.Agtor.Basin(
            name=basin_spec[:name],
            zone_spec=zone_specs,
            managers=manage_zones,
            climate_data="data/farm/climate/test_climate.csv"
        )

        # Create farm state
        farm_dates = Date("2000-05-25"):Day(14):Date("2000-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates)
        farm_state.is_plant_season = true

        # Create inputs
        gw_levels = Dict("1" => 10.0)
        water_allocs::Dict{String, Any} = Dict("1" => Dict(
            "SW" => Dict("HR" => 1000.0, "LR" => 500.0),
            "GW" => Dict("HR" => 800.0, "LR" => 0.0)
        ))

        dt = Date("2000-06-01")  # Not a fortnight date
        ts = 8

        # Call update_farm
        sw_orders, gw_orders = CampaspeIntegratedModel.update_farm(
            basin, gw_levels, water_allocs, dt, ts, farm_state
        )

        # Should return zero orders (skipped)
        @test sw_orders["1"] == 0.0
        @test gw_orders["1"] == 0.0
    end

    @testset "ends plant season on harvest date" begin
        # Load test basin
        basin_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/TestBasin.yml")[:TestBasin]
        zone_specs = basin_spec[:zone_spec]
        OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
        manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )

        basin = CampaspeIntegratedModel.Agtor.Basin(
            name=basin_spec[:name],
            zone_spec=zone_specs,
            managers=manage_zones,
            climate_data="data/farm/climate/test_climate.csv"
        )

        # Create farm state
        farm_dates = Date("2000-05-25"):Day(14):Date("2001-02-01")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates)
        farm_state.is_plant_season = true

        # Create inputs
        gw_levels = Dict("1" => 10.0)
        water_allocs::Dict{String, Any} = Dict("1" => Dict(
            "SW" => Dict("HR" => 1000.0, "LR" => 500.0),
            "GW" => Dict("HR" => 800.0, "LR" => 0.0)
        ))

        dt = Date("2001-01-20")  # Plant season end (harvest date)
        ts = 240

        # Call update_farm
        sw_orders, gw_orders = CampaspeIntegratedModel.update_farm(
            basin, gw_levels, water_allocs, dt, ts, farm_state
        )

        # Should end plant season
        @test farm_state.is_plant_season == false
    end
end
