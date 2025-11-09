using Interpolations

"""
    recreational_index(dam_level::Vector{Float64}, dam_capacity::Float64=204.0, threshold::Float64=0.3)::Vector{Float64}

Calculate recreational index for Lake Eppalock based on dam level using threshold method.
Returns binary index (0 or 1) indicating whether recreation conditions are met.

# Arguments
- `dam_level::Vector{Float64}` : Time series of dam levels
- `dam_capacity::Float64` : Dam capacity for normalization (default: 204.0)
- `threshold::Float64` : Normalized dam level threshold (default: 0.3, i.e., 30% of capacity)

# Returns
- `Vector{Float64}` : Binary index (0 or 1) for each timestep

# Example
```julia
dam_level = [50.0, 100.0, 150.0, 200.0]
rec_index = recreational_index(dam_level)  # Returns [0.0, 0.0, 1.0, 1.0] with default threshold 0.3
```
"""
function recreational_index(
    dam_level::Vector{Float64}; dam_capacity::Float64=204.0, threshold::Float64=0.3
)::Vector{Float64}
    normalized_level = dam_level ./ dam_capacity

    # Apply threshold: >= threshold returns 1.0, < threshold returns 0.0
    rec_index = Float64.(normalized_level .>= threshold)

    return rec_index
end

"""
    recreational_index(dam_level::Vector{Float64}, recreation_curve::DataFrame; dam_capacity::Float64=204.0)::Vector{Float64}

Calculate recreational index for Lake Eppalock based on dam level using curve interpolation method.
Returns continuous index (0 to 1) based on weighted average of yacht and caravan park recreation curves.

# Arguments
- `dam_level::Vector{Float64}` : Time series of dam levels
- `recreation_curve::DataFrame` : DataFrame with interpolation data
- `dam_capacity::Float64` : Dam capacity for normalization (default: 204.0)

# Returns
- `Vector{Float64}` : Continuous recreation index (0 to 1) for each timestep

# Example
```julia
using CSV, DataFrames
recreation_curve = CSV.read("data/policy/recreation_curve.csv", DataFrame)
dam_level = [50.0, 100.0, 150.0, 200.0]
rec_index = recreational_index(dam_level, recreation_curve; dam_capacity=204.0)
```
"""
function recreational_index(
    dam_level::Vector{Float64}, recreation_curve::DataFrame; dam_capacity::Float64=204.0
)::Vector{Float64}
    normalized_level = dam_level ./ dam_capacity
    @assert all(0.0 .<= normalized_level .<= 1.0)

    # Extract coordinates for each recreation type
    yacht_mask = .!ismissing.(recreation_curve.Yachting)
    yacht_x = recreation_curve.Dam_Capacity[yacht_mask]
    yacht_y = recreation_curve.Yachting[yacht_mask]

    cpark_mask = .!ismissing.(recreation_curve.Caravan_park)
    cpark_x = recreation_curve.Dam_Capacity[cpark_mask]
    cpark_y = recreation_curve.Caravan_park[cpark_mask]

    # Interpolate indices for each recreation type
    yacht_interp = LinearInterpolation(yacht_x, yacht_y)
    cpark_interp = LinearInterpolation(cpark_x, cpark_y)

    # Calculate interpolated values
    yacht_index = yacht_interp.(normalized_level)
    cpark_index = cpark_interp.(normalized_level)

    # Weighted average: 50% yacht, 50% caravan park
    rec_index = 0.5 .* yacht_index .+ 0.5 .* cpark_index

    return rec_index
end
