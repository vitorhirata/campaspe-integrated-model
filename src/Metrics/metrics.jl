"""
    recreational_index(dam_level::Vector{Float64}, dam_capacity::Float64=204.0, threshold::Float64=0.3)::Vector{Float64}

Calculate recreational index for Lake Eppalock based on dam level.
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
