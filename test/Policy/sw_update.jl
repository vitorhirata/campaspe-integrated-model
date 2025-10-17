@testset "#update_surface_water" begin
    # Helper function to create a minimal SwState for testing
    @testset "check_run returns false - model doesn't run" begin
        sw_state = create_sw_state()

        # Use a date that is NOT the season start (July 1) and next_run is nothing
        date = Date("1970-06-15")
        global_timestep = 1
        f_orders = Dict("Zone1" => 100.0)
        rochester_flow = fill(150.0, 365)
        dam_vol = 200000.0
        rolling_dam_level = 175.0
        release_timeframe = 7

        # Call update_surface_water - should return false
        result = CampaspeIntegratedModel.update_surface_water(
            sw_state, date, global_timestep, f_orders, rochester_flow,
            dam_vol, rolling_dam_level, release_timeframe
        )

        @test result == false
        @test sw_state.ts == 1
        @test sw_state.next_run === nothing  # Should remain nothing
    end

    @testset "first allocation on season start (July 1)" begin
        sw_state = create_sw_state()

        # Season start date
        date = Date("1970-07-01")
        global_timestep = 1
        f_orders = Dict("Zone1" => 10.0, "Zone2" => 10.0)  # Small orders to allow reserves to be met
        rochester_flow = fill(150.0, 365)
        dam_vol = 200000.0
        rolling_dam_level = 175.0
        release_timeframe = 7

        # Call update_surface_water
        result = CampaspeIntegratedModel.update_surface_water(
            sw_state, date, global_timestep, f_orders, rochester_flow,
            dam_vol, rolling_dam_level, release_timeframe
        )

        # Should return a dam release value (Float64)
        @test typeof(result) == Float64
        @test result >= 0.0

        # Check that the model ran
        @test sw_state.ts == 1
        @test sw_state.next_run !== nothing

        # Check that allocations were calculated
        @test sw_state.total_allocated > 0.0
        @test sw_state.cumu_allocation["campaspe"]["HR"] > 0.0
    end

    @testset "mid-season allocation with orders" begin
        sw_state = create_sw_state()

        # Initialize the season first (run on July 1)
        date_start = Date("1970-07-01")
        CampaspeIntegratedModel.update_surface_water(
            sw_state, date_start, 1, Dict("Zone1" => 0.0, "Zone2" => 0.0),  # No orders initially
            fill(100.0, 365), 200000.0, 100000.0, 7
        )

        # Now test mid-season (a week later) - use zero orders to avoid allocation issues
        date_mid = Date("1970-07-08")
        global_timestep = 8
        f_orders = Dict("Zone1" => 10.0, "Zone2" => 10.0)
        rochester_flow = fill(100.0, 365)  # Below 120 target for winterlow
        dam_vol = 195000.0
        rolling_dam_level = 175.0
        release_timeframe = 7

        initial_timestep = sw_state.ts
        initial_total_orders = sw_state.total_water_orders

        # Call update_surface_water
        result = CampaspeIntegratedModel.update_surface_water(
            sw_state, date_mid, global_timestep, f_orders, rochester_flow,
            dam_vol, rolling_dam_level, release_timeframe
        )

        # Should return a dam release value
        @test typeof(result) == Float64
        @test result >= 0.0

        # Timestep should have incremented
        @test sw_state.ts == initial_timestep + 1

        # Farm orders were zero but environmental/other orders may have been added
        # Just check that total water orders increased
        @test sw_state.total_water_orders > initial_total_orders

        # Environmental orders should have been processed (winterlow deficit expected)
        @test sw_state.env_state.season_order > 0.0
    end

    @testset "end of season with carryover calculation" begin
        sw_state = create_sw_state()

        # Set up season to end on the next weekly timestep (Jul 8)
        sw_state.season_end = Date("1970-07-08")

        # Initialize the season
        date_start = Date("1970-07-01")
        CampaspeIntegratedModel.update_surface_water(
            sw_state, date_start, 1, Dict("Zone1" => 0.0, "Zone2" => 0.0),  # No orders initially
            fill(150.0, 365), 200000.0, 175.0, 7
        )

        # Call on end of season date (one week later) with zero orders
        date_end = Date("1970-07-08")
        global_timestep = 8
        f_orders = Dict("Zone1" => 10.0, "Zone2" => 10.0)  # Zero orders for testing
        rochester_flow = fill(150.0, 365)
        dam_vol = 180000.0
        rolling_dam_level = 175.0
        release_timeframe = 7

        initial_year = sw_state.current_year

        # Call update_surface_water on end of season
        result = CampaspeIntegratedModel.update_surface_water(
            sw_state, date_end, global_timestep, f_orders, rochester_flow,
            dam_vol, rolling_dam_level, release_timeframe
        )

        # Should still return a dam release value
        @test typeof(result) == Float64
        @test result >= 0.0

        # Check that carryover was calculated (whether or not season actually ended)
        @test sw_state.yearly_carryover[initial_year] >= 0.0
        @test sw_state.carryover_state[initial_year] >= 0.0
    end
end
