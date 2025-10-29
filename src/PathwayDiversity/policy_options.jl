"""
    implement_coupled_allocations!(policy_state::PolicyState)::Nothing

Change groundwater allocations to be coupled with surface water allocation.

# Arguments
- `policy_state::PolicyState` : Policy state
"""
function implement_coupled_allocations!(policy_state::PolicyState)::Nothing
    policy_state.gw_state.restriction_type = "coupled"
    return nothing
end

"""
    change_environmental_water!(sw_state::SwState, percentage_change::Float64)::Nothing

Update environmental water entitlements for all environmental zones in both sw_state and environment_state.
Applies a percentage change to both HR and LR entitlements and recalculates aggregated totals.

# Arguments
- `sw_state::SwState` : Surface water policy state containing SW and environment allocation information
- `percentage_change::Float64` : Percentage change as decimal (e.g., 0.1 for +10%, -0.15 for -15%)
"""
function change_environmental_water!(sw_state::SwState, percentage_change::Float64)::Nothing
    for (key, value) in sw_state.zone_info
        if value["zone_type"] == "environmental"
            value["entitlement"]["HR"] *= (1.0 + percentage_change)
            value["entitlement"]["LR"] *= (1.0 + percentage_change)
        end
    end

    recalculate_entitlements!(sw_state)
    return nothing
end

"""
    change_water_price!(zone::Agtor.FarmZone, percentage_change::Float64)::Nothing

Update water price (cost_per_ML) for all water sources in a farm zone.
Applies a percentage change to the cost_per_ML field.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone containing water sources to update
- `percentage_change::Float64` : Percentage change as decimal (e.g., 0.1 for +10%, -0.15 for -15%)
"""
function change_water_price!(zone::Agtor.FarmZone, percentage_change::Float64)::Nothing
    for ws in zone.water_sources
        ws.cost_per_ML *= (1.0 + percentage_change)
    end

    return nothing
end

"""
    raise_dam_level!(sn::Streamfall.StreamfallNetwork, percentage_change::Float64=0.15)::Nothing

Increase dam storage capacity by raising the dam wall level. Updates the max_storage parameter of the dam node.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network containing the dam
- `percentage_change::Float64` : Percentage change as decimal (default: 0.15 for 15% increase)
- `node_id::String` : Node id of the dam node. Defaults for "406000"
"""
function raise_dam_level!(
    sn::Streamfall.StreamfallNetwork, percentage_change::Float64=0.15; node_id::String="406000"
)::Nothing
    _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, node_id)
    dam_node.max_storage *= (1.0 + percentage_change)

    return nothing
end

"""
    subsidise_irrigation_efficiency!(farm_state::FarmState, percentage_change::Float64=-0.15)::Nothing

Provide subsidy for irrigation efficiency improvements by reducing the effective capital cost.
Updates the irrigation subsidy multiplier in farm state.

# Arguments
- `farm_state::FarmState` : Farm state containing subsidy information
- `percentage_change::Float64` : Percentage change as decimal (default: -0.15 for 15% subsidy/reduction)
"""
function subsidise_irrigation_efficiency!(farm_state::FarmState, percentage_change::Float64=-0.15)::Nothing
    farm_state.irrigation_subsidy = 1.0 + percentage_change

    return nothing
end

"""
    subsidise_solar_pump!(farm_state::FarmState, percentage_change::Float64=-0.15)::Nothing

Provide subsidy for solar pump adoption by reducing the effective capital cost.
Updates the solar panel subsidy multiplier in farm state.

# Arguments
- `farm_state::FarmState` : Farm state containing subsidy information
- `percentage_change::Float64` : Percentage change as decimal (default: -0.15 for 15% subsidy/reduction)
"""
function subsidise_solar_pump!(farm_state::FarmState, percentage_change::Float64=-0.15)::Nothing
    farm_state.solar_panel_subsidy = 1.0 + percentage_change

    return nothing
end
