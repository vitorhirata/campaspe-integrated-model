@testset "#PolicyState constructor" begin
    @testset "creates PolicyState with valid parameters" begin
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

        # Test that PolicyState was created
        @test typeof(policy_state) == CampaspeIntegratedModel.PolicyState

        # Test that SwState was initialized
        @test typeof(policy_state.sw_state) == CampaspeIntegratedModel.SwState
        @test policy_state.sw_state.goulburn_alloc_scenario == goulburn_alloc_scenario
        @test policy_state.sw_state.model_run_range == model_run_range

        # Test that GwState was initialized
        @test typeof(policy_state.gw_state) == CampaspeIntegratedModel.GwState

        # Test default cap values
        @test policy_state.sw_cap == 1.0
        @test policy_state.gw_cap == 0.6
    end
end

