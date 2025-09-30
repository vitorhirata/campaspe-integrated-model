"""
    get_goulburn_allocation!(sw_state::SwState;
                            start_alloc::Dict{String, Float64} = Dict("high" => 74.0, "median" => 56.0, "low" => 48.0),
                            max_week::Dict{String, Int64} = Dict("high" => 4, "median" => 8, "low" => 11))

Determine allocation for Goulburn system based on Campaspe HR allocation status.

Sets up the Goulburn allocation function and parameters in sw_state based on whether
Campaspe is at full HR allocation (wet scenario) or below (dry scenario).

**Wet/High Allocation Years** (Campaspe HR at 100%):
- Starts at scenario-specific percentage (high: 74%, median: 56%, low: 48%)
- Increases weekly by increment = (100 - start) / max_week
- Reaches 100% by max_week (high: 4 weeks, median: 8 weeks, low: 11 weeks)

**Dry/Drought Conditions** (Campaspe HR < 100%):
- Uses linear equations based on timestep:
  - High: min(100, max(0, 1.2525x + 48.541))
  - Median: min(100, max(0, 1.4005x + 5.3381))
  - Low: min(100, max(0, 1.0116x - 3.2019))

# Arguments
- `sw_state::SwState` : surface water state structure
- `start_alloc::Dict{String, Float64}` : starting allocation percentages for each scenario
- `max_week::Dict{String, Int64}` : weeks to reach 100% allocation for each scenario

# Modifies
- `sw_state.goulburn_alloc_perc` : initial allocation percentage
- `sw_state.goulburn_increment` : weekly increment (wet scenario only)
- `sw_state.goulburn_alloc_func` : function to calculate future allocations
- `sw_state.goulburn_wet_scenario` : flag indicating wet vs dry scenario
"""
function get_goulburn_allocation!(sw_state::SwState;
        start_alloc::Dict{String, Float64} = Dict("high" => 74.0, "median" => 56.0, "low" => 48.0),
        max_week::Dict{String, Int64} = Dict("high" => 4, "median" => 8, "low" => 11)
)::Nothing
    # Validate scenario
    if !(sw_state.goulburn_alloc_scenario in ["high", "median", "low"])
        error("Invalid goulburn_alloc_scenario: $(sw_state.goulburn_alloc_scenario).")
    end

    # High allocation scenario - Campaspe allocation is at 100%
    if isapprox(sw_state.perc_entitlement["campaspe"]["HR"], 1.0)
        goulburn_alloc = start_alloc[sw_state.goulburn_alloc_scenario]
        sw_state.goulburn_increment = (100.0 - goulburn_alloc) / max_week[sw_state.goulburn_alloc_scenario]
        sw_state.goulburn_alloc_func = goulburn_wet_alloc
        sw_state.goulburn_wet_scenario = true
        sw_state.goulburn_alloc_perc = goulburn_alloc / 100.0
    else
        # Dry/drought conditions - Campaspe HR below 100%
        sw_state.goulburn_wet_scenario = false

        if sw_state.goulburn_alloc_scenario == "high"
            sw_state.goulburn_alloc_func = goulburn_dry_high
        elseif sw_state.goulburn_alloc_scenario == "median"
            sw_state.goulburn_alloc_func = goulburn_dry_median
        elseif sw_state.goulburn_alloc_scenario == "low"
            sw_state.goulburn_alloc_func = goulburn_dry_low
        end

        sw_state.goulburn_alloc_perc = max(0.0, sw_state.goulburn_alloc_func(sw_state.current_time + 1))
    end

    return nothing
end

"""
    add_goulburn_allocation!(ts::Int64, z_info::Dict, sw_state::SwState)

Add goulburn allocations for irrigation areas (only considers HR allocations).

# Arguments
- `ts` : current time step
- `z_info` : zone information dictionary
- `sw_state` : surface water state
"""
function add_goulburn_allocation!(ts::Int64, z_info::Dict, sw_state::SwState)::Nothing
    # Set goulburn_alloc_perc
    if sw_state.goulburn_wet_scenario
        sw_state.goulburn_alloc_perc = sw_state.goulburn_alloc_func(
            sw_state.goulburn_alloc_perc, sw_state.goulburn_increment
        )
    else
        sw_state.goulburn_alloc_perc = sw_state.goulburn_alloc_func(ts)
    end

    @assert sw_state.goulburn_alloc_perc < 1.0 || isapprox(sw_state.goulburn_alloc_perc, 1.0)

    # Only process irrigation areas (Rochester or Campaspe Irrigation Area)
    if irrigation_area(z_info)
        # Calculate goulburn allocation for this zone
        goulburn_alloc_for_zone = z_info["entitlement"]["goul_HR"] * sw_state.goulburn_alloc_perc

        # Calculate how much has already been allocated/used
        alloc_used = sum(z_info["ts_water_orders"]["goulburn"][1:ts])

        # Set available allocation (total allocation minus what's been used)
        z_info["avail_allocation"]["goulburn"]["HR"] = goulburn_alloc_for_zone - alloc_used
        z_info["allocated_to_date"]["goulburn"]["HR"] = goulburn_alloc_for_zone
    end

    return nothing
end

"""
    goulburn_wet_alloc(alloc_perc::Float64, increment::Float64)

Calculate Goulburn allocation for wet/high allocation years using weekly increments.
Allocation increases by fixed increment each week until reaching 100%.

# Arguments
- `alloc_perc::Float64` : current allocation percentage (0.0 to 1.0)
- `increment::Float64` : weekly increment percentage

# Returns
- `Float64` : updated allocation percentage capped at 100%
"""
function goulburn_wet_alloc(alloc_perc::Float64, increment::Float64)::Float64
    return min(1.0, max(0.0, alloc_perc + (increment / 100.0)))
end

"""
    goulburn_dry_high(ts::Int64)

Calculate Goulburn allocation for dry/drought conditions with high scenario.
Uses linear equation: min(100, max(0, 1.2525x + 48.541))

# Arguments
- `ts::Int64` : current timestep (1-based)

# Returns
- `Float64` : allocation percentage (0.0 to 1.0)
"""
function goulburn_dry_high(ts::Int64)::Float64
    return min(1.0, max(0.0, (1.2525 * ts + 48.541) / 100.0))
end

"""
    goulburn_dry_median(ts::Int64)

Calculate Goulburn allocation for dry/drought conditions with median scenario.
Uses linear equation: min(100, max(0, 1.4005x + 5.3381))

# Arguments
- `ts::Int64` : current timestep (1-based)

# Returns
- `Float64` : allocation percentage (0.0 to 1.0)
"""
function goulburn_dry_median(ts::Int64)::Float64
    return min(1.0, max(0.0, (1.4005 * ts + 5.3381) / 100.0))
end

"""
    goulburn_dry_low(ts::Int64)

Calculate Goulburn allocation for dry/drought conditions with low scenario.
Uses linear equation: min(100, max(0, 1.0116x - 3.2019))

# Arguments
- `ts::Int64` : current timestep (1-based)

# Returns
- `Float64` : allocation percentage (0.0 to 1.0)
"""
function goulburn_dry_low(ts::Int64)::Float64
    return min(1.0, max(0.0, (1.0116 * ts - 3.2019) / 100.0))
end
