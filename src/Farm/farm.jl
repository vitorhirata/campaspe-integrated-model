using Agtor

@with_kw mutable struct FarmState
    plant_season_start::Date = Date(1900, 5, 25) # Year is ignored
    plant_season_end::Date = Date(1900, 1, 20) # Year is ignored
    is_plant_season::Bool = false
    farm_dates::StepRange{Date, Day}
end

"""
    update_farm(basin::Agtor.Basin, gw_levels::Dict{String, Float64}, water_allocs::Dict{String, Any}, dt::Date, ts::Int64)::Tuple{Dict{String, Float64}, Dict{String, Float64}}

Update farm model and calculate water orders for all zones.

Runs the farm optimization model (Agtor) for each zone in the basin to determine
irrigation water requirements from surface water and groundwater sources.

# Arguments
- `basin::Agtor.Basin` : Basin containing all farm zones
- `gw_levels::Dict{String, Float64}` : Groundwater depth for each zone (meters below ground)
- `water_allocs::Dict{String, Any}` : Available water allocations for each zone
  - Keys are zone IDs
  - Values are dicts with "SW" (surface water) and "GW" (groundwater) allocations
- `dt::Date` : Current date
- `ts::Int64` : Current timestep index

# Returns
- `Tuple{Dict{String, Float64}, Dict{String, Float64}}` :
  - First dict: Surface water orders by zone ID (ML)
  - Second dict: Groundwater orders by zone ID (ML)
"""
function update_farm(
    basin::Agtor.Basin, gw_levels::Dict{String, Float64}, water_allocs::Dict{String, Any},
    dt::Date, ts::Int64, farm_state::FarmState
)::Tuple{Dict{String, Float64}, Dict{String, Float64}}
    zone_ids = [split(zone.name, "_")[end] for zone in basin.zones]
    sw_orders = Dict{String, Float64}(zip(zone_ids, zeros(length(zone_ids))))
    gw_orders = Dict{String, Float64}(zip(zone_ids, zeros(length(zone_ids))))

    if is_same_day(dt, farm_state.plant_season_start)
        reset_allocations!(basin)
        farm_state.is_plant_season = true
    end
    if !farm_state.is_plant_season
        return sw_orders, gw_orders
    end
    # If not on fortnight and not on start and end of season
    if !(dt in farm_state.farm_dates) &&
       !is_same_day(dt, farm_state.plant_season_start) &&
       !is_same_day(dt, farm_state.plant_season_end)
        return sw_orders, gw_orders
    end

    # Update timesteps
    basin.current_ts = (ts, dt)

    for zone in basin.zones
        # Extract zone ID from zone name
        zone_id = split(zone.name, "_")[end]

        if !is_same_day(dt, farm_state.plant_season_start)
            # Prepare water allocation data for this zone. Sum high and low reliability to get total surface water allocation
            water_source_map = Dict(:surface_water => "SW", :groundwater => "GW")
            keys = Tuple([Symbol(ws.name) for ws in zone.water_sources])
            vals = Tuple(sum(values(water_allocs[zone_id][water_source_map[key]])) for key in keys)
            zone_water_allocs = NamedTuple{keys}(vals)

            CampaspeIntegratedModel.Agtor.update_available_water!(zone, zone_water_allocs)
        end

        # Update groundwater head/depth for this zone
        gw_index = findfirst(z -> z.name == "groundwater", zone.water_sources)
        if !isnothing(gw_index)
            zone.water_sources[gw_index].head = gw_levels[zone_id]
        end

        # Run farm optimization for this timestep
        CampaspeIntegratedModel.Agtor.run_timestep!(zone.manager, zone, ts, dt)

        # Get irrigation volumes from all fields in the zone
        sw_vol, gw_vol = irrigation_orders(zone)

        sw_orders[zone_id] = sw_vol
        gw_orders[zone_id] = gw_vol
    end

    if is_same_day(dt, farm_state.plant_season_end)
        farm_state.is_plant_season = false
    end

    return sw_orders, gw_orders
end

"""
    irrigation_orders(zone::Agtor.FarmZone)::Tuple{Float64, Float64}

Calculate total irrigation orders volume from surface water and groundwater for a zone.
Aggregates irrigation volumes across all fields in the zone from the last irrigation event recorded in each field.

# Arguments
- `zone::Agtor.FarmZone` : Farm zone to get irrigation volumes for

# Returns
- `Tuple{Float64, Float64}` : (surface_water_ML, groundwater_ML)

# Notes
Returns (0.0, 0.0) if no irrigation has occurred or fields have no irrigation data.
"""
function irrigation_orders(zone::Agtor.FarmZone)::Tuple{Float64, Float64}
    sw_total::Float64 = 0.0
    gw_total::Float64 = 0.0

    for field in zone.fields
        # field.irrigated_volume is a tuple: (water_source_name, volume_ML)
        # Will be nothing if field hasn't been irrigated yet
        if !isnothing(field.irrigated_volume) && field.irrigated_volume != 0
            sw_total += field._irrigated_volume["surface_water"]
            gw_total += field._irrigated_volume["groundwater"]
        end
    end

    return sw_total, gw_total
end

"""
    reset_allocations!(basin::Agtor.Basin)::Nothing

Set all water source allocations to their full entitlement values.
Used at planting season start to allow area optimization before actual allocations are available.
"""
function reset_allocations!(basin::Agtor.Basin)::Nothing
    for zone in basin.zones
        for water_source in zone.water_sources
            water_source.allocation = water_source.entitlement
        end
    end
    return nothing
end

"""
    is_same_day(dt1::Date, dt2::Date)::Bool

Check if two dates have the same month and day, ignoring year.
Useful for comparing seasonal dates across different years.
"""
function is_same_day(dt1::Date, dt2::Date)::Bool
    return Dates.month(dt1) == Dates.month(dt2) && Dates.day(dt1) == Dates.day(dt2)
end

"""
    update_crop_dates!(basin::Agtor.Basin, start_date::Date)::Nothing

Update plant and harvest dates for all crops in the basin to align with the model run period.

For each crop, finds the next occurrence of its planting date (month-day) that occurs on or after
the model start date, then updates plant_date, harvest_date, and growth stages accordingly.

# Arguments
- `basin::Agtor.Basin` : Basin containing zones with fields and crops
- `start_date::Date` : Start date of the model simulation

# Example
```julia
model_start = Date("2024-01-01")
update_crop_dates!(campaspe_basin, model_start)
```
"""
function update_crop_dates!(basin::Agtor.Basin, start_date::Date)::Nothing
    for zone in basin.zones
        for field in zone.fields
            crop = field.crop

            # Find the next occurrence of this month-day >= start_date
            new_date = Date(Dates.year(start_date), Dates.month(crop.plant_date), Dates.day(crop.plant_date))
            if new_date < start_date
                new_date += Dates.Year(1)
            end

            # Update all crop dates
            crop.plant_date = new_date
            crop.harvest_date = crop.plant_date + crop.harvest_offset
            CampaspeIntegratedModel.Agtor.update_stages!(crop, crop.plant_date)
        end
    end

    return nothing
end
