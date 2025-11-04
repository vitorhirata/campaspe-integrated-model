using Streamfall

"""
    update_water(sn::Streamfall.StreamfallNetwork, climate::Streamfall.Climate, ts::Int64, date::Date, extraction::DataFrame)::Nothing

Update and run the surface water and groundwater model for a single timestep.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `climate::Streamfall.Climate` : Climate data (rainfall and evaporation)
- `ts::Int64` : Current timestep index
- `date::Date` : Current date
- `extraction::DataFrame` : DataFrame containing water extractions and releases

# Returns
- `Nothing`
"""
function update_water(
    sn::Streamfall.StreamfallNetwork, climate::Streamfall.Climate, ts::Int64, date::Date, extraction::DataFrame
)::Nothing
    if ts == 1
        timesteps = CampaspeIntegratedModel.Streamfall.sim_length(climate)
        CampaspeIntegratedModel.Streamfall.prep_state!(sn, timesteps)
    end

    inlets, outlets = CampaspeIntegratedModel.Streamfall.find_inlets_and_outlets(sn)

    for outlet in outlets
        CampaspeIntegratedModel.Streamfall.run_node!(sn, outlet, climate, ts; extraction=extraction)
    end
    return nothing
end

"""
    dam_level(sn::Streamfall.StreamfallNetwork, id::String = "406000")::Vector{Float64}

Get the dam water level time series.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `id::String` : Gauge ID of the dam node (default: "406000" for Lake Eppalock)

# Returns
- `Vector{Float64}` : Time series of dam water levels
"""
function dam_level(sn::Streamfall.StreamfallNetwork, id::String = "406000")::Vector{Float64}
    _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, id)
    return dam_node.level
end

"""
    dam_volume(sn::Streamfall.StreamfallNetwork, ts::Int64, id::String = "406000")::Float64

Get the dam storage volume at a specific timestep.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `ts::Int64` : Timestep index
- `id::String` : Gauge ID of the dam node (default: "406000" for Lake Eppalock)

# Returns
- `Float64` : Dam storage volume at timestep `ts` (ML)
"""
function dam_volume(sn::Streamfall.StreamfallNetwork, ts::Int64, id::String = "406000")::Float64
    _, dam_node = CampaspeIntegratedModel.Streamfall.get_node(sn, id)
    return dam_node.storage[ts]
end

"""
    proj_inflow(sn::Streamfall.StreamfallNetwork, id::String = "406219")::Vector{Float64}

Get the projected inflow time series from a gauge.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `id::String` : Gauge ID (default: "406219" for projected inflow gauge)

# Returns
- `Vector{Float64}` : Time series of outflow from the gauge (ML/day)
"""
function proj_inflow(sn::Streamfall.StreamfallNetwork, ts::Int64, id::String = "406219")::Float64
    _, node = CampaspeIntegratedModel.Streamfall.get_node(sn, id)
    return node.outflow[ts]
end

"""
    rochester_flow(sn::Streamfall.StreamfallNetwork, id::String = "406202")::Vector{Float64}

Get the Rochester flow time series.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `id::String` : Gauge ID (default: "406202" for Rochester gauge)

# Returns
- `Vector{Float64}` : Time series of outflow from Rochester gauge (ML/day)
"""
function rochester_flow(sn::Streamfall.StreamfallNetwork, id::String = "406202")::Vector{Float64}
    _, node = CampaspeIntegratedModel.Streamfall.get_node(sn, id)
    return node.outflow
end

function gw_levels(
    sn::Streamfall.StreamfallNetwork, ts::Int64, ids::Tuple{String}=("", "")
)::Tuple{Dict{String,Float64},Dict{String,Float64}}
    node_218 = get_node(sn, "406218")[2] ## Linked to bore 62589
    node_265 = get_node(sn, "406265")[2] ## Linked to bore 79324

    # trigger_head dict for policy model
    trigger_head = Dict(
        "62589" => calculate_head_from_depth(get_simulated_depth(node_218, ts), node_218.bore_ground_elevation),
        "79324" => calculate_head_from_depth(get_simulated_depth(node_265, ts), node_265.bore_ground_elevation)
    )

    # Fill average gw_depth depending on which bore each zone uses. Based on zone_info data
    avg_gw_depth = Dict(
        "1" => trigger_head["62589"],
        "2" => trigger_head["62589"],
        "3" => trigger_head["79324"],
        "4" => trigger_head["79324"],
        "5" => trigger_head["79324"],
        "6" => trigger_head["79324"],
        "7" => trigger_head["79324"],
        "8" => trigger_head["79324"],
        "9" => trigger_head["79324"],
        "10" => trigger_head["79324"],
        "11" => trigger_head["79324"],
        "12" => trigger_head["79324"],
    )
    return trigger_head, avg_gw_depth
end
