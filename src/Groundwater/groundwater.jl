"""
Simple bucket groundwater model for the Campaspe catchment.

Water balance equation:
G_(t+1) = G_t + a*rainfall - b*evapotranspiration - extraction + (c - G_t)*d

Where:
- G_t: Groundwater volume at time t (ML)
- a: Rainfall recharge coefficient (ML per mm/day) - calibratable
- b: Evapotranspiration loss coefficient (ML per mm/day) - calibratable
- c: GW threshold for dam-GW exchange (ML) - calibratable
- d: Dam-GW exchange coefficient (dimensionless, 0-1) - calibratable
- e: Volume to head conversion (mAHD per ML) - calibratable
- extraction: Sum of all zone extractions (ML/day)

The exchange term (c - G_t)*d represents:
- When G_t < c (low GW): positive contribution → dam recharges groundwater
- When G_t > c (high GW): negative contribution → groundwater feeds dam
"""

"""
    GWModel

Simple bucket groundwater model with 5 calibratable parameters.

# Fields
- `a::Float64` : Rainfall recharge coefficient (ML per mm/day). Bounds: [0.1, 200.0]
- `b::Float64` : Evapotranspiration loss coefficient (ML per mm/day). Bounds: [0.01, 50.0]
- `c::Float64` : GW threshold for exchange (ML). Bounds: [100000.0, 2000000.0]
- `d::Float64` : Dam-GW exchange coefficient. Bounds: [1e-6, 0.1]
- `e::Float64` : Volume to head conversion (mAHD per ML). Bounds: [1e-6, 1e-3]
- `bore_ground_elevation::Float64` : Bore ground elevation (mAHD). Default: 100.0
- `G::Float64` : Current groundwater volume (ML). Initialized from observed bore depth
- `storage::Vector{Float64}` : Time series of groundwater volume (ML)
- `heads::Vector{Float64}` : Time series of groundwater head (mAHD)
- `depths::Vector{Float64}` : Time series of depth below surface (m)

# Example
```julia
# Initialize from observed bore depth of 11.1 m with bore elevation 100.0 mAHD
initial_head = 100.0 - 11.1  # = 88.9 mAHD
gw_model = GWModel(a=2.0, b=0.5, c=500000.0, d=0.05, e=0.0002, bore_ground_elevation=100.0)
```
"""

Base.@kwdef mutable struct GWModel
    # Calibratable parameters
    a::Float64 = 80.92069           # Rainfall recharge coefficient (ML per mm/day)
    b::Float64 = 35.164271           # Evapotranspiration loss coefficient (ML per mm/day)
    c::Float64 = 1.6477810e6         # GW threshold for exchange (ML)
    d::Float64 = 0.00018938             # Dam-GW exchange coefficient
    e::Float64 = 5.02934582e-5             # Volume to head conversion (mAHD per ML)

    # Reference elevation
    bore_ground_elevation::Float64 = 100.0  # Bore ground elevation (mAHD)

    # State - initialized from observed bore depth of 11.1 m
    G::Float64 = (bore_ground_elevation - 11.1) / e  # Back-calculate from observed depth

    # History (for analysis)
    storage::Vector{Float64} = [G]  # Time series of volume (ML)
    heads::Vector{Float64} = [G * e]  # Time series of head (mAHD)
    depths::Vector{Float64} = [bore_ground_elevation - G * e]  # Time series of depth below surface (m)
end


"""
    update_gw!(
        model::GWModel,
        rainfall::Float64,
        evap::Float64,
        extraction::Dict{String,Float64}
    )::Float64

Update the groundwater model for one timestep.

# Arguments
- `model::GWModel` : The groundwater model to update
- `rainfall::Float64` : Rainfall for this timestep (mm/day)
- `evap::Float64` : Evapotranspiration for this timestep (mm/day)
- `extraction::Dict{String,Float64}` : Groundwater extractions by zone (ML/day). Keys are zone IDs ("1", "2", etc.)

# Returns
- `Float64` : Updated groundwater volume (ML)

# Example
```julia
gw_model = GWModel()
extraction = Dict("1" => 10.0, "2" => 15.0, "3" => 5.0)
new_volume = update_gw!(gw_model, 2.5, 3.0, extraction)
```
"""
function update_gw!(model::GWModel, rainfall::Float64, evap::Float64, extraction::Float64)::Float64
    # Water balance equation: G_(t+1) = G_t + a*rainfall - b*evap - extraction + (c - G_t)*d
    G_new = model.G + model.a * rainfall - model.b * evap - extraction + (model.c - model.G) * model.d

    # Prevent negative volume
    model.G = max(0.0, G_new)

    # Calculate head and depth
    head = model.G * model.e
    depth = model.bore_ground_elevation - head

    # Store in history
    push!(model.storage, model.G)
    push!(model.heads, head)
    push!(model.depths, depth)

    return model.G
end
function update_gw!(model::GWModel, climate::Streamfall.Climate, extraction::Dict{String,Float64}, ts::Int64)::Float64
    # Sum all zone extractions
    total_extraction = sum(values(extraction))
    rainfall = climate.climate_data[ts,"406000_rain"]
    evap = climate.climate_data[ts,"406000_evap"]

    return update_gw!(model, rainfall, evap, total_extraction)
end


"""
    gw_levels(model::GWModel)::Tuple{Dict{String,Float64}, Dict{String,Float64}}

Get groundwater levels for trigger heads and zone-averaged depths.

Returns the same head value for all bores and zones (single bucket model).

# Arguments
- `model::GWModel` : The groundwater model

# Returns
- `Tuple{Dict{String,Float64}, Dict{String,Float64}}` :
  - First dict: trigger_head for bores "62589" and "79324" - Groundwater head in mAHD
  - Second dict: avg_gw_depth for zones "1" through "12" - Depth below ground surface in meters (positive is below ground)

# Example
```julia
gw_model = GWModel(G=889000.0, e=0.0001, bore_ground_elevation=100.0)
trigger_head, avg_gw_depth = gw_levels(gw_model)
# trigger_head = Dict("62589" => 88.9, "79324" => 88.9)  # mAHD
# avg_gw_depth = Dict("1" => 11.1, ..., "12" => 11.1)    # m below surface
```
"""
function gw_levels(model::GWModel)::Tuple{Dict{String,Float64}, Dict{String,Float64}}
    head = model.G * model.e
    depth = model.bore_ground_elevation - head

    # Same head for both trigger bores (mAHD)
    trigger_head = Dict("62589" => head, "79324" => head)

    # Same depth for all zones (m below surface)
    zones = string.(collect(1:12))
    avg_gw_depth = Dict(zip(zones, fill(depth, length(zones))))

    return trigger_head, avg_gw_depth
end


"""
    get_parameter_bounds()::Dict{Symbol, Tuple{Float64, Float64}}

Get suggested parameter bounds for calibration.

# Returns
- `Dict{Symbol, Tuple{Float64, Float64}}` : Dictionary mapping parameter names to (min, max) bounds

# Example
```julia
bounds = get_parameter_bounds()
# Dict(:a => (0.1, 200.0), :b => (0.01, 50.0), ...)
```
"""
function get_parameter_bounds()::Dict{Symbol, Tuple{Float64, Float64}}
    return Dict(
        :a => (0.1, 200.0),           # Rainfall recharge coefficient (ML per mm/day)
        :b => (0.01, 50.0),           # Evapotranspiration loss coefficient (ML per mm/day)
        :c => (100000.0, 2000000.0),  # GW threshold for exchange (ML)
        :d => (1e-6, 0.1),            # Dam-GW exchange coefficient (dimensionless)
        :e => (1e-6, 1e-3)            # Volume to head conversion (mAHD per ML)
    )
end
