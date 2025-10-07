@testset "#create EnvironmentState" begin
    @testset "constructor correctly initializes state" begin
        hr_entitlement = 20000.0
        lr_entitlement = 5000.0

        env_state = CampaspeIntegratedModel.EnvironmentState(hr_entitlement, lr_entitlement)

        @test typeof(env_state) == CampaspeIntegratedModel.EnvironmentState
        @test env_state.hr_entitlement == hr_entitlement - 1656.0  # fixed_annual_losses subtracted
        @test env_state.lr_entitlement == lr_entitlement
        @test env_state.fixed_annual_losses == 1656.0
        @test env_state.season_order == 0.0
        @test env_state.water_order == 0.0
    end
end

@testset "#run_model!" begin
    @testset "simple winterlow deficit on July 1" begin
        hr_entitlement = 20000.0
        lr_entitlement = 5000.0

        env_state = CampaspeIntegratedModel.EnvironmentState(hr_entitlement, lr_entitlement)

        # July 1st with rochester flow below 120 ML/d
        ts = 1
        date = Date("1970-07-01")
        rochester_flow = fill(80.0, 365)  # Below 120 ML/d target
        other_releases = 0.0
        avail_hr = 18344.0  # hr_entitlement after losses
        avail_lr = 5000.0
        dam_vol = 220000.0  # Median scenario

        water_order = CampaspeIntegratedModel.run_model!(env_state, ts, date, rochester_flow, other_releases,
            avail_hr, avail_lr, dam_vol
        )

        # Winterlow deficit = 120 - 80 - 0 = 40 ML
        @test water_order == 40.0
        @test env_state.water_order == 40.0
        @test env_state.season_order == 40.0
    end
end
