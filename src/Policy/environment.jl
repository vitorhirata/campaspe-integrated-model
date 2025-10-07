@with_kw mutable struct EnvironmentState
    season_order::Float64 = 0.0
    water_order::Float64 = 0.0
    fixed_annual_losses::Float64
    hr_entitlement::Float64
    lr_entitlement::Float64
end

"""
    EnvironmentState(hr_entitlement::Float64, lr_entitlement::Float64; fixed_annual_losses::Float64=1656.0)

Constructor for EnvironmentState.

# Arguments
- `hr_entitlement` : high reliability entitlement in ML
- `lr_entitlement` : low reliability entitlement in ML
- `fixed_annual_losses` : fixed annual losses in ML (default: 1656.0)

# Notes
HR entitlement is adjusted by subtracting fixed_annual_losses.
"""
function EnvironmentState(hr_entitlement::Float64, lr_entitlement::Float64; fixed_annual_losses::Float64=1656.0)
    return EnvironmentState(
        fixed_annual_losses=fixed_annual_losses,
        hr_entitlement=hr_entitlement - fixed_annual_losses,
        lr_entitlement=lr_entitlement
    )
end

"""
    run_model!(env_state::EnvironmentState, ts::Int64, date::Date, rochester_flow::Vector{Float64},
               other_releases::Float64, avail_hr::Float64, avail_lr::Float64, dam_vol::Float64)::Float64

Run environmental policy model to determine water orders.

# Arguments
- `env_state` : environmental state structure
- `ts` : global time step (1-based)
- `date` : current date
- `rochester_flow` : time series of flow at Rochester from SW Model
- `other_releases` : other water releases (ML) for current time step
- `avail_hr` : available High Reliability allocation in ML
- `avail_lr` : available Low Reliability allocation in ML
- `dam_vol` : volume of water in dam in ML

# Returns
- `Float64` : water order in ML for the time step
"""
function run_model!(env_state::EnvironmentState, ts::Int64, date::Date, rochester_flow::Vector{Float64},
                   other_releases::Float64, avail_hr::Float64, avail_lr::Float64, dam_vol::Float64)::Float64

    env_state.water_order = 0.0  # default value when low flow objectives are met

    # 120 ML/d is the max amount to supplement
    winterlow_deficit = max(0.0, 120.0 - rochester_flow[ts] - other_releases)
    avail_env_water = avail_hr + avail_lr

    # If it is the 1 July
    if month(date) == 7 && day(date) == 1
        env_state.water_order = winterlow_deficit
    else
        # For all years Jul-Nov, and following Jun
        if (month(date) in [6, 7, 8, 9, 10, 11]) && winterlow_deficit > 0.0
            # If order is less than cid losses
            if env_state.season_order <= env_state.fixed_annual_losses
                env_state.water_order = winterlow_deficit
            else
                env_state.water_order = min(winterlow_deficit, avail_env_water)
            end
        end
    end

    # Determine climate situation based on dam volume
    if dam_vol <= 200000.0
        climate_situation = "dry"
    elseif dam_vol <= 250000.0
        climate_situation = "median"
    else  # dam_vol > 250000.0
        climate_situation = "wet"
    end

    # If rochester flow does not meet a specified flow/day target for a consecutive amount
    # of time, before a specified date, then release a volume of water required to meet the
    # targeted flow/day, but only if this allocation is available
    if month(date) == 8 && day(date) == 25
        dt_threshold = Date(year(date), 6, 30) # End of jun
        add_release_on_dt_check!(env_state, ts, date, rochester_flow, dt_threshold, avail_env_water,
                                other_releases, 4, 1500.0)
    elseif month(date) == 11 && day(date) == 25
        # Filter August release
        dt_threshold = Date(year(date), 8, 31) # End of aug
        add_release_on_dt_check!(env_state, ts, date, rochester_flow, dt_threshold, avail_env_water,
                                other_releases, 4, 1500.0)
    elseif month(date) in [2, 3, 4, 5] # Month between Feb and May
        if month(date) == 2 && day(date) == 1
            dt_threshold = Date(year(date) - 1, 12, 31) # End of jan
            add_release_on_dt_check!(env_state, ts, date, rochester_flow, dt_threshold, avail_env_water,
                                    other_releases, 6, 100.0)
        elseif month(date) == 3 && day(date) == 16
            early_feb = Date(year(date), 2, 1)
            add_release_on_dt_check!(env_state, ts, date, rochester_flow, early_feb, avail_env_water,
                                    other_releases, 6, 100.0)
        elseif month(date) == 5 && day(date) == 1
            mid_march = Date(year(date), 3, 16)
            add_release_on_dt_check!(env_state, ts, date, rochester_flow, mid_march, avail_env_water,
                                    other_releases, 6, 100.0)
        end

        if climate_situation == "wet"
            # This should only run if any more allocations exist...
            dt_threshold = Date(year(date), 5, 1) # Begin may
            add_release_on_dt_check!(env_state, ts, date, rochester_flow, dt_threshold, avail_env_water,
                                    other_releases, 4, 1500.0)
        end
    end

    # Cap to available environmental water
    env_state.water_order = max(0.0, min(env_state.water_order, avail_env_water))
    env_state.season_order += env_state.water_order

    @assert (env_state.water_order <= avail_env_water) || isapprox(env_state.water_order, avail_env_water)

    return env_state.water_order
end

"""
    add_release_on_dt_check!(env_state::EnvironmentState, ts::Int64, date::Date,
                            rochester_flow::Vector{Float64}, dt_threshold::Date,
                            avail_alloc::Float64, other_releases::Float64,
                            block_limit::Int64, target_release::Float64)

Add a volume release to the water order.

WARNING: days used in calculating target array index for rochester flow.

# Arguments
- `env_state` : environmental state structure
- `ts` : global time step
- `date` : current date
- `rochester_flow` : time series of flow data at Rochester
- `dt_threshold` : search for flow event AFTER this date
- `avail_alloc` : total available allocation (HR + LR)
- `other_releases` : other water orders
- `block_limit` : number of consecutive days to be considered as an event
- `target_release` : flow/day amount to check for, and add if necessary
"""
function add_release_on_dt_check!(env_state::EnvironmentState, ts::Int64, date::Date,
                                 rochester_flow::Vector{Float64}, dt_threshold::Date,
                                 avail_alloc::Float64, other_releases::Float64,
                                 block_limit::Int64, target_release::Float64)
    # Calculate starting index for flow check
    threshold_idx = ts - abs(Dates.value(date - dt_threshold))

    # Find indices where flow meets or exceeds target and compute differences between consecutive indices
    indices_above_target = findall(rochester_flow[threshold_idx:ts] .>= target_release)
    is_seq = diff(indices_above_target)

    add_release!(env_state, rochester_flow[ts], is_seq, avail_alloc, other_releases,
                  block_limit, target_release)

    return nothing
end

"""
    add_release!(env_state::EnvironmentState, rochester_ts_flow::Float64, sequence,
                 avail_alloc::Float64, other_releases::Float64, block_limit::Int64,
                 target_release::Float64)

Add environmental water release on top of whatever else is ordered.

Checks to see if a certain number of events has occurred over a certain flow level.
If the number of events has not been reached then adds environmental water orders.

# Arguments
- `env_state` : environmental state structure
- `rochester_ts_flow` : flow at Rochester for the current time step
- `sequence` : boolean array indicating days with flow above target value
- `avail_alloc` : total available allocation (HR + LR)
- `other_releases` : value indicating volume of other releases
- `block_limit` : value representing how many consecutive days is to be regarded as a single event
- `target_release` : desired volume to be released
"""
function add_release!(env_state::EnvironmentState, rochester_ts_flow::Float64, sequence,
                      avail_alloc::Float64, other_releases::Float64, block_limit::Int64,
                      target_release::Float64)
    block_count = count_consecutive_events(sequence, block_limit)

    # Target flow rate has NOT happened
    if block_count == 0
        # Release water required to meet this condition if allocation available
        daily_release = max(0.0, target_release - rochester_ts_flow - other_releases)
        env_state.water_order += min(daily_release * block_limit, avail_alloc)
    end

    return nothing
end

"""
    count_consecutive_events(sequence, block_limit::Int64)::Int64

Count number of consecutive events in a sequence.

# Arguments
- `sequence` : boolean array indicating days with flow above target value
- `block_limit` : number of consecutive `true` conditions to be regarded as an event

# Returns
- `Int64` : count of events
"""
function count_consecutive_events(sequence::Vector{Bool}, block_limit::Int64)::Int64
    count = 1
    block_count = 0

    for i in sequence
        count = (i == 1) ? count + 1 : 1
        if i > 1 && count >= 4
            block_count += 1
            count = 1
        end
    end

    # Include last contiguous block
    if count > block_limit
        block_count += 1
    end

    return block_count
end

