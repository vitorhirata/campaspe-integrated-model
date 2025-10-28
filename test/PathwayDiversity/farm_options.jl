@testset "improve_irrigation_efficiency!" begin
    @testset "default parameters" begin
        basin = create_agtor_basin()
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))
        irrig_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/irrigations/pipe_riser.yml")[:pipe_riser]
        irrigation = basin.zones[1].fields[1].irrigation

        CampaspeIntegratedModel.improve_irrigation_efficiency!(basin.zones[1], "data/farm/basin", farm_state)

        @test irrigation.name == "pipe_riser"
        @test irrigation.efficiency.value == irrig_spec[:efficiency].value
        @test irrigation.capital_cost == irrig_spec[:capital_cost].value
    end

    @testset "with subsidy (85%)" begin
        basin = create_agtor_basin()
        farm_dates = Date("1970-07-01"):Day(1):Date("1971-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates, irrigation_subsidy=0.85)
        irrig_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/irrigations/pipe_riser.yml")[:pipe_riser]
        irrigation = basin.zones[1].fields[1].irrigation

        CampaspeIntegratedModel.improve_irrigation_efficiency!(basin.zones[1], "data/farm/basin", farm_state)

        @test irrigation.name == "pipe_riser"
        @test irrigation.efficiency.value == irrig_spec[:efficiency].value
        @test irrigation.capital_cost ≈ irrig_spec[:capital_cost].value * 0.85
    end
end

@testset "implement_solar_panels!" begin
    @testset "default parameters" begin
        basin = create_agtor_basin()
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=Date("1970-07-01"):Day(1):Date("1971-06-30"))
        pump_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/pumps/solar_groundwater.yml")[:solar_groundwater]
        gw_index = findfirst(ws -> ws.name == "groundwater", basin.zones[1].water_sources)
        pump = basin.zones[1].water_sources[gw_index].pump

        CampaspeIntegratedModel.implement_solar_panels!(basin.zones[1], "data/farm/basin", farm_state)

        @test pump.name == "solar_groundwater"
        @test pump.cost_per_kW == pump_spec[:cost_per_kW].value
        @test pump.capital_cost == pump_spec[:capital_cost].default_val
    end

    @testset "with subsidy (85%)" begin
        basin = create_agtor_basin()
        farm_dates = Date("1970-07-01"):Day(1):Date("1971-06-30")
        farm_state = CampaspeIntegratedModel.FarmState(farm_dates=farm_dates, solar_panel_subsidy=0.85)
        pump_spec = CampaspeIntegratedModel.Agtor.load_spec("data/farm/pumps/solar_groundwater.yml")[:solar_groundwater]
        gw_index = findfirst(ws -> ws.name == "groundwater", basin.zones[1].water_sources)
        pump = basin.zones[1].water_sources[gw_index].pump

        CampaspeIntegratedModel.implement_solar_panels!(basin.zones[1], "data/farm/basin", farm_state)

        @test pump.name == "solar_groundwater"
        @test pump.cost_per_kW == pump_spec[:cost_per_kW].value
        @test pump.capital_cost ≈ pump_spec[:capital_cost].default_val * 0.85
    end
end

@testset "adopt_drought_resistant_crops!" begin
    basin = create_agtor_basin()
    crop_spec1 = CampaspeIntegratedModel.Agtor.load_spec("data/farm/crops/irrigated_wheat_drought.yml")
    crop_spec1 = crop_spec1[:irrigated_wheat_drought]
    crop_spec2 = CampaspeIntegratedModel.Agtor.load_spec("data/farm/crops/irrigated_canola_drought.yml")
    crop_spec2 = crop_spec2[:irrigated_canola_drought]
    crop = basin.zones[1].fields[1].crop
    crop1 = basin.zones[1].fields[1].crop_rotation[1]
    crop2 = basin.zones[1].fields[1].crop_rotation[2]

    CampaspeIntegratedModel.adopt_drought_resistant_crops!(basin.zones[1], "data/farm/basin")

    @test crop.name == "irrigated_wheat_drought"
    @test crop.water_use_ML_per_ha == crop_spec1[:water_use_ML_per_ha].value
    @test crop.root_depth_m == crop_spec1[:root_depth_m].value
    @test crop1.name == "irrigated_wheat_drought"
    @test crop1.water_use_ML_per_ha == crop_spec1[:water_use_ML_per_ha].value
    @test crop1.root_depth_m == crop_spec1[:root_depth_m].value
    @test crop2.name == "irrigated_canola_drought"
    @test crop2.water_use_ML_per_ha == crop_spec2[:water_use_ML_per_ha].value
    @test crop2.root_depth_m == crop_spec2[:root_depth_m].value
end

@testset "improve_soil_TAW!" begin
    basin = create_agtor_basin()
    original_TAW = basin.zones[1].fields[1].soil_TAW.value
    CampaspeIntegratedModel.improve_soil_TAW!(basin.zones[1]; percentage_improve=0.15)

    @test basin.zones[1].fields[1].soil_TAW.value ≈ original_TAW * 1.15
end

@testset "change_farm_entitlements!" begin
    @testset "positive percentage_change" begin
        basin = create_agtor_basin()
        basin.zones[1].name = "Zone_2" # Zone_1 don't have entitlements, so the update on the policy state does nothing
        policy_state = create_policy_state()
        zone_id = split(basin.zones[1].name, "_")[end]

        original_sw_allocation = basin.zones[1].water_sources[1].allocation
        original_sw_entitlement = basin.zones[1].water_sources[1].entitlement
        gw_row_idx = findfirst(isequal(zone_id), policy_state.gw_state.zone_info.ZoneID)
        original_gw_ent = policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"]
        sw_zone_key = findfirst(v -> get(v, "zone_id", nothing) == zone_id, policy_state.sw_state.zone_info)
        original_camp_HR = policy_state.sw_state.zone_info[sw_zone_key]["entitlement"]["camp_HR"]
        original_farm_hr_entitlement = policy_state.sw_state.farm_hr_entitlement

        CampaspeIntegratedModel.change_farm_entitlements!(basin.zones[1], policy_state, 0.2)

        @test basin.zones[1].water_sources[1].allocation ≈ original_sw_allocation * 1.2
        @test basin.zones[1].water_sources[1].entitlement ≈ original_sw_entitlement * 1.2
        @test policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"] ≈ original_gw_ent * 1.2
        @test policy_state.sw_state.zone_info[sw_zone_key]["entitlement"]["camp_HR"] ≈ original_camp_HR * 1.2
        @test policy_state.sw_state.farm_hr_entitlement > original_farm_hr_entitlement
    end

    @testset "negative percentage_change" begin
        basin = create_agtor_basin()
        basin.zones[1].name = "Zone_2" # Zone_1 don't have entitlements, so the update on the policy state does nothing
        policy_state = create_policy_state()
        zone_id = split(basin.zones[1].name, "_")[end]

        original_sw_allocation = basin.zones[1].water_sources[1].allocation
        original_sw_entitlement = basin.zones[1].water_sources[1].entitlement
        gw_row_idx = findfirst(isequal(zone_id), policy_state.gw_state.zone_info.ZoneID)
        original_gw_ent = policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"]
        sw_zone_key = findfirst(v -> get(v, "zone_id", nothing) == zone_id, policy_state.sw_state.zone_info)
        original_camp_HR = policy_state.sw_state.zone_info[sw_zone_key]["entitlement"]["camp_HR"]
        original_farm_hr_entitlement = policy_state.sw_state.farm_hr_entitlement

        CampaspeIntegratedModel.change_farm_entitlements!(basin.zones[1], policy_state, -0.15)

        @test basin.zones[1].water_sources[1].allocation ≈ original_sw_allocation * 0.85
        @test basin.zones[1].water_sources[1].entitlement ≈ original_sw_entitlement * 0.85
        @test policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"] ≈ original_gw_ent * 0.85
        @test policy_state.sw_state.zone_info[sw_zone_key]["entitlement"]["camp_HR"] ≈ original_camp_HR * 0.85
        @test policy_state.sw_state.farm_hr_entitlement < original_farm_hr_entitlement
    end
end
