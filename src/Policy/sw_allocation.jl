"""
    calc_allocation(sw_state::SwState, farm_orders::Dict, dam_vol::Float64, rolling_dam_level::Float64)

Calculate the initial HR allocation (first time step) for a growing season.
Does this for each farm zone.

Sets the HR allocation, carryover, percent HR entitlement, and updates the total HR water
allocated.

# Arguments
- `sw_state` : surface water state structure
- `farm_orders` : dictionary of surface water orders for each farm zone
- `dam_vol` : dam volume in ML
- `rolling_dam_level` : rolling average of dam level
"""
function calc_allocation(sw_state::SwState, farm_orders::Dict, dam_vol::Float64, rolling_dam_level::Float64)
    # Calculate storage river losses
    ts = sw_state.current_time
    river_loss = sum([value[ts] for value in values(sw_state.water_losses)])

    # Calculate usable dam volume
    sw_state.usable_dam_vol = max(0.0, dam_vol - sw_state.min_op_vol - river_loss)

    # Calculate GMW volume
    sw_state.gmw_vol[ts] = max(0.0,
        (sw_state.gmw_share * sw_state.proj_inflow[ts]) + (sw_state.gmw_share * sw_state.usable_dam_vol))

    if ts == 1
        first_allocation(sw_state, sw_state.current_year, ts, sw_state.gmw_vol[ts], rolling_dam_level)
    else
        later_allocation(sw_state, sw_state.current_year, ts, sw_state.gmw_vol[ts], farm_orders)
    end

    update_catchment_stats!(sw_state)
end

"""
    first_allocation(sw_state::SwState, year::Int64, ts::Int64, gmw_vol::Float64, rolling_dam_level::Float64)

Calculate the initial HR allocation (first time step) for a growing season.

Sets the HR allocation, carryover, percent HR entitlement, and updates the total HR water
allocated.

# Arguments
- `sw_state` : surface water state structure
- `year` : count of year in model run (not year of current datetime)
- `ts` : current time step (1-based)
- `gmw_vol` : volume share for Goulburn-Murray Water
- `rolling_dam_level` : rolling average of dam level
"""
function first_allocation(sw_state::SwState, year::Int64, ts::Int64, gmw_vol::Float64, rolling_dam_level::Float64)
    # Reset all global state counters to zero
    sw_state.total_water_orders = 0.0
    sw_state.avail_allocation["campaspe"]["LR"] = 0.0
    sw_state.cumu_allocation["campaspe"]["LR"] = 0.0

    # Assign first allocation, capping to HR entitlement
    if year == 1
        sw_state.avail_allocation["campaspe"]["HR"] = min(gmw_vol, sw_state.hr_entitlement)
    else
        sw_state.avail_allocation["campaspe"]["HR"] = min(
              sw_state.reserves["HR"][year] + gmw_vol, sw_state.hr_entitlement)
    end

    sw_state.total_allocated = sw_state.avail_allocation["campaspe"]["HR"]
    sw_state.cumu_allocation["campaspe"]["HR"] = sw_state.total_allocated
    sw_state.perc_entitlement["campaspe"]["HR"] = sw_state.total_allocated / sw_state.hr_entitlement

    # Define goulburn allocation
    get_goulburn_allocation!(sw_state)

    # Reset allocation and order counter for all zones
    for z_info in values(sw_state.zone_info)
        if z_info["zone_type"] == "farm"
            avail_hr = z_info["entitlement"]["camp_HR"] * sw_state.perc_entitlement["campaspe"]["HR"]
        else
            avail_hr = z_info["entitlement"]["HR"] * sw_state.perc_entitlement["campaspe"]["HR"]
        end

        # Set zone available allocation
        z_info["avail_allocation"]["campaspe"]["HR"] = avail_hr
        z_info["avail_allocation"]["campaspe"]["LR"] = 0.0

        # Set allocated to date
        z_info["allocated_to_date"]["campaspe"]["HR"] = avail_hr
        z_info["allocated_to_date"]["campaspe"]["LR"] = 0.0

        # Get entitlement
        avail_hr_goul = z_info["entitlement"]["goul_HR"] * sw_state.goulburn_alloc_perc
        z_info["avail_allocation"]["goulburn"]["HR"] = avail_hr_goul
        z_info["avail_allocation"]["goulburn"]["LR"] = 0.0
        z_info["allocated_to_date"]["goulburn"]["HR"] = avail_hr_goul
        z_info["allocated_to_date"]["goulburn"]["LR"] = 0.0

        z_info["ts_water_orders"]["campaspe"] .= 0.0
        z_info["ts_water_orders"]["goulburn"] .= 0.0
    end
end

"""
    later_allocation(sw_state::SwState, year::Int64, ts::Int64, gmw_vol::Float64, farm_orders::Dict)

Calculate allocations for non-first time steps in the model run. Does this for each farm zone.

Once high reliability water is allocated and delivered, and reserves are withheld,
any additional inflow volumes can be allocated to low reliability entitlements.

At end of each time-step pass :math:`A_{L}` to farm model, and environmental water orders,
and other orders to determine water order supplied at the next time-step (:math:`V_{O,t}`)

This should be done until the end of growing season or until :math:`A_{H} = 100`
(percent of high reliablity entitlement).

Water orders are subtracted from the Goulburn system first, then carryovers, then Campaspe LR and HR.

# Arguments
- `sw_state` : surface water state structure
- `year` : count of year in model run (not year of current datetime)
- `ts` : current time step (1-based)
- `gmw_vol` : volume share for Goulburn-Murray Water
- `farm_orders` : dict of farm orders based on zone name as key
"""
function later_allocation(sw_state::SwState, year::Int64, ts::Int64, gmw_vol::Float64, farm_orders::Dict)
    # Bias water orders to Goulburn system if able
    for (zone, z_info) in sw_state.zone_info
        if haskey(farm_orders, zone)
            if irrigation_area(z_info)
                hr_vol = z_info["avail_allocation"]["goulburn"]["HR"]
                goulb_order = farm_orders[zone]

                if (goulb_order > 0.0) && (hr_vol >= goulb_order)
                    hr_vol = hr_vol - goulb_order
                    z_info["avail_allocation"]["goulburn"]["HR"] = hr_vol
                    farm_orders[zone] = 0.0
                elseif goulb_order > 0.0
                    farm_orders[zone] = goulb_order - hr_vol
                    goulb_order = hr_vol
                    z_info["avail_allocation"]["goulburn"]["HR"] = 0.0
                else
                    goulb_order = 0.0
                end

                z_info["ts_water_orders"]["goulburn"][ts] = goulb_order
            end
        end
    end

    # Calculate High Reliability (HR) allocation updates if not at 100% capacity
    # This section handles incremental HR allocation based on available GMW volume
    hr_perc = sw_state.perc_entitlement["campaspe"]["HR"]
    lr_perc = sw_state.perc_entitlement["campaspe"]["LR"]
    lr_alloc = hr_alloc = 0.0
    total_water_orders = sw_state.total_water_orders + sum(values(farm_orders))

    if hr_perc < 1.0
        hr_ent = sw_state.hr_entitlement
        allocated_HR = sw_state.cumu_allocation["campaspe"]["HR"]

        # V_{HR} = GMW_{vol} - (V_{T} - (V_{o} + V_{s})), see page 18 of policy document
        hr_alloc = max(0.0, gmw_vol - (allocated_HR - total_water_orders))

        # Cap to HR entitlement
        if (allocated_HR + hr_alloc) > sw_state.hr_entitlement
            hr_alloc = sw_state.hr_entitlement - sw_state.cumu_allocation["campaspe"]["HR"]
        end

        updated_HR_alloc = allocated_HR + hr_alloc

        avail_hr = updated_HR_alloc - total_water_orders
        if isapprox(avail_hr, 0.0)
            avail_hr = 0.0
        end
        @assert avail_hr >= 0.0

        sw_state.avail_allocation["campaspe"]["HR"] = avail_hr
        hr_perc = updated_HR_alloc / hr_ent
        sw_state.cumu_allocation["campaspe"]["HR"] = updated_HR_alloc
    end

    @assert hr_perc < 1 || isapprox(hr_perc, 1.0)

    # Update individual zone allocations based on current percentage entitlements
    # This distributes the calculated catchment-wide allocations to each zone
    for (zone, z_info) in sw_state.zone_info
        add_campaspe_allocation!(z_info, sw_state)
        add_goulburn_allocation!(ts, z_info, sw_state)
    end

    calc_next_season_reserves!(sw_state)

    # Calculate Low Reliability (LR) allocation if conditions are met
    # LR allocation only occurs when HR is at 100%, reserves are satisfied, and LR is not yet at 100%
    if lr_allocation(sw_state, hr_perc, lr_perc, ts)
        total_alloc = sw_state.cumu_allocation["campaspe"]["HR"] + sw_state.cumu_allocation["campaspe"]["LR"]

        lr_alloc = max(0.0, gmw_vol - sw_state.reserves["op"][year] - sw_state.reserves["HR"][year] -
                      (total_alloc - total_water_orders))

        # Cap to LR entitlement
        if (sw_state.cumu_allocation["campaspe"]["LR"] + lr_alloc) > sw_state.lr_entitlement
            lr_alloc = sw_state.lr_entitlement - sw_state.cumu_allocation["campaspe"]["LR"]
        end

        total_alloc = total_alloc + lr_alloc

        sw_state.avail_allocation["campaspe"]["LR"] = sw_state.avail_allocation["campaspe"]["LR"] + lr_alloc
        sw_state.cumu_allocation["campaspe"]["LR"] = sw_state.cumu_allocation["campaspe"]["LR"] + lr_alloc
        lr_perc = sw_state.cumu_allocation["campaspe"]["LR"] / sw_state.lr_entitlement

        # Set HR and LR allocations
        for (z_name, z_info) in sw_state.zone_info
            if z_info["zone_type"] == "farm"
                avail_hr = z_info["entitlement"]["camp_HR"] * hr_perc
                avail_lr = z_info["entitlement"]["camp_LR"] * lr_perc
            else
                avail_hr = z_info["entitlement"]["HR"] * hr_perc
                avail_lr = z_info["entitlement"]["LR"] * lr_perc
            end

            # Set available and allocated to date zone allocation
            z_info["avail_allocation"]["campaspe"]["HR"] = avail_hr
            z_info["avail_allocation"]["campaspe"]["LR"] = avail_lr
            z_info["allocated_to_date"]["campaspe"]["HR"] = avail_hr
            z_info["allocated_to_date"]["campaspe"]["LR"] = avail_lr
        end
    end

    # Update global state
    sw_state.perc_entitlement["campaspe"]["HR"] = hr_perc
    sw_state.perc_entitlement["campaspe"]["LR"] = lr_perc

    # Update zone allocation information
    zonal_lr_alloc, zonal_hr_alloc = 0.0, 0.0
    for (zone, z_info) in sw_state.zone_info
        if haskey(farm_orders, zone)
            z_info["ts_water_orders"]["campaspe"][ts] = farm_orders[zone]
        end

        # Subtract water orders from carryover state if available
        leftover = update_carryover_state!(z_info, ts)

        # Update available allocation by subtracting water order from available allocation
        avail_hr = z_info["avail_allocation"]["campaspe"]["HR"]
        avail_lr = z_info["avail_allocation"]["campaspe"]["LR"]

        avail_lr, avail_hr, leftover = prop_subtract(avail_lr, avail_hr, leftover)
        # TODO: Bug happening here. The tests have zero f_orders because adding orders raises errors in this assert.
        @assert isapprox(leftover, 0.0) "Cannot order more than available allocation. Zone: $zone, " *
            "Water ordered: $(z_info["ts_water_orders"]["campaspe"][ts]), Leftover: $leftover, " *
            "Avail HR: $avail_hr, Avail LR: $avail_lr, Zone type: $(z_info["zone_type"])"

        # Inline set_avail_zone_allocation for campaspe system
        z_info["avail_allocation"]["campaspe"]["HR"] = avail_hr
        z_info["avail_allocation"]["campaspe"]["LR"] = avail_lr

        zonal_lr_alloc += avail_lr
        zonal_hr_alloc += avail_hr
    end
    @assert zonal_hr_alloc >= 0.0

    sw_state.avail_allocation["campaspe"]["HR"] = zonal_hr_alloc
    sw_state.avail_allocation["campaspe"]["LR"] = zonal_lr_alloc
    return nothing
end

"""
    check_if_irrigation_area(z_info::Dict)::Bool

Check if given zone is an irrigation area (Rochester or Campaspe).
"""
function irrigation_area(z_info::Dict)::Bool
    return (haskey(z_info, "water_system") &&
            z_info["water_system"] in ["Rochester Irrigation Area", "Campaspe Irrigation Area"])
end

"""
    lr_allocation(sw_state::SwState, hr_perc::Float64, lr_perc::Float64, ts::Int64)::Bool

Check if low reliability allocation must be runned. Only start allocating LR if full HR allocations have been reached
and reserves have been met.
"""
function lr_allocation(sw_state::SwState, hr_perc::Float64, lr_perc::Float64, ts::Int64)::Bool
    hr_met = isapprox(hr_perc, 1.0)
    reserves_met = ((sw_state.ts_reserves["HR"][ts] >= sw_state.hr_entitlement) &&
                   (sw_state.ts_reserves["op"][ts] >= sw_state.worst_case_loss))
    lr_not_met = lr_perc < 1.0

    return hr_met && reserves_met && lr_not_met
end

"""
    add_campaspe_allocation!(z_info::Dict, sw_state::SwState)

Update zone's allocated_to_date for Campaspe system based on current percentage entitlements.

# Arguments
- `z_info` : zone information dictionary
- `sw_state` : surface water state
"""
function add_campaspe_allocation!(z_info::Dict, sw_state::SwState)::Nothing
    if z_info["zone_type"] == "farm"
        hr = z_info["entitlement"]["camp_HR"] * sw_state.perc_entitlement["campaspe"]["HR"]
        lr = z_info["entitlement"]["camp_LR"] * sw_state.perc_entitlement["campaspe"]["LR"]
    else
        hr = z_info["entitlement"]["HR"] * sw_state.perc_entitlement["campaspe"]["HR"]
        lr = z_info["entitlement"]["LR"] * sw_state.perc_entitlement["campaspe"]["LR"]
    end

    z_info["allocated_to_date"]["campaspe"]["HR"] = hr
    z_info["allocated_to_date"]["campaspe"]["LR"] = lr
    return nothing
end

"""
    update_carryover_state!(z_info::Dict, ts::Int64)

Update available carryover, subtracting water orders at each timestep for a specific zone.
Water orders should be subtracted from carryovers first.

# Arguments
- `z_info` : zone information dictionary
- `ts` : current time step

# Returns
- `Float64` : water orders left to be fulfilled
"""
function update_carryover_state!(z_info::Dict, ts::Int64)::Float64
    z_cos = z_info["carryover_state"]

    water_ordered = z_info["ts_water_orders"]["campaspe"][ts] > 0
    carryover_available = (z_cos["LR"] > 0) || (z_cos["HR"] > 0)

    if water_ordered && carryover_available
        z_cos["LR"], z_cos["HR"], leftover = prop_subtract(z_cos["LR"], z_cos["HR"],
                                                           z_info["ts_water_orders"]["campaspe"][ts])
        return leftover
    end

    return z_info["ts_water_orders"]["campaspe"][ts]
end

"""
    calc_next_season_reserves!(sw_state::SwState)

Calculate reserves for next season until reserves are met or end of season.
Does this for the entire catchment.

# Arguments
- `sw_state` : surface water state
"""
function calc_next_season_reserves!(sw_state::SwState)::Nothing
    ts = sw_state.current_time
    op_reserve = 0.0
    hr_reserve = 0.0

    if sw_state.current_year > 1
        if sw_state.cumu_allocation["campaspe"]["HR"] < sw_state.hr_entitlement
            set_reserves!(sw_state, hr_reserve, op_reserve)
            return nothing
        end

        upper_limit = sw_state.worst_case_loss + sw_state.hr_entitlement
        allocated_reserves = (sw_state.ts_reserves["HR"][ts - 1] + sw_state.ts_reserves["op"][ts - 1])

        # If reserves are not met use GMW water
        if allocated_reserves < upper_limit
            temp_gmw_vol = sw_state.gmw_vol[ts] - sw_state.cumu_allocation["campaspe"]["HR"]
            op_reserve = max(0.0, min(temp_gmw_vol, sw_state.worst_case_loss))
            hr_reserve = max(0.0, min(temp_gmw_vol - op_reserve, sw_state.hr_entitlement))
        else
            hr_reserve = sw_state.ts_reserves["HR"][ts - 1]
            op_reserve = sw_state.ts_reserves["op"][ts - 1]
        end
    end

    set_reserves!(sw_state, hr_reserve, op_reserve)
    return nothing
end

"""
    set_reserves!(sw_state::SwState, hr::Float64, op::Float64)

Set reserve volumes for HR and operational reserves.

# Arguments
- `sw_state` : surface water state
- `hr` : volume reserved for High Reliability entitlements
- `op` : volume reserved for dam operation
"""
function set_reserves!(sw_state::SwState, hr::Float64, op::Float64)::Nothing
    @assert sw_state.current_year + 1 <= length(sw_state.reserves["HR"])

    # Set yearly reserves (matches Python: year + 1 pattern for next year)
    sw_state.reserves["HR"][sw_state.current_year + 1] = hr
    sw_state.reserves["op"][sw_state.current_year + 1] = op

    # Set time series reserves (matches Python: ts pattern for current timestep)
    sw_state.ts_reserves["HR"][sw_state.current_time] = hr
    sw_state.ts_reserves["op"][sw_state.current_time] = op

    return nothing
end

"""
    prop_subtract(lr::Float64, hr::Float64, val::Float64)

Cascading water allocation subtraction: takes from LR first, then HR, preserving HR allocations.

Water orders are satisfied using priority-based allocation: Low Reliability (LR) water is
consumed first to preserve critical High Reliability (HR) allocations. Returns remaining
allocations and any unsatisfied demand.

# Arguments
- `lr::Float64` : available Low Reliability water allocation volume (ML)
- `hr::Float64` : available High Reliability water allocation volume (ML)
- `val::Float64` : water volume to subtract/allocate (ML)

# Returns
- `Tuple{Float64, Float64, Float64}` : (remaining_lr, remaining_hr, leftover_demand)

# Examples
```julia
# Case 1: Full satisfaction from LR
lr, hr, leftover = prop_subtract(100.0, 50.0, 80.0)  # (20.0, 50.0, 0.0)

# Case 2: Partial from LR, remainder from HR
lr, hr, leftover = prop_subtract(30.0, 50.0, 60.0)   # (0.0, 20.0, 0.0)

# Case 3: Exhausts both pools
lr, hr, leftover = prop_subtract(30.0, 20.0, 60.0)   # (0.0, 0.0, 10.0)
```
"""
function prop_subtract(lr::Float64, hr::Float64, val::Float64)::Tuple{Float64, Float64, Float64}
    if isapprox(val, 0.0)
        return lr, hr, 0.0
    end

    if lr > 0.0
        if lr < val && !isapprox(lr, val)
            leftover = val - lr  # LR insufficient - exhaust LR, calculate remaining demand
            lr = 0.0

            if hr < leftover && !isapprox(hr, leftover)
                leftover = leftover - hr  # HR also insufficient - exhaust HR, demand remains unsatisfied
                hr = 0.0
            else
                hr = hr - leftover  # HR covers remaining demand completely
                leftover = 0.0
            end
        else
            lr = lr - val  # LR sufficient for entire demand
            leftover = 0.0
        end
    elseif hr > 0.0
        if hr < val && !isapprox(hr, val)
            leftover = val - hr  # HR insufficient - exhaust HR, demand remains unsatisfied
            hr = 0.0
        else
            hr = hr - val  # HR sufficient for entire demand
            leftover = 0.0
        end
    else
        return lr, hr, val  # Both pools empty - cannot satisfy any demand
    end

    lr = isapprox(lr, 0.0) ? 0.0 : lr  # Clean up numerical precision
    hr = isapprox(hr, 0.0) ? 0.0 : hr
    @assert lr >= 0.0 && hr >= 0.0

    return lr, hr, leftover
end

"""
    get_reliability_carryover(sw_state::SwState)

Calculate total carryover for the catchment based on reliability (HR and LR).

Sums up yearly carryover volumes across all zones for the current year.

# Arguments
- `sw_state::SwState` : surface water state structure

# Returns
- `Dict{String, Float64}` : dictionary with "HR" and "LR" carryover totals
"""
function get_reliability_carryover(sw_state::SwState)::Dict{String, Float64}
    hr_carryover = 0.0
    lr_carryover = 0.0

    for z_info in values(sw_state.zone_info)
        hr_carryover += z_info["yearly_carryover"]["HR"][sw_state.current_year]
        lr_carryover += z_info["yearly_carryover"]["LR"][sw_state.current_year]
    end

    return Dict("HR" => hr_carryover, "LR" => lr_carryover)
end

"""
    calc_carryover_state!(sw_state::SwState)

Calculate carryover state within a growing season for the entire catchment.

Sums the current carryover state (HR + LR) across all zones and stores it
in the catchment-level carryover_state array for the current year.

# Arguments
- `sw_state::SwState` : surface water state structure
"""
function calc_carryover_state!(sw_state::SwState)::Nothing
    total = 0.0
    for z_info in values(sw_state.zone_info)
        z_co = z_info["carryover_state"]
        total += z_co["HR"] + z_co["LR"]
    end

    sw_state.carryover_state[sw_state.current_year] = total
    return nothing
end

"""
    update_catchment_stats!(sw_state::SwState)

Update catchment-wide statistics after allocation calculations.

Updates:
- Total water allocated (sum of cumulative HR and LR)
- Percentage of entitlement allocated (HR and LR)
- Adjusted percentage entitlement (includes carryover in denominator)
- Carryover state within the growing season

# Arguments
- `sw_state::SwState` : surface water state structure
"""
function update_catchment_stats!(sw_state::SwState)::Nothing
    # Update total allocated volume
    cumu_hr_vol = sw_state.cumu_allocation["campaspe"]["HR"]
    cumu_lr_vol = sw_state.cumu_allocation["campaspe"]["LR"]
    sw_state.total_allocated = cumu_hr_vol + cumu_lr_vol

    # Update percentage entitlement
    sw_state.perc_entitlement["campaspe"]["HR"] = cumu_hr_vol / sw_state.hr_entitlement
    sw_state.perc_entitlement["campaspe"]["LR"] = cumu_lr_vol / sw_state.lr_entitlement

    # Calculate adjusted percentage entitlement with carryover
    reliability_co = get_reliability_carryover(sw_state)
    sw_state.adj_perc_entitlement["HR"] = cumu_hr_vol / (sw_state.hr_entitlement + reliability_co["HR"])
    sw_state.adj_perc_entitlement["LR"] = cumu_lr_vol / (sw_state.lr_entitlement + reliability_co["LR"])

    # Recalculate within-season carryover state
    calc_carryover_state!(sw_state)

    return nothing
end

"""
    calc_other_orders!(sw_state::SwState)::Float64

Calculate water orders for "other" (non-farming and non-environmental) water systems.

"Other" zones receive their available allocation immediately as water orders.
This function:
1. Identifies zones with zone_type == "other"
2. Calculates available allocation after subtracting previously ordered water
3. Releases all available allocation as water orders
4. Updates carryover state
5. Subtracts released water from catchment-level available allocation

# Arguments
- `sw_state::SwState` : surface water state structure

# Returns
- `Float64` : total water ordered for "other" systems in ML
"""
function calc_other_orders!(sw_state::SwState)::Float64
    if sw_state.current_time == 0
        return 0.0
    end

    hr_release = 0.0
    lr_release = 0.0

    for (zone_id, z_info) in sw_state.zone_info
        if z_info["zone_type"] == "other"
            # Calculate additional allocation if any
            total_water_ordered = sum(z_info["ts_water_orders"]["campaspe"][1:sw_state.current_time])
            alloc_to_date_hr = z_info["allocated_to_date"]["campaspe"]["HR"]
            alloc_to_date_lr = z_info["allocated_to_date"]["campaspe"]["LR"]

            avail_lr, avail_hr, leftover = prop_subtract(alloc_to_date_lr, alloc_to_date_hr, total_water_ordered)

            # Release any available allocation as soon as able
            if (z_info["avail_allocation"]["campaspe"]["LR"] + z_info["avail_allocation"]["campaspe"]["HR"]) > 0.0
                z_info["ts_water_orders"]["campaspe"][sw_state.current_time] = avail_hr + avail_lr
                hr_release += avail_hr
                lr_release += avail_lr
                z_info["avail_allocation"]["campaspe"]["HR"] = 0.0
                z_info["avail_allocation"]["campaspe"]["LR"] = 0.0
            else
                z_info["avail_allocation"]["campaspe"]["HR"] = avail_hr
                z_info["avail_allocation"]["campaspe"]["LR"] = avail_lr
            end

            # Subtract water orders from carryover state if available
            update_carryover_state!(z_info, sw_state.current_time)
        end
    end

    water_order = hr_release + lr_release

    if water_order > 0.0
        # Update total available allocations
        allocs = sw_state.avail_allocation["campaspe"]
        allocs["LR"], allocs["HR"], leftover = prop_subtract(allocs["LR"], allocs["HR"], water_order)
    end

    return water_order
end
