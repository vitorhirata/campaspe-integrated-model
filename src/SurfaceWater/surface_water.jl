using Streamfall

"""
    update_surface_water(sn::Streamfall.StreamfallNetwork, climate::Streamfall.Climate, ts::Int64, date::Date, extraction::DataFrame, exchange::Dict{String, Float64})::Nothing

Update and run the surface water model for a single timestep.

# Arguments
- `sn::Streamfall.StreamfallNetwork` : Surface water network
- `climate::Streamfall.Climate` : Climate data (rainfall and evaporation)
- `ts::Int64` : Current timestep index
- `date::Date` : Current date
- `extraction::DataFrame` : DataFrame containing water extractions and releases
- `exchange::Dict{String, Float64}` : Groundwater-surface water exchange fluxes by gauge ID

# Returns
- `Nothing`
"""
function update_surface_water(
    sn::Streamfall.StreamfallNetwork, climate::Streamfall.Climate, ts::Int64, date::Date,
    extraction::DataFrame, exchange::DataFrame
)::Nothing
    if ts == 1
        timesteps = CampaspeIntegratedModel.Streamfall.sim_length(climate)
        CampaspeIntegratedModel.Streamfall.prep_state!(sn, timesteps)
    end

    inlets, outlets = CampaspeIntegratedModel.Streamfall.find_inlets_and_outlets(sn)

    for outlet in outlets
        CampaspeIntegratedModel.Streamfall.run_node!(sn, outlet, climate, ts; extraction=extraction, exchange=exchange)
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
