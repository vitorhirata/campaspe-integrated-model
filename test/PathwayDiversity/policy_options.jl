@testset "implement_coupled_allocations!" begin
    policy_state = create_policy_state()
    CampaspeIntegratedModel.implement_coupled_allocations!(policy_state)

    @test policy_state.gw_state.restriction_type == "coupled"
end

@testset "change_environmental_water!" begin
        @testset "positive change" begin
        sw_state = create_sw_state()

        # Get original values
        env_zone_key = findfirst(v -> v["zone_type"] == "environmental", sw_state.zone_info)
        original_env_HR = sw_state.zone_info[env_zone_key]["entitlement"]["HR"]
        original_env_LR = sw_state.zone_info[env_zone_key]["entitlement"]["LR"]
        original_environment_hr = sw_state.env_state.hr_entitlement
        original_environment_lr = sw_state.env_state.lr_entitlement
        original_hr_entitlement = sw_state.hr_entitlement

        CampaspeIntegratedModel.change_environmental_water!(sw_state, 0.15)

        @test sw_state.zone_info[env_zone_key]["entitlement"]["HR"] ≈ original_env_HR * 1.15
        @test sw_state.zone_info[env_zone_key]["entitlement"]["LR"] ≈ original_env_LR * 1.15
        @test sw_state.env_state.hr_entitlement > original_environment_hr
        @test sw_state.env_state.lr_entitlement ≈ original_environment_lr * 1.15
        @test sw_state.hr_entitlement > original_hr_entitlement
    end

    @testset "negative change" begin
        sw_state = create_sw_state()

        # Get original values
        env_zone_key = findfirst(v -> v["zone_type"] == "environmental", sw_state.zone_info)
        original_env_HR = sw_state.zone_info[env_zone_key]["entitlement"]["HR"]
        original_env_LR = sw_state.zone_info[env_zone_key]["entitlement"]["LR"]
        original_environment_hr = sw_state.env_state.hr_entitlement
        original_environment_lr = sw_state.env_state.lr_entitlement
        original_hr_entitlement = sw_state.hr_entitlement

        CampaspeIntegratedModel.change_environmental_water!(sw_state, -0.2)

        @test sw_state.zone_info[env_zone_key]["entitlement"]["HR"] ≈ original_env_HR * 0.8
        @test sw_state.zone_info[env_zone_key]["entitlement"]["LR"] ≈ original_env_LR * 0.8
        @test sw_state.env_state.hr_entitlement < original_environment_hr
        @test sw_state.env_state.lr_entitlement ≈ original_environment_lr * 0.8
        @test sw_state.hr_entitlement < original_hr_entitlement
    end
end

@testset "change_water_price!" begin
    @testset "positive change" begin
        basin = create_agtor_basin()
        original_sw_cost = basin.zones[1].water_sources[1].cost_per_ML
        original_gw_cost = basin.zones[1].water_sources[2].cost_per_ML

        CampaspeIntegratedModel.change_water_price!(basin.zones[1], 0.25)

        @test basin.zones[1].water_sources[1].cost_per_ML ≈ original_sw_cost * 1.25
        @test basin.zones[1].water_sources[2].cost_per_ML ≈ original_gw_cost * 1.25
    end

    @testset "change_water_price! - negative change" begin
        basin = create_agtor_basin()
        original_sw_cost = basin.zones[1].water_sources[1].cost_per_ML
        original_gw_cost = basin.zones[1].water_sources[2].cost_per_ML

        CampaspeIntegratedModel.change_water_price!(basin.zones[1], -0.1)

        @test basin.zones[1].water_sources[1].cost_per_ML ≈ original_sw_cost * 0.9
        @test basin.zones[1].water_sources[2].cost_per_ML ≈ original_gw_cost * 0.9
    end
end

@testset "raise_dam_level!" begin
    @testset "default increase (15%)" begin
        network_path = "data/surface_water/two_node_network.yml"
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)
        _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, "406000")
        original_max_storage = dam_node.max_storage

        CampaspeIntegratedModel.raise_dam_level!(sn)

        @test dam_node.max_storage ≈ original_max_storage * 1.15
    end

    @testset "custom increase (20%)" begin
        network_path = "data/surface_water/two_node_network.yml"
        sn = CampaspeIntegratedModel.Streamfall.load_network("TestNetwork", network_path)
        _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, "406000")
        original_max_storage = dam_node.max_storage

        CampaspeIntegratedModel.raise_dam_level!(sn, 0.2)

        @test dam_node.max_storage ≈ original_max_storage * 1.2
    end
end

@testset "subsidise_irrigation_efficiency!" begin
    @testset "default subsidy (15%)" begin
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))

        CampaspeIntegratedModel.subsidise_irrigation_efficiency!(farm_state)

        @test farm_state.irrigation_subsidy ≈ 0.85
    end

    @testset "custom subsidy (20%)" begin
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))

        CampaspeIntegratedModel.subsidise_irrigation_efficiency!(farm_state, -0.2)

        @test farm_state.irrigation_subsidy ≈ 0.8
    end
end

@testset "subsidise_solar_pump!" begin
    @testset "default subsidy (15%)" begin
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))

        CampaspeIntegratedModel.subsidise_solar_pump!(farm_state)

        @test farm_state.solar_panel_subsidy ≈ 0.85
    end

    @testset "custom subsidy (20%)" begin
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))

        CampaspeIntegratedModel.subsidise_solar_pump!(farm_state, -0.2)

        @test farm_state.solar_panel_subsidy ≈ 0.8
    end
end
