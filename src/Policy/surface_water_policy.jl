"""
    update_surface_water(sw_state::SwState, global_timestep::Int64, date::Date, f_orders::Dict, rochester_flow::Vector{Float64}, dam_vol::Float64, rolling_dam_level::Float64, release_timeframe::Int64)::Union{Float64, Bool}

Updates surface water levels based on extraction orders.

# Arguments
- `sw_state` : struct with surface water state.
- `date` : date of current time step.
- `global_timestep` : global timestep of the model.
- `f_orders` : dictionary with farm irrigation order for each zone. For example, {zone name: farm irrigation order for each zone}.
- `rochester_flow` : time series of flow at Rochester, used in environmental policy model.
- `dam_vol` : dam volume.
- `rolling_dam_level` : 3 year rolling average dam level.
- `release_timeframe` : timestep over which to release water.

# Returns
False if model have not run and dam release if model ran.
"""
function update_surface_water(
        sw_state::SwState, date::Date, global_timestep::Int64, f_orders::Dict,
        rochester_flow::Vector{Float64}, dam_vol::Float64, rolling_dam_level::Float64, release_timeframe::Int64
)::Union{Float64, Bool}
    if !check_run(sw_state, date)
        return false
    end

    # Record farm orders for the campaspe
    for (key, value) in f_orders
        sw_state.zone_info[key]["ts_water_orders"]["campaspe"][sw_state.current_time] = value
    end
    calc_allocation(sw_state, f_orders, dam_vol, rolling_dam_level)

    other_orders = calc_other_orders!(sw_state)
    farm_orders = sum(values(f_orders))

    # Get environmental allocation
    env_hr = env_lr = 0.0
    env_zones = filter(((_, v),) -> v["zone_type"] == "environmental", sw_state.zone_info)
    for zones in values(env_zones)
        env_hr += zones["avail_allocation"]["campaspe"]["HR"] + zones["avail_allocation"]["goulburn"]["HR"]
        env_lr += zones["avail_allocation"]["campaspe"]["LR"] + zones["avail_allocation"]["goulburn"]["LR"]
    end

    # Set environmental allocation
    sw_state.avail_allocation["environment"]["HR"] = env_hr
    sw_state.avail_allocation["environment"]["LR"] = env_lr

    # Determine environmental water orders
    env_order = run_model!(sw_state.env_state, global_timestep, date, rochester_flow,
                          other_orders + farm_orders, env_hr, env_lr, dam_vol)
    total_other = other_orders + env_order
    sw_state.total_water_orders += total_other
    @assert env_order >= 0 && other_orders >= 0

    # Distribute environmental water orders across all environmental zones
    leftover = env_order
    lr_ordered = 0.0
    hr_ordered = 0.0
    for (z_id, z_info) in env_zones
        avail_hr = z_info["avail_allocation"]["campaspe"]["HR"] + z_info["avail_allocation"]["goulburn"]["HR"]
        avail_lr = z_info["avail_allocation"]["campaspe"]["LR"] + z_info["avail_allocation"]["goulburn"]["LR"]
        z_env_lr, z_env_hr, leftover = prop_subtract(avail_lr, avail_hr, leftover)

        @assert isapprox(leftover, 0.0) || leftover <= 0.0 || isapprox(z_env_lr + z_env_hr, 0.0)

        ordered_lr = isapprox(z_env_lr, 0.0) ? avail_lr : avail_lr - z_env_lr
        ordered_hr = isapprox(z_env_hr, 0.0) ? avail_hr : avail_hr - z_env_hr

        @assert (ordered_lr + ordered_hr >= 0.0) || isapprox(ordered_lr + ordered_hr, 0.0)

        z_info["ts_water_orders"]["campaspe"][sw_state.current_time] = ordered_lr + ordered_hr

        # Update zone available allocation for campaspe system
        z_info["avail_allocation"]["campaspe"]["HR"] = z_env_hr
        z_info["avail_allocation"]["campaspe"]["LR"] = z_env_lr

        # Update carryover state
        z_info["carryover_state"]["LR"] = max(0.0, z_info["carryover_state"]["LR"] - z_env_lr)
        z_info["carryover_state"]["HR"] = max(0.0, z_info["carryover_state"]["HR"] - z_env_hr)

        # Recalculate total amount of allocations available
        lr_ordered += ordered_lr
        hr_ordered += ordered_hr

        if isapprox(leftover, 0.0)
            break
        end
    end

    @assert isapprox(leftover, 0.0)
    @assert isapprox(lr_ordered + hr_ordered, env_order)

    # Update global campaspe allocation
    sw_state.avail_allocation["campaspe"]["HR"] -= hr_ordered
    sw_state.avail_allocation["campaspe"]["LR"] -= lr_ordered

    update_catchment_stats!(sw_state)

    # Aggregate by regulation zone (unregulated areas get ignored)
    regzone_orders = Dict{String, Float64}()
    for (z_id, z_info) in sw_state.zone_info
        reg_zone = z_info["regulation_zone"]
        regzone_orders[reg_zone] = get(regzone_orders, reg_zone, 0.0)
        regzone_orders[reg_zone] += z_info["ts_water_orders"]["campaspe"][sw_state.current_time]
    end

    @assert sum(values(regzone_orders)) >= 0.0

    daily_dam_release = dam_release(sw_state, date, regzone_orders, total_other,
                                     sw_state.usable_dam_vol,
                                     sw_state.proj_inflow[sw_state.current_time],
                                     0.0,  # siphon inflows not taken into account (set to 0.0)
                                     release_timeframe)

    # Logging would go here if necessary

    # Handle end of season
    if date == sw_state.season_end
        calc_carryover!(sw_state, sw_state.current_year, sw_state.current_time, date)

        sw_state.current_time = 1
        sw_state.env_state.season_order = 0.0
        sw_state.current_year += 1
        sw_state.next_run = nothing
        sw_state.season_end = Date(1900, 4, 30)  # Reset to template (year ignored)
    end

    return daily_dam_release
end

"""
    calc_carryover!(sw_state::SwState, year::Int64, ts::Int64, date::Date)

Calculate carryover at end of season. Runs in the last time step for each zone.

Carryover is calculated as 95% of unused water allocation, distributed first to LR
entitlement up to its limit, then to HR entitlement.

# Arguments
- `sw_state` : surface water state structure
- `year` : current year count in model run
- `ts` : current time step
- `date` : current date
"""
function calc_carryover!(sw_state::SwState, year::Int64, ts::Int64, date::Date)
    total_co = 0.0

    for (zone_id, z_info) in sw_state.zone_info
        # Determine entitlement based on zone type
        if haskey(z_info["entitlement"], "camp_HR")
            E_H = z_info["entitlement"]["camp_HR"]
            E_L = z_info["entitlement"]["camp_LR"]
        else
            E_H = z_info["entitlement"]["HR"]
            E_L = z_info["entitlement"]["LR"]
        end

        # Skip zones with zero entitlements
        if (E_H == 0.0) && (E_L == 0.0)
            continue
        end

        # Special case: skip environmental zones with no carryover
        if haskey(z_info, "name") && z_info["name"] == "Campaspe River Environment (no c/o or trade)"
            continue
        end

        # Calculate unused volume (available allocation for campaspe system)
        vol_unused = z_info["avail_allocation"]["campaspe"]["HR"] + z_info["avail_allocation"]["campaspe"]["LR"]

        # Cap to 95% of unused volume
        capped_total = 0.95 * vol_unused

        # Distribute carryover: LR first, then HR
        if capped_total <= E_L
            lr_carryover = capped_total
            hr_carryover = 0.0
        else
            lr_carryover = E_L
            hr_carryover = capped_total - E_L
        end

        @assert hr_carryover >= 0.0 && lr_carryover >= 0.0

        # Set next year's carryover
        z_info["yearly_carryover"]["HR"][year + 1] = hr_carryover
        z_info["yearly_carryover"]["LR"][year + 1] = lr_carryover

        # Update carryover state
        z_info["carryover_state"]["HR"] = hr_carryover
        z_info["carryover_state"]["LR"] = lr_carryover

        total_co += hr_carryover + lr_carryover
    end

    # Update catchment-level carryover tracking
    sw_state.yearly_carryover[year + 1] = total_co
    sw_state.carryover_state[year + 1] = total_co

    return nothing
end

"""
    dam_release(sw_state::SwState, date::Date, water_orders::Dict, other_releases::Float64,
                dam_vol::Float64, eppalock_inflow::Float64, siphon_inflow::Float64,
                release_timeframe::Int64; meps::Union{Float64,Nothing}=nothing,
                mcs::Union{Float64,Nothing}=nothing, epp_loss::Float64=0.04,
                weir_loss::Float64=0.1, goornong_daily_ML::Float64=1.178)::Float64

Calculate dam releases for a given time step.

Returns daily amount of water to be released over the next time step.

# Arguments
- `sw_state::SwState` : surface water state structure
- `date::Date` : current date of model run
- `water_orders::Dict` : dictionary of water orders with zone id as keys (expects 'Regulated 4A' and 'Regulated 4C')
- `other_releases::Float64` : other water releases in ML (will be converted to daily values)
- `dam_vol::Float64` : current dam volume in ML
- `eppalock_inflow::Float64` : inflow to Eppalock for the time step (will be converted to daily values)
- `siphon_inflow::Float64` : inflow to Campaspe Siphon (Rochester gauge) for the time step
- `release_timeframe::Int64` : time frame in days over which to release water

# Keyword Arguments
- `meps::Union{Float64,Nothing}` : minimum flow for Eppalock (if nothing, will determine from lookup table)
- `mcs::Union{Float64,Nothing}` : minimum flow for Siphon (if nothing, will determine from lookup table)
- `epp_loss::Float64` : seepage loss from Eppalock (default: 0.04)
- `weir_loss::Float64` : operational loss at Campaspe Weir (default: 0.1)
- `goornong_daily_ML::Float64` : constant release to supply Goornoong (default: 1.178 ML/day)

# Returns
- `Float64` : daily release in ML

# Notes
Minimum passing flows (MEPS and MCS) are based on DEPI (2013).
"""
function dam_release(sw_state::SwState, date::Date, water_orders::Dict, other_releases::Float64,
                     dam_vol::Float64, eppalock_inflow::Float64, siphon_inflow::Float64,
                     release_timeframe::Int64; meps::Union{Float64,Nothing}=nothing,
                     mcs::Union{Float64,Nothing}=nothing, epp_loss::Float64=0.04,
                     weir_loss::Float64=0.1, goornong_daily_ML::Float64=1.178
)::Float64

    # Convert water_orders to daily values (create copy and divide all values)
    daily_water_orders = Dict(zone => order / release_timeframe for (zone, order) in water_orders)

    # Calculate transmission and operational losses
    eppalock_trans_loss = daily_water_orders["Regulated 4A"] * epp_loss
    weir_op_loss = daily_water_orders["Regulated 4C"] * weir_loss

    # Determine minimum passing flows if not provided
    if isnothing(meps) && isnothing(mcs)
        if dam_vol <= 150000.0
            meps = 10.0
            mcs = 35.0
        elseif dam_vol <= 200000.0
            meps = 50.0
            mcs = 35.0
        elseif dam_vol <= 250000.0
            meps = 80.0
            mcs = 70.0
        else  # dam_vol > 250000.0
            if month(date) in [1, 3, 5, 6, 12]
                meps = 90.0
            elseif month(date) in [2, 4]
                meps = 80.0
            elseif month(date) in [7, 11]
                meps = 150.0
            elseif month(date) in [8, 9, 10]
                meps = 200.0
            end
            mcs = 70.0
        end

        # Cap to actual inflows
        meps = min(meps, eppalock_inflow / release_timeframe)
        mcs = min(mcs, siphon_inflow / release_timeframe)
    end

    meps_mcs_release = meps + mcs

    # Check if there is enough water for MEPS and MCS from Eppalock Reservoir allocation
    z_info = sw_state.zone_info["Eppalock Reservoir"]
    avail_water = z_info["avail_allocation"]["campaspe"]["HR"] + z_info["avail_allocation"]["campaspe"]["LR"]

    full_operational_release = false
    if meps_mcs_release >= avail_water
        # Release both MEPS and MCS
        full_operational_release = true
    elseif meps > avail_water
        # Only enough water for MEPS
        full_operational_release = false
        meps_mcs_release = meps
    end

    if !full_operational_release && (mcs >= avail_water)
        # Only enough water for MCS
        meps_mcs_release = mcs
    end

    # Calculate total dam release
    dam_release_val = (sum(values(daily_water_orders)) + (other_releases / release_timeframe) +
                       eppalock_trans_loss + weir_op_loss + goornong_daily_ML +
                       meps_mcs_release)

    if dam_release_val < 0.0
        @warn "Negative dam release detected! Set to 0.0"
        dam_release_val = 0.0
    end

    return dam_release_val
end

"""
    check_run(sw_state::SwState, date::Date)

Check if surface water policy model should run and updates times.

# Arguments
- `sw_state` : struct with surface water state.
- `date` : date of current time step.

# Returns
Boolean defining if the model should run.
"""
function check_run(sw_state::SwState, date::Date)
    if sw_state.next_run == nothing
        if month(date) == month(sw_state.season_start) && day(date) == day(sw_state.season_start)
            sw_state.season_end = Date(year(date) + 1, month(sw_state.season_end), day(sw_state.season_end))
            sw_state.first_release = Date(year(date), month(sw_state.first_release), day(sw_state.first_release))
            sw_state.next_run = date + sw_state.timestep

            # Reset environmental water order counter
            sw_state.env_state.water_order = 0.0
            sw_state.env_state.season_order = 0.0

            return true
        else
            return false
        end
    else
        if date == sw_state.next_run
            sw_state.next_run += sw_state.timestep
            sw_state.current_time += 1
            return true
        elseif environmental_order_dates(date, sw_state.season_end)
            sw_state.current_time += 1
            return true
        else
            return false
        end
    end
end

function environmental_order_dates(date::Date, season_end::Date)::Bool
    return (
        (month(date) in [2, 5] && day(date) == 1) ||
        (month(date) == 3 && day(date) == 16) ||
        (month(date) in [8, 11] && day(date) == 25) ||
        (month(date) == 7 && day(date) == 1) ||
        (date == season_end)
    )
end

"""
    get_dam_extraction(sw_state::SwState, date::Date)::Float64

Get dam extraction volume for a given date from DataFrame or return constant value.
If the date is not found in the DataFrame, returns 0.0.

# Arguments
- `sw_state::SwState` : surface water state structure
- `date::Date` : date for which to get extraction volume

# Returns
- `Float64` : extraction volume in ML for the given date
"""
function get_dam_extraction(sw_state::SwState, date::Date)::Float64
    # Try to find extraction for this date
    if date in sw_state.dam_ext.Time
        row_idx = findfirst(==(date), sw_state.dam_ext.Date)
        return sw_state.dam_ext[row_idx, "Extraction (ML)"]
    else
        return 0.0
    end
end
