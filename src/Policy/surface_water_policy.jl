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

    return 1.0
end

"""
    check_run(sw_state::GwState, date::Date)

Check if surface water policy model should run and updates times.

# Arguments
- `sw_state` : struct with surface water state.
- `date` : date of current time step.

# Returns
Boolean defining if the model should run.
"""
function check_run(sw_state::GwState, date::Date)
    if sw_state.next_run == nothing
        if month(date) == month(sw_state.season_start) && day(date) == day(sw_state.season_start)
            sw_state.season_end = Date(year(date) + 1, month(sw_state.season_end), day(sw_state.season_end))
            sw_state.first_release = Date(year(date), month(sw_state.first_release), day(sw_state.first_release))
            sw_state.next_run = date + sw_state.timestep

            # Reset environmental water order counter
            sw_state.env_state.water_order = 0
            sw_state.env_state.season_order = 0

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
