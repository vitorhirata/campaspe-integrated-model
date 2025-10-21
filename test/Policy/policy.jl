@testset "#update_policy integration test" begin
    @testset "update_policy returns valid allocations" begin
        # Setup test parameters
        data_path = "data/policy/"
        model_run_range::StepRange{Date, Period} = Date("1970-07-01"):Day(1):Date("1971-06-30")
        goulburn_alloc_scenario = "high"
        dam_ext = DataFrame(
            Time = [Date("1970-07-01")],
            Extraction = [10.0]
        )
        carryover_period = 1
        max_carryover_perc = 0.95
        restriction_type = "default"

        # Create PolicyState
        policy_state = CampaspeIntegratedModel.PolicyState(
            data_path,
            model_run_range,
            goulburn_alloc_scenario,
            dam_ext,
            carryover_period,
            max_carryover_perc,
            restriction_type,
        )

        # Setup update_policy parameters
        ts = 1
        dt = Date("1970-07-01")
        f_orders = Dict{String, Float64}()  # Empty farm orders for simplicity
        gw_orders = Dict{String, Float64}()  # Empty groundwater orders
        dam_vol = 50000.0  # ML
        dam_rolling_level = 0.7  # 70% full
        rochester_flow = [100.0, 100.0, 100.0]  # ML/day vector
        proj_inflow = 500.0  # ML
        gw_level = Dict{String, Float64}("62589" => 10.0, "79324" => 12.0)  # Bore levels in meters
        release_timeframe = 14  # days

        # Run the policy model
        daily_dam_release, farm_allocations = CampaspeIntegratedModel.update_policy(
            policy_state,
            ts,
            dt,
            f_orders,
            gw_orders,
            dam_vol,
            dam_rolling_level,
            rochester_flow,
            proj_inflow,
            gw_level,
            release_timeframe
        )

        # Test return types
        @test typeof(daily_dam_release) <: Union{Float64, Bool}
        @test typeof(farm_allocations) == Dict{String, Any}

        # Test that projected inflow was set
        @test policy_state.sw_state.proj_inflow[policy_state.sw_state.ts] == proj_inflow

        # Test farm allocations structure (if any farm zones exist)
        if !isempty(farm_allocations)
            first_zone_alloc = first(values(farm_allocations))

            # Test allocation structure
            @test haskey(first_zone_alloc, "SW")
            @test haskey(first_zone_alloc, "GW")

            # Test SW allocation structure
            @test haskey(first_zone_alloc["SW"], "HR")
            @test haskey(first_zone_alloc["SW"], "LR")

            # Test GW allocation structure
            @test haskey(first_zone_alloc["GW"], "HR")
            @test haskey(first_zone_alloc["GW"], "LR")

            # Test that allocations are non-negative
            @test first_zone_alloc["SW"]["HR"] >= 0.0
            @test first_zone_alloc["SW"]["LR"] >= 0.0
            @test first_zone_alloc["GW"]["HR"] >= 0.0
            @test first_zone_alloc["GW"]["LR"] >= 0.0
        end
    end
end
