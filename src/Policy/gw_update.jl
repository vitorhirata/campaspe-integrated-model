"""
    update_groundwater(gw_state::GwState, date::Date, gw_orders::Dict{String, Float64}, gw_levels::Dict{String, Float64})

Updates groundwater levels based on extraction orders.

# Arguments
- `gw_state` : struct with groundwater state.
- `date` : date of current time step.
- `gw_orders` : dictionary with groundwater orders. For example, {Zone Name: Amount of GW Order}.
- `gw_levels` : dictionary with groundwater levels at trigger bores. For example, {Bore name: GW level}.

# Returns
Vector with log including several variables.
"""
function update_groundwater(
    gw_state::GwState, date::Date, gw_orders::Dict{String, Float64}, gw_levels::Dict{String, Float64}
)::Vector{Float64}
    log::Vector{Float64} = []
    for zone_name in keys(gw_orders)
        gw_state.zone_info[findfirst(==(zone_name), gw_state.zone_info.ZoneID), "gw_used"] += gw_orders[zone_name]
    end

    gw_state.gw_levels = copy(gw_levels)

    if Dates.month(date) == Dates.month(gw_state.season_start) && Dates.day(date) == Dates.day(gw_state.season_start)
        restriction(gw_state)
        licence(gw_state, date)
        gw_state.initial_gw_levels = copy(gw_levels)
        log = build_log(gw_state)
    elseif Dates.month(date) == Dates.month(gw_state.season_end) && Dates.day(date) == Dates.day(gw_state.season_end)
        licence(gw_state, date)
        log = build_log(gw_state)
        gw_state.current_year += 1
        gw_state.zone_info[:, ["gw_alloc", "gw_carryover", "gw_proportion", "gw_used"]] .= 0.0
    end

    return log
end

"""
    licence(gw_state, date)::Nothing

Updates groundwater allocation and carryover, based on water entitlement and water extraction.

# Arguments
- `gw_state` : struct with groundwater state.
- `date` : date of current time step.
"""
function licence(gw_state::GwState, date::Date)::Nothing
    entitlement = gw_state.zone_info.gw_Ent

    if Dates.year(date) > 1
        gw_state.zone_info.gw_alloc = (entitlement .* gw_state.zone_info.gw_proportion) .+ gw_state.zone_info.gw_carryover
    else
        gw_state.zone_info.gw_alloc = (entitlement .* gw_state.zone_info.gw_proportion)
    end

    if Dates.month(date) == Dates.month(gw_state.season_end) && Dates.day(date) == Dates.day(gw_state.season_end)
        # Maximum carryover is 25% of a year's allocation (see Campaspe Policy doc, page 30)
        tmp = min.(gw_state.zone_info.gw_alloc * 0.25, gw_state.zone_info.gw_alloc - gw_state.zone_info.gw_used)
        # Replace values close to 0.0 with 0.0 (element-wise)
        tmp = [isapprox(val, 0.0; atol=1e-6) ? 0.0 : val for val in tmp]
        gw_state.zone_info.gw_carryover = tmp
    end

    return nothing
end

"""
    restriction(gw_state::GwState)::Nothing

Updates zone_info using the default or coupled groundwater restrictions.

# Arguments
- `gw_state` : struct with groundwater state.
"""
function restriction(gw_state::GwState)::Nothing
    if gw_state.restriction_type == "default"
        default_restriction(gw_state)
    elseif gw_state.restriction_type == "coupled"
        coupled_restriction(gw_state)
    end

    return nothing
end

"""
    default_restriction(gw_state::GwState)::Nothing

Current restriction ruleset. Updates zone_info dataframe with allowable proportional take on 1 July each year.

# Arguments
- `gw_state` : struct with groundwater state.
"""
function default_restriction(gw_state::GwState)::Nothing
    set_trigger_levels(gw_state)
    set_allocation_prop(gw_state, "current")

    return nothing
end

"""
    coupled_restriction(gw_state::GwState)::Nothing

New proposed restriction ruleset, coupling groundwater and surface water. Determines drought status at 1 July each year.
Updates zone_info dataframe with allowable proportional take.

# Arguments
- `gw_state` : struct with groundwater state.
"""
function coupled_restriction(gw_state::GwState)
    set_trigger_levels(gw_state)

    if gw_state.sw_perc_entitlement < gw_state.drought_trigger
        gw_state.drought_count += 1
    end

    if gw_state.drought_count <= gw_state.max_drought_years
        # Determine groundwater allocation based on drought rules
        set_allocation_prop(gw_state, "drought")
    else
        # Determine groundwater allocation based on non-drought rules
        set_allocation_prop(gw_state, "nondrought")
    end

    return nothing
end

"""
    set_trigger_levels(gw_state::GwState)::Nothing

Update groundwater trigger bore level.

# Arguments
- `gw_state` : struct with groundwater state.
"""
function set_trigger_levels(gw_state::GwState)::Nothing
    for bore in keys(gw_state.gw_levels)
        # Update GW level for a zone if key matches associated name or bore id
        m = [v for (key, v) in gw_state.zone_rows if occursin(lowercase(bore), key)][1]
        gw_state.zone_info[m, "gw_triggerbore_level"] .= gw_state.gw_levels[bore]
    end

    return nothing
end

"""
    set_allocation_prop(gw_state::GwState, table_name::String)::Nothing

Set gw allocation proportion for each entry in `gw_levels`, based on matching groundwater zone and bore id, for the
given water level.

# Arguments
- `gw_state` : struct with groundwater state.
- `table_name` : name of table to use.
"""
function set_allocation_prop(gw_state::GwState, table_name::String)::Nothing
    for bore in keys(gw_state.gw_levels)
        m = [v for (key, v) in gw_state.zone_rows if occursin(lowercase(bore), key)][1]

        zone_bore = gw_state.zone_info[m, "TrigBore"][1]
        tgt_bore = gw_state.trigger_tables[zone_bore][table_name]

        bore_depth_condition = gw_state.gw_levels[bore] .> tgt_bore.Depth
        if sum(bore_depth_condition) != 0
            tmp = maximum(tgt_bore[bore_depth_condition, :Depth])
        else
            tmp = minimum(tgt_bore[gw_state.gw_levels[bore] .< tgt_bore.Depth, :Depth])
        end

        gw_state.zone_info[m, "gw_proportion"] .= tgt_bore[tgt_bore.Depth .== tmp, "Proportion"]
    end

    return nothing
end

function build_log(gw_state)
    return [gw_state.current_year,
     gw_state.sw_perc_entitlement,
     sum(gw_state.zone_info[:, "gw_alloc"]) / sum(gw_state.zone_info[:, "gw_Ent"]),
     gw_state.initial_gw_levels["62589"],
     gw_state.initial_gw_levels["79324"],
     sum(gw_state.zone_info[:, "gw_alloc"]),
     sum(gw_state.zone_info[:, "gw_used"]),
     sum(gw_state.zone_info[:, "gw_carryover"]),
    ]
end
