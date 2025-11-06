"""
    implement_farm_option!(farm_option::String, basin::Agtor.Basin, farm_path::String, farm_state::FarmState, policy_state::PolicyState)::Nothing

Apply a farm adaptation option to all zones in the basin.

# Arguments
- `farm_option::String` : Name of the farm option to implement
- `basin::Agtor.Basin` : Farm basin containing zones
- `farm_path::String` : Path to farm data directory
- `farm_state::FarmState` : Farm state containing subsidy information
- `policy_state::PolicyState` : Policy state for entitlement updates
"""
function implement_farm_option!(
    farm_option::String, basin::Agtor.Basin, farm_path::String, farm_state::FarmState, policy_state::PolicyState
)::Nothing
    if farm_option == "improve_irrigation_efficiency"
        map(zone -> improve_irrigation_efficiency!(zone, farm_path, farm_state), basin.zones)
    elseif farm_option == "implement_solar_panels"
        map(zone -> implement_solar_panels!(zone, farm_path, farm_state), basin.zones)
    elseif farm_option == "adopt_drought_resistant_crops"
        map(zone -> adopt_drought_resistant_crops!(zone, farm_path), basin.zones)
    elseif farm_option == "improve_soil_TAW"
        map(zone -> improve_soil_TAW!(zone; percentage_improve=0.4), basin.zones)
    elseif farm_option == "increase_farm_entitlements"
        map(zone -> change_farm_entitlements!(zone, policy_state, 0.4), basin.zones)
    elseif farm_option == "decrease_farm_entitlements"
        map(zone -> change_farm_entitlements!(zone, policy_state, -0.4), basin.zones)
    elseif farm_option == "default"
        return nothing
    else
        @warn "Farm option $(farm_option) not implemented, no changes applied."
    end

    return nothing
end

"""
    improve_irrigation_efficiency!(zone::Agtor.FarmZone, farm_path::String, farm_state::FarmState)::Nothing

Update irrigation parameters for all fields in a zone from a new irrigation specification file.
Applies irrigation subsidy to capital cost.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing fields to update
- `farm_path::String` : Path to irrigation YAML spec file
- `farm_state::FarmState` : Farm state containing subsidy information
"""
function improve_irrigation_efficiency!(zone::Agtor.FarmZone, farm_path::String, farm_state::FarmState)::Nothing
    current_irrigation = zone.fields[1].irrigation.name
    new_irrigation = Dict(
        "gravity" => "pipe_riser", "pipe_riser" => "spray", "spray" => "", "dryland" => ""
    )[current_irrigation]
    if isempty(new_irrigation)
        return nothing
    end

    path = joinpath(dirname(farm_path), "irrigations", new_irrigation * ".yml")
    irrig_spec = CampaspeIntegratedModel.Agtor.load_spec(path)[Symbol(new_irrigation)]

    # Update each field in the zone
    for field in zone.fields
        # Update irrigation parameters
        field.irrigation.name = new_irrigation
        field.irrigation.efficiency = irrig_spec[:efficiency]
        field.irrigation.flow_ML_day = irrig_spec[:flow_ML_day]
        field.irrigation.head_pressure = irrig_spec[:head_pressure]
        field.irrigation.capital_cost = irrig_spec[:capital_cost].default_val * farm_state.irrigation_subsidy
        field.irrigation.minor_maintenance_rate = irrig_spec[:minor_maintenance_rate]
        field.irrigation.major_maintenance_rate = irrig_spec[:major_maintenance_rate]
        field.irrigation.minor_maintenance_schedule = irrig_spec[:minor_maintenance_schedule]
        field.irrigation.major_maintenance_schedule = irrig_spec[:major_maintenance_schedule]
    end

    return nothing
end

"""
    implement_solar_panels!(zone::Agtor.FarmZone, farm_path::String, farm_state::FarmState)::Nothing

Update groundwater pump parameters to solar-powered specifications.
Applies solar panel subsidy to capital cost.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing water sources to update
- `farm_path::String` : Base path to farm data directory (e.g., "data/farm")
- `farm_state::FarmState` : Farm state containing subsidy information
"""
function implement_solar_panels!(zone::Agtor.FarmZone, farm_path::String, farm_state::FarmState)::Nothing
    gw_index = findfirst(ws -> ws.name == "groundwater", zone.water_sources)
    if isnothing(gw_index)
        return nothing
    end

    pump_path = joinpath(dirname(farm_path), "pumps", "solar_groundwater.yml")
    pump_spec = CampaspeIntegratedModel.Agtor.load_spec(pump_path)[:solar_groundwater]
    gw_source = zone.water_sources[gw_index]

    # Update pump parameters
    gw_source.pump.name = "solar_groundwater"
    gw_source.pump.capital_cost = pump_spec[:capital_cost].default_val * farm_state.solar_panel_subsidy
    gw_source.pump.minor_maintenance_schedule = pump_spec[:minor_maintenance_schedule]
    gw_source.pump.major_maintenance_schedule = pump_spec[:major_maintenance_schedule]
    gw_source.pump.minor_maintenance_rate = pump_spec[:minor_maintenance_rate]
    gw_source.pump.major_maintenance_rate = pump_spec[:major_maintenance_rate]
    gw_source.pump.pump_efficiency = pump_spec[:pump_efficiency]
    gw_source.pump.cost_per_kW = pump_spec[:cost_per_kW]
    gw_source.pump.derating = pump_spec[:derating]

    return nothing
end

"""
    adopt_drought_resistant_crops!(zone::Agtor.FarmZone, farm_path::String)::Nothing

Update crop rotation to drought-resistant varieties for all fields in a zone.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing fields to update
- `farm_path::String` : Base path to farm data directory (e.g., "data/farm")

"""
function adopt_drought_resistant_crops!(zone::Agtor.FarmZone, farm_path::String)::Nothing
    crops_path = joinpath(dirname(farm_path), "crops")

    for field in zone.fields
        # Update current crop to drought variety
        new_crop_name = field.crop.name * "_drought"
        drought_spec_path = joinpath(crops_path, new_crop_name * ".yml")
        drought_spec = CampaspeIntegratedModel.Agtor.load_spec(drought_spec_path)[Symbol(new_crop_name)]

        # Update parameters
        field.crop.name = new_crop_name
        field.crop.yield_per_ha = drought_spec[:yield_per_ha]
        field.crop.price_per_yield = drought_spec[:price_per_yield]
        field.crop.variable_cost_per_ha = drought_spec[:variable_cost_per_ha]
        field.crop.water_use_ML_per_ha = drought_spec[:water_use_ML_per_ha]
        field.crop.root_depth_m = drought_spec[:root_depth_m]
        field.crop.effective_root_zone = drought_spec[:effective_root_zone]
        field.crop.naive_crop_income = (field.crop.price_per_yield * field.crop.yield_per_ha) -
            field.crop.variable_cost_per_ha

        # Update crop_rotation to drought varieties
        for crop in field.crop_rotation
            if occursin("drought", crop.name)
                continue
            end
            new_crop_name = crop.name * "_drought"

            # Load drought crop spec
            drought_spec_path = joinpath(crops_path, new_crop_name * ".yml")
            drought_spec = CampaspeIntegratedModel.Agtor.load_spec(drought_spec_path)[Symbol(new_crop_name)]

            # Update parameters
            crop.name = new_crop_name
            crop.yield_per_ha = drought_spec[:yield_per_ha]
            crop.price_per_yield = drought_spec[:price_per_yield]
            crop.variable_cost_per_ha = drought_spec[:variable_cost_per_ha]
            crop.water_use_ML_per_ha = drought_spec[:water_use_ML_per_ha]
            crop.root_depth_m = drought_spec[:root_depth_m]
            crop.effective_root_zone = drought_spec[:effective_root_zone]
            crop.naive_crop_income = (crop.price_per_yield * crop.yield_per_ha) - crop.variable_cost_per_ha
        end
    end

    return nothing
end

"""
    improve_soil_TAW!(zone::Agtor.FarmZone; percentage_improve::Float64=0.1)::Nothing

Improve soil Total Available Water (TAW) capacity for all fields in a zone based on a percentage_improve.
This represents soil improvement practices like adding organic matter, reducing compaction, or other soil health
interventions.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing fields to update
- `percentage_improve::Float64` : Percentage increase as decimal (default=0.1 for 10% improvement)
"""
function improve_soil_TAW!(zone::Agtor.FarmZone; percentage_improve::Float64=0.1)::Nothing
    for field in zone.fields
        field.soil_TAW.value *= (1.0 + percentage_improve)
    end

    return nothing
end

"""
    change_farm_entitlements!(zone::Agtor.FarmZone, policy_state::PolicyState, percentage_change::Float64)::Nothing

Update water entitlements for a farm zone in both the farm and policy model.
Applies a percentage change to both surface and groundwater entitlements for the specified zone.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing water sources to update
- `policy_state::PolicyState` : Policy state containing SW and GW allocation information
- `percentage_change::Float64` : Percentage change as decimal (e.g., 0.1 for +10%, -0.15 for -15%)
"""
function change_farm_entitlements!(zone::Agtor.FarmZone, policy_state::PolicyState, percentage_change::Float64)::Nothing
    multiplier = 1.0 + percentage_change
    zone_id = split(zone.name, "_")[end]

    # Update zone water sources (both allocation and entitlement)
    for ws in zone.water_sources
        ws.allocation *= multiplier
        ws.entitlement *= multiplier
    end

    # Update policy_state.gw_state zone_info
    gw_row_idx = findfirst(isequal(zone_id), policy_state.gw_state.zone_info.ZoneID)
    if !isnothing(gw_row_idx)
        policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"] *= multiplier
    end

    # Update policy_state.sw_state zone_info entitlements
    sw_zone_key = findfirst(v -> get(v, "zone_id", nothing) == zone_id, policy_state.sw_state.zone_info)
    if !isnothing(sw_zone_key)
        ent = policy_state.sw_state.zone_info[sw_zone_key]["entitlement"]
        ent["camp_HR"] *= multiplier
        ent["camp_LR"] *= multiplier
        ent["farm_HR"] *= multiplier
        ent["farm_LR"] *= multiplier
        ent["goul_HR"] *= multiplier
        ent["goul_LR"] *= multiplier
    end

    recalculate_entitlements!(policy_state.sw_state)
    return nothing
end

