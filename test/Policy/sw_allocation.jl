function create_test_sw_state()
    model_run_range::StepRange{Date, Period} = Date("1968-05-01"):Week(1):Date("1988-04-30")
    goulburn_alloc_scenario = "high"
    dam_ext = DataFrame(
        Time = [Date("2020-07-01"), Date("2020-07-08")],
        Extraction = [10.0, 15.0],
    )
    zone_info::Dict{Int64, Any} = Dict(
        1 => Dict(
            "entitlement" => Dict(
                "camp_HR" => 1000.0, "camp_LR" => 500.0,
                "goul_HR" => 800.0, "goul_LR" => 0.0,
                "farm_HR" => 1000.0, "farm_LR" => 500.0
            ),
            "water_system" => "Campaspe Irrigation Area",
            "regulation_zone" => "Regulated 4C",
            "areas" => Dict("crop_ha" => 5000.0, "zone_ha" => 50000.0),
            "name" => "Test Zone 1",
            "zone_type" => "farm"
        )
    )

    sw_state = CampaspeIntegratedModel.SwState(model_run_range, zone_info, goulburn_alloc_scenario, dam_ext)
    return sw_state
end

@testset "#first_allocation" begin
    @testset "allocates HR water correctly for year 1" begin
        sw_state = create_test_sw_state()
        year = 1
        ts = 1
        gmw_vol = 50000.0  # Available GMW volume
        rolling_dam_level = 180.0

        # Call first_allocation
        CampaspeIntegratedModel.first_allocation(sw_state, year, ts, gmw_vol, rolling_dam_level)

        # Test that total allocated is set correctly (should be min of gmw_vol and hr_entitlement)
        @test sw_state.total_allocated > 0.0
        @test sw_state.total_allocated <= sw_state.hr_entitlement

        # Test that cumulative allocation is updated
        @test sw_state.cumu_allocation["campaspe"]["HR"] == sw_state.total_allocated
        @test sw_state.cumu_allocation["campaspe"]["LR"] == 0.0

        # Test that percentage entitlement is calculated
        @test sw_state.perc_entitlement["campaspe"]["HR"] >= 0.0
        @test sw_state.perc_entitlement["campaspe"]["HR"] <= 1.0

        # Test that LR allocations are zero at first allocation
        @test sw_state.avail_allocation["campaspe"]["LR"] == 0.0

        # Test that Goulburn allocation percentage is set
        @test sw_state.goulburn_alloc_perc >= 0.0
        @test sw_state.goulburn_alloc_perc <= 1.0

        # Test that zone allocations are set
        for z_info in values(sw_state.zone_info)
            @test z_info["avail_allocation"]["campaspe"]["HR"] >= 0.0
            @test z_info["avail_allocation"]["campaspe"]["LR"] == 0.0
            @test z_info["allocated_to_date"]["campaspe"]["HR"] >= 0.0
            @test z_info["ts_water_orders"]["campaspe"][1] == 0.0
        end
    end
end

@testset "#later_allocation" begin
    @testset "wet scenario with LR allocation (HR at 100%, reserves met)" begin
        sw_state = create_test_sw_state()
        year = 2  # Use year > 1 so calc_next_season_reserves! will run properly
        ts = 2

        # Setup initial state - simulate that first_allocation already ran
        sw_state.current_time = ts
        sw_state.current_year = year
        sw_state.hr_entitlement = 10000.0
        sw_state.lr_entitlement = 5000.0
        sw_state.worst_case_loss = 1000.0

        # Set HR to 100% to trigger LR allocation
        sw_state.cumu_allocation["campaspe"]["HR"] = sw_state.hr_entitlement
        sw_state.cumu_allocation["campaspe"]["LR"] = 0.0
        sw_state.avail_allocation["campaspe"]["HR"] = 5000.0
        sw_state.avail_allocation["campaspe"]["LR"] = 0.0
        sw_state.perc_entitlement["campaspe"]["HR"] = 1.0
        sw_state.perc_entitlement["campaspe"]["LR"] = 0.0
        sw_state.total_water_orders = 2000.0  # Water already ordered in the season

        # Set gmw_vol for current timestep (used by calc_next_season_reserves!)
        gmw_vol = 25000.0  # Large volume to enable LR allocation (after reserves and HR)
        sw_state.gmw_vol[ts] = gmw_vol

        # Set reserves at previous timestep (ts-1) for calc_next_season_reserves!
        sw_state.ts_reserves["HR"][ts - 1] = sw_state.hr_entitlement
        sw_state.ts_reserves["op"][ts - 1] = sw_state.worst_case_loss
        # Set reserves to met at current timestep ts (for lr_allocation check)
        sw_state.ts_reserves["HR"][ts] = sw_state.hr_entitlement
        sw_state.ts_reserves["op"][ts] = sw_state.worst_case_loss
        # Set year reserves (used in LR calculation on line 197)
        sw_state.reserves["HR"][year] = sw_state.hr_entitlement
        sw_state.reserves["op"][year] = sw_state.worst_case_loss

        # Setup wet/high Goulburn scenario
        sw_state.goulburn_wet_scenario = true
        sw_state.goulburn_alloc_perc = 0.74
        sw_state.goulburn_increment = 6.5
        sw_state.goulburn_alloc_func = CampaspeIntegratedModel.goulburn_wet_alloc

        # Setup zone info for allocation
        for z_info in values(sw_state.zone_info)
            z_info["avail_allocation"]["campaspe"]["HR"] = 1000.0
            z_info["avail_allocation"]["campaspe"]["LR"] = 0.0
            z_info["allocated_to_date"]["campaspe"]["HR"] = 1000.0
            z_info["allocated_to_date"]["campaspe"]["LR"] = 0.0
            z_info["carryover_state"]["HR"] = 0.0
            z_info["carryover_state"]["LR"] = 0.0
        end

        farm_orders = Dict(1 => 100.0)

        # Call later_allocation
        CampaspeIntegratedModel.later_allocation(sw_state, year, ts, gmw_vol, farm_orders)

        # Test that LR allocation occurred (HR at 100%, reserves met)
        @test sw_state.cumu_allocation["campaspe"]["LR"] > 0.0
        @test sw_state.perc_entitlement["campaspe"]["LR"] > 0.0

        # Test that HR remains at 100%
        @test isapprox(sw_state.perc_entitlement["campaspe"]["HR"], 1.0, atol=1e-10)

        # Test that Goulburn allocation increased (wet scenario incremental)
        @test sw_state.goulburn_alloc_perc > 0.74
        @test sw_state.goulburn_alloc_perc <= 1.0

        # Test that zone allocations are updated
        for z_info in values(sw_state.zone_info)
            @test z_info["allocated_to_date"]["campaspe"]["LR"] >= 0.0
        end
    end

    @testset "dry-median scenario with HR allocation only" begin
        sw_state = create_test_sw_state()
        sw_state.goulburn_alloc_scenario = "median"
        year = 1
        ts = 2

        # Setup initial state - HR below 100%
        sw_state.current_time = ts
        sw_state.hr_entitlement = 10000.0
        sw_state.lr_entitlement = 5000.0
        sw_state.worst_case_loss = 1000.0

        # Set HR to 50% (below 100%, so no LR allocation)
        sw_state.cumu_allocation["campaspe"]["HR"] = 5000.0
        sw_state.cumu_allocation["campaspe"]["LR"] = 0.0
        sw_state.avail_allocation["campaspe"]["HR"] = 2000.0
        sw_state.avail_allocation["campaspe"]["LR"] = 0.0
        sw_state.perc_entitlement["campaspe"]["HR"] = 0.5
        sw_state.perc_entitlement["campaspe"]["LR"] = 0.0

        # Reserves not relevant since HR < 100%
        sw_state.ts_reserves["HR"][ts] = 0.0
        sw_state.ts_reserves["op"][ts] = 0.0
        sw_state.reserves["HR"][year] = 0.0
        sw_state.reserves["op"][year] = 0.0

        # Setup dry/drought Goulburn scenario (median)
        sw_state.goulburn_wet_scenario = false
        sw_state.goulburn_alloc_perc = 0.0
        sw_state.goulburn_alloc_func = CampaspeIntegratedModel.goulburn_dry_median

        # Setup zone info for allocation
        for z_info in values(sw_state.zone_info)
            z_info["avail_allocation"]["campaspe"]["HR"] = 500.0
            z_info["avail_allocation"]["campaspe"]["LR"] = 0.0
            z_info["allocated_to_date"]["campaspe"]["HR"] = 500.0
            z_info["allocated_to_date"]["campaspe"]["LR"] = 0.0
            z_info["carryover_state"]["HR"] = 0.0
            z_info["carryover_state"]["LR"] = 0.0
        end

        gmw_vol = 8000.0
        farm_orders = Dict(1 => 50.0)

        # Call later_allocation
        CampaspeIntegratedModel.later_allocation(sw_state, year, ts, gmw_vol, farm_orders)

        # Test that HR allocation increased
        @test sw_state.cumu_allocation["campaspe"]["HR"] >= 5000.0
        @test sw_state.perc_entitlement["campaspe"]["HR"] > 0.5
        @test sw_state.perc_entitlement["campaspe"]["HR"] < 1.0

        # Test that LR allocation did NOT occur (HR not at 100%)
        @test sw_state.cumu_allocation["campaspe"]["LR"] == 0.0
        @test sw_state.perc_entitlement["campaspe"]["LR"] == 0.0

        # Test that Goulburn allocation uses dry scenario formula
        @test sw_state.goulburn_alloc_perc >= 0.0
        @test sw_state.goulburn_alloc_perc <= 1.0

        # Test that zone allocations reflect HR percentage
        for z_info in values(sw_state.zone_info)
            @test z_info["allocated_to_date"]["campaspe"]["HR"] > 0.0
            @test z_info["allocated_to_date"]["campaspe"]["LR"] == 0.0
        end
    end
end

@testset "#calc_allocation" begin
    @testset "first timestep (ts=1) calls first_allocation" begin
        sw_state = create_test_sw_state()
        sw_state.current_time = 1
        sw_state.current_year = 1

        # Set up initial conditions
        dam_vol = 50000.0
        rolling_dam_level = 180.0
        farm_orders = Dict{Int64, Float64}()

        # Set projected inflow for this timestep
        sw_state.proj_inflow[1] = 5000.0

        # Call calc_allocation
        CampaspeIntegratedModel.calc_allocation(sw_state, farm_orders, dam_vol, rolling_dam_level)

        # Test that usable dam volume was calculated
        @test sw_state.usable_dam_vol >= 0.0
        @test sw_state.usable_dam_vol <= dam_vol

        # Test that GMW volume was calculated
        @test sw_state.gmw_vol[1] >= 0.0

        # Test that first allocation ran (HR should be allocated, LR should be zero)
        @test sw_state.cumu_allocation["campaspe"]["HR"] > 0.0
        @test sw_state.cumu_allocation["campaspe"]["LR"] == 0.0

        # Test that total allocated is set
        @test sw_state.total_allocated > 0.0

        # Test that percentage entitlement is calculated
        @test sw_state.perc_entitlement["campaspe"]["HR"] > 0.0
        @test sw_state.perc_entitlement["campaspe"]["HR"] <= 1.0

        # Test that Goulburn allocation is initialized
        @test sw_state.goulburn_alloc_perc >= 0.0
        @test sw_state.goulburn_alloc_perc <= 1.0
    end

    @testset "later timestep (ts=2) calls later_allocation" begin
        sw_state = create_test_sw_state()
        sw_state.current_time = 2
        sw_state.current_year = 1

        # Set up state as if first allocation already happened
        sw_state.hr_entitlement = 10000.0
        sw_state.lr_entitlement = 5000.0
        sw_state.cumu_allocation["campaspe"]["HR"] = 5000.0
        sw_state.cumu_allocation["campaspe"]["LR"] = 0.0
        sw_state.perc_entitlement["campaspe"]["HR"] = 0.5
        sw_state.perc_entitlement["campaspe"]["LR"] = 0.0
        sw_state.total_water_orders = 0.0

        # Set up Goulburn allocation state
        sw_state.goulburn_wet_scenario = false
        sw_state.goulburn_alloc_func = CampaspeIntegratedModel.goulburn_dry_high
        sw_state.goulburn_alloc_perc = 0.6

        # Set up zone allocations
        for z_info in values(sw_state.zone_info)
            z_info["avail_allocation"]["campaspe"]["HR"] = 500.0
            z_info["avail_allocation"]["campaspe"]["LR"] = 0.0
            z_info["allocated_to_date"]["campaspe"]["HR"] = 500.0
            z_info["allocated_to_date"]["campaspe"]["LR"] = 0.0
            z_info["carryover_state"]["HR"] = 0.0
            z_info["carryover_state"]["LR"] = 0.0
        end

        # Set up for calc_allocation call
        dam_vol = 60000.0
        rolling_dam_level = 175.0
        farm_orders = Dict(1 => 100.0)

        # Set projected inflow and previous timestep values
        sw_state.proj_inflow[2] = 6000.0
        sw_state.gmw_vol[1] = 20000.0

        # Call calc_allocation
        CampaspeIntegratedModel.calc_allocation(sw_state, farm_orders, dam_vol, rolling_dam_level)

        # Test that usable dam volume was calculated
        @test sw_state.usable_dam_vol >= 0.0
        @test sw_state.usable_dam_vol <= dam_vol

        # Test that GMW volume was calculated for ts=2
        @test sw_state.gmw_vol[2] >= 0.0

        # Test that later allocation ran (HR should have increased or stayed same)
        @test sw_state.cumu_allocation["campaspe"]["HR"] >= 5000.0

        # Test that catchment stats were updated
        @test sw_state.total_allocated >= 0.0

        # Test that percentage entitlement is updated
        @test sw_state.perc_entitlement["campaspe"]["HR"] >= 0.5
        @test sw_state.perc_entitlement["campaspe"]["HR"] <= 1.0

        # Test that Goulburn allocation was updated
        @test sw_state.goulburn_alloc_perc >= 0.0
        @test sw_state.goulburn_alloc_perc <= 1.0

        # Test that farm orders were processed
        for z_info in values(sw_state.zone_info)
            @test z_info["ts_water_orders"]["campaspe"][2] >= 0.0
        end
    end
end
