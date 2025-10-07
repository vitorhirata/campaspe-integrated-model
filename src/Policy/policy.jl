include("gw_state.jl")
include("gw_update.jl")
include("environment.jl")
include("sw_state.jl")
include("sw_allocation.jl")
include("sw_goulburn_allocation.jl")
include("sw_update.jl")
include("policy_state.jl")

"""
    run_policy(policy_state::PolicyState, ts::Int64, dt::Date, f_orders::Dict, gw_orders::Dict{String, Float64}, dam_vol::Float64, dam_rolling_level::Float64, rochester_flow::Vector{Float64}, proj_inflow::Float64, gw_level::Dict{String, Float64}, release_timeframe::Int64)::Tuple{Union{Float64, Bool}, Dict{String, Any}}

Run policy models.

# Arguments
- `policy_state` : PolicyState struct containing surface water and groundwater state.
- `ts` : int, time step of integrated model.
- `dt` : datetime, datetime object of current time step.
- `f_orders` : dict, farm surface water orders (zone_id as key), volume in ML.
- `gw_orders` : dict, groundwater orders, volume in ML.
- `dam_vol` : float, volume of dam at current time step.
- `dam_rolling_level` : float, 3-year rolling average of dam level.
- `rochester_flow` : vector, volume inflow from rochester.
- `proj_inflow` : float, volume projected inflow for the timestep.
- `gw_level` : dict, groundwater levels at each gauge.
- `release_timeframe` : int, days over which to release water from dam.

# Returns
Tuple of (daily dam release in ML, dict of farm allocations)
"""
function update_policy(
    policy_state::PolicyState,
    ts::Int64,
    dt::Date,
    f_orders::Dict{String, Float64},
    gw_orders::Dict{String, Float64},
    dam_vol::Float64,
    dam_rolling_level::Float64,
    rochester_flow::Vector{Float64},
    proj_inflow::Float64,
    gw_level::Dict{String, Float64},
    release_timeframe::Int64
)::Tuple{Union{Float64, Bool}, Dict{String, Any}}
    # Set projected inflow for current timestep
    policy_state.sw_state.proj_inflow[policy_state.sw_state.ts] = proj_inflow

    # Groundwater policy inputs - GW model requires percentage of HR entitlement for Campaspe
    policy_state.gw_state.sw_perc_entitlement = policy_state.sw_state.perc_entitlement["campaspe"]["HR"]

    # Run surface water policy model
    daily_dam_release = update_surface_water(
        policy_state.sw_state, dt, ts, f_orders, rochester_flow, dam_vol, dam_rolling_level, release_timeframe
    )

    # Run groundwater policy model
    update_groundwater(policy_state.gw_state, dt, gw_orders, gw_level)

    # Get available farm allocations
    farm_allocations = get_avail_farm_allocations(policy_state)

    return daily_dam_release, farm_allocations
end

"""
    get_avail_farm_allocations(policy_state::PolicyState)::Dict{String, Any}

Get available farm allocations from surface water and groundwater.

# Arguments
- `policy_state` : PolicyState struct containing surface water and groundwater state.

# Returns
Dict of farm allocations by zone_id with SW and GW allocations.
"""
function get_avail_farm_allocations(policy_state::PolicyState)::Dict{String, Any}
    allocations = Dict{String, Any}()

    for (z, z_info) in policy_state.sw_state.zone_info
        if z_info["zone_type"] == "farm"
            # Get groundwater data from DataFrame
            gw_row_idx = findfirst(==(z_info["zone_id"]), policy_state.gw_state.zone_info.ZoneID)

            if !isnothing(gw_row_idx)
                gw_alloc = policy_state.gw_state.zone_info[gw_row_idx, "gw_alloc"]
                gw_used = policy_state.gw_state.zone_info[gw_row_idx, "gw_used"]
                gw_ent = policy_state.gw_state.zone_info[gw_row_idx, "gw_Ent"]

                # Assert allocation cannot be negative. TODO: fix input ent/alloc so that this problem don't happen
                if !((gw_alloc - gw_used) > 0.0 || isapprox(gw_alloc - gw_used, 0.0))
                    gw_used = gw_alloc
                end
                @assert (gw_alloc - gw_used) > 0.0 || isapprox(gw_alloc - gw_used, 0.0)

                # Calculate available groundwater allocation
                gw_alloc = min((gw_ent * policy_state.gw_cap) - gw_used, gw_alloc - gw_used)
                gw_alloc = isapprox(0.0, gw_alloc) ? 0.0 : gw_alloc

                # Get surface water allocations from campaspe and goulburn
                camp_hr = z_info["avail_allocation"]["campaspe"]["HR"]
                camp_lr = z_info["avail_allocation"]["campaspe"]["LR"]
                goul_hr = z_info["avail_allocation"]["goulburn"]["HR"]
                goul_lr = z_info["avail_allocation"]["goulburn"]["LR"]

                # Store allocations for this zone
                allocations[z_info["zone_id"]] = Dict{String, Any}(
                    "SW" => Dict{String, Float64}(
                        "HR" => (camp_hr + goul_hr) * policy_state.sw_cap,
                        "LR" => (camp_lr + goul_lr) * policy_state.sw_cap
                    ),
                    "GW" => Dict{String, Float64}("HR" => gw_alloc, "LR" => 0.0)
                )
            end
        end
    end

    return allocations
end


"""
    get_rolling_dam_level(dt::Date, years::Int64, dam_levels::Vector{Float64}, datetimes::Vector{Date})::Float64

Calculate the average of dam levels over a specified number of years.
Computes the rolling average for the previous `years` from current datetime (right-aligned).

# Arguments
- `dt::Date` : current datetime
- `years::Int64` : years over which to generate a rolling average (right aligned)
- `dam_levels::Vector{Float64}` : daily dam levels
- `datetimes::Vector{Date}` : datetimes that represent model run time frame

# Returns
- `Float64` : rolling average of dam level
"""
function get_rolling_dam_level(dt::Date, years::Int64, dam_levels::Vector{Float64}, datetimes::Vector{Date})::Float64
    # Calculate start date by subtracting years from current date
    start_date = dt - Dates.Year(years)

    # Find indices in the date range [start_date, dt]
    window_indices = findall(d -> start_date <= d <= dt, datetimes)

    # Extract dam levels for this window
    data = dam_levels[window_indices]

    # Return mean of dam levels in the window
    return mean(data)
end
