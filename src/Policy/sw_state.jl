@with_kw mutable struct SwState
    # Timing variables
    season_start::Date = Date(1900, 7, 1) # July 1 (irrigation season start and allocation computed). Year ignored
    first_release::Date = Date(1900, 8, 15) # August 15 (first release date). Year ignored
    season_end::Date = Date(1900, 4, 30) # April 30 (irrigation season end).  Year ignored
    timestep::Day = Day(7) # Length of the model time step. TODO: Check if 7 or 14 days
    ts::Int64 = 1 # Day timestep counter
    current_year::Int64 = 1 # Year timestep counter
    next_run::Union{Date, Nothing} = nothing # Next scheduled run date
    model_run_range::Union{StepRange{Date, Period},Vector{Date}} # Date range for model execution

    # Dam and GMW parameters
    gmw_share::Float64 = 0.82 # Water under control of GM-Water
    worst_case_loss::Int64 = 18560 # Worst case operational losses in ML
    min_op_vol::Int64 = 1024 # Minimum dam operation volume, in ML
    usable_dam_vol::Float64 = 0.0 # Usable dam volume

    # Allocation and entitlements
    avail_allocation::Dict{String, Dict{String, Float64}} = allocation_template() # Currently available allocations
    cumu_allocation::Dict{String, Dict{String, Float64}} = allocation_template() # Cumulative allocations over time
    perc_entitlement::Dict{String, Dict{String, Float64}} = allocation_template() # Percentage of entitlement allocated
    adj_perc_entitlement::Dict{String, Any} = allocation_template() # Perc of entitlement allocated, including carryover
    other_hr_entitlements::Float64 # Other system high reliability entitlements
    other_lr_entitlements::Float64 # Other system low reliability entitlements
    hr_entitlement::Float64 # Total high reliability entitlement
    lr_entitlement::Float64 # Total low reliability entitlement
    farm_hr_entitlement::Float64 # Farm high reliability entitlement
    farm_lr_entitlement::Float64 # Farm low reliability entitlement
    total_water_orders::Float64 = 0.0 # Total water orders for entire catchment for a season
    total_allocated::Float64 = 0.0 # Total water volume allocated

    # Time series data
    gmw_vol::Vector{Float64} # GM-Water volume by timestep
    carryover_state::Vector{Float64} # Carryover state by year
    yearly_carryover::Vector{Float64} # Yearly carryover volumes
    proj_inflow::Vector{Float64} # Projected inflows by timestep
    ts_reserves::Dict{String, Vector{Float64}} # Time series reserves by week (HR, LR, operational)
    reserves::Dict{String, Vector{Float64}} # Time series reserves by year (HR, LR, operational)
    water_losses::Dict{String, Vector{Float64}} # Water losses from lake and operations time series by week

    # Goulburn catchment
    goulburn_alloc_scenario::String # Allocation scenario for Goulburn catchment
    goulburn_wet_scenario::Bool = false
    goulburn_alloc_func::Union{Function, Nothing} = nothing
    goulburn_increment::Float64 = 0.0 # Weekly increment for "high" allocation seasons
    goulburn_alloc_perc::Float64 = 0.0 # Goulburn allocation percentage

    # Zone, dam extration and environment information
    zone_info::Dict{String, Any} # Information about farm zones
    zone_id_to_name::Dict{String, String} # Lookup map from zone_id to zone_name (for farm zones only)
    env_state::EnvironmentState # Environmental State struct
    dam_ext::DataFrame # Water extractions not accounted for by discharge
end

"""
    SwState(model_run_range::Union{StepRange{Date, Period}, zone_info::Dict{String, Any}, goulburn_alloc_scenario::String, dam_ext::DataFrame, env_systems::DataFrame, other_systems::DataFrame)::SwState

SwState constructor.

# Arguments
- `model_run_range` : date range of model execution.
- `zone_info` : dictionary with farming zones info.
- `goulburn_alloc_scenario` : allocation scenario for the Goulburn catchment.
- `dam_ext` : water extractions not accounted for by discharge.
-
"""
function SwState(
    model_run_range::Union{StepRange{Date, Period}, Vector{Date}}, zone_info::Dict{String, Any},
    goulburn_alloc_scenario::String, dam_ext::DataFrame, env_systems::DataFrame, other_systems::DataFrame,
)::SwState

    total_n_weeks = round(Int, (length(model_run_range) / 7) + 1) + 7
    total_n_years = round(Int, (length(model_run_range) / 356) + 1)
    gmw_vol = zeros(total_n_weeks)
    carryover_state = zeros(total_n_years)
    yearly_carryover = zeros(total_n_years)
    proj_inflow = zeros(total_n_weeks)
    ts_reserves = Dict("HR"=>zeros(total_n_weeks), "LR"=>zeros(total_n_weeks), "op"=>zeros(total_n_weeks))
    reserves = Dict("HR"=>zeros(total_n_years), "LR"=>zeros(total_n_years), "op"=>zeros(total_n_years))
    water_losses = Dict("lake_seepage"=>zeros(total_n_weeks), "lake_evaporation"=>zeros(total_n_weeks),
                        "transmission"=>zeros(total_n_weeks), "operational"=>zeros(total_n_weeks))

    zone_info = create_zone_info(zone_info, total_n_weeks, total_n_years, env_systems, other_systems)
    hr_entitlement, lr_entitlement, farm_hr_entitlement, farm_lr_entitlement = compute_entitlements(zone_info,
        env_systems, other_systems)

    # Create zone_id to zone_name lookup for farm zones
    zone_id_to_name = Dict{String, String}(
        z_info["zone_id"] => zone_name
        for (zone_name, z_info) in zone_info
        if z_info["zone_type"] == "farm"
    )

    # Environmental entitlements
    env_hr_entitlement::Float64 = sum(env_systems.HR_Entitlement)
    env_lr_entitlement::Float64 = sum(env_systems.LR_Entitlement)
    env_state = EnvironmentState(env_hr_entitlement, env_lr_entitlement)

    #Other entitlements
    other_hr_entitlements = sum(other_systems.HR_Entitlement)
    other_lr_entitlements = sum(other_systems.LR_Entitlement)

    return SwState(model_run_range=model_run_range, goulburn_alloc_scenario=goulburn_alloc_scenario, dam_ext=dam_ext,
        zone_info=zone_info, zone_id_to_name=zone_id_to_name, gmw_vol=gmw_vol, carryover_state=carryover_state,
        yearly_carryover=yearly_carryover, proj_inflow=proj_inflow,ts_reserves=ts_reserves, reserves=reserves,
        water_losses=water_losses, hr_entitlement=hr_entitlement, lr_entitlement=lr_entitlement,
        farm_hr_entitlement=farm_hr_entitlement, farm_lr_entitlement=farm_lr_entitlement,
        other_hr_entitlements=other_hr_entitlements, other_lr_entitlements=other_lr_entitlements,
        env_state=env_state
    )
end

"""
    create_zone_info(zone_info::Dict{String, Any}, total_n_weeks::Int64, total_n_years::Int64)::Dict{String, Any}

Setup zone_info by adding additional tracking information for each zone including
time series arrays for water orders, carryover states, allocations, and reserves.

# Arguments
- `zone_info` : dictionary with zone information.
- `total_n_weeks` : total number of weeks for time series arrays.
- `total_n_years` : total number of years for time series arrays.
"""
function create_zone_info(zone_info::Dict{String, Any}, total_n_weeks::Int64, total_n_years::Int64,
    env_systems::DataFrame, other_systems::DataFrame
)::Dict{String, Any}
    for (key, value) in zone_info
        zone_info[key] = merge(value, additional_zone_info(total_n_weeks, total_n_years))
        zone_info[key]["zone_type"] = "farm"
    end

    # Set environmental and other zones
    for zone in eachrow(env_systems)
        zone_info[zone["Water System"]] = Dict(
            "entitlement"=>Dict(
                "HR"=>zone.HR_Entitlement, "LR"=> zone.LR_Entitlement,
                "camp_HR"=>0.0, "camp_LR"=>0.0,
                "goul_HR"=>0.0, "goul_LR"=>0.0,
                "farm_HR"=>0.0, "farm_LR"=>0.0
            ),
            "regulation_zone"=> zone["Water System"],
            "name"=> zone["Water System"],
            "zone_type"=> "environmental"
        )
        zone_info[zone["Water System"]] = merge(zone_info[zone["Water System"]], additional_zone_info(total_n_weeks, total_n_years))
    end

    for zone in eachrow(other_systems)
        zone_info[zone["Water System"]] = Dict(
            "entitlement"=>Dict(
                "HR"=>zone.HR_Entitlement, "LR"=> zone.LR_Entitlement,
                "camp_HR"=>0.0, "camp_LR"=>0.0,
                "goul_HR"=>0.0, "goul_LR"=>0.0,
                "farm_HR"=>0.0, "farm_LR"=>0.0
            ),
            "regulation_zone"=> zone["Water System"],
            "name"=> zone["Water System"],
            "zone_type"=> "other"
        )
        zone_info[zone["Water System"]] = merge(zone_info[zone["Water System"]], additional_zone_info(total_n_weeks, total_n_years))
    end
    return zone_info
end

"""
    compute_entitlements(zone_info::Dict{String, Any})::Tuple{Float64, Float64, Float64, Float64}

Compute total and farm entitlements for high and low reliability water allocations.
Also calculates zone shares of total entitlement for GMW volume distribution.

# Arguments
- `zone_info` : dictionary with zone information including entitlements.

# Returns
- `Tuple{Float64, Float64, Float64, Float64}` : (hr_entitlement, lr_entitlement, farm_hr_entitlement, farm_lr_entitlement)
"""
function compute_entitlements(zone_info::Dict{String, Any}, env_systems::DataFrame, other_systems::DataFrame
)::Tuple{Float64, Float64, Float64, Float64}
    hr_ent = lr_ent = farm_hr = farm_lr = 0.0

    for (key, value) in zone_info
        hr_ent += value["entitlement"]["camp_HR"]
        lr_ent += value["entitlement"]["camp_LR"]

        if value["zone_type"] == "farm"
            farm_hr += value["entitlement"]["farm_HR"]
            farm_lr += value["entitlement"]["farm_LR"]
        end
    end

    # Add environmental and other entitlements.
    hr_ent += sum(env_systems.HR_Entitlement) + sum(other_systems.HR_Entitlement)
    lr_ent += sum(env_systems.LR_Entitlement) + sum(other_systems.LR_Entitlement)

    # Sets percent share of GMW volume for each zone based on Campaspe zonal HR entitlement.
    # This is in turn currently based on proportional area.
    for (key, value) in zone_info
        if value["zone_type"] == "farm"
            value["zone_share"] = value["entitlement"]["camp_HR"] / hr_ent
        else
            value["zone_share"] = value["entitlement"]["HR"] / hr_ent
        end
    end

    return hr_ent, lr_ent, farm_hr, farm_lr
end

"""
    recalculate_entitlements!(sw_state::SwState)::Nothing

Recalculate all entitlement totals in sw_state based on current zone_info values.
Updates hr_entitlement, lr_entitlement, farm_hr_entitlement, farm_lr_entitlement,
other_hr_entitlements, and other_lr_entitlements.

# Arguments
- `sw_state::SwState` : Surface water state containing zone information
"""
function recalculate_entitlements!(sw_state::SwState)::Nothing
    hr_ent = lr_ent = farm_hr = farm_lr = other_hr = other_lr = env_hr = env_lr = 0.0

    for value in values(sw_state.zone_info)
        if value["zone_type"] == "farm"
            hr_ent += value["entitlement"]["camp_HR"]
            lr_ent += value["entitlement"]["camp_LR"]
            farm_hr += value["entitlement"]["farm_HR"]
            farm_lr += value["entitlement"]["farm_LR"]
        elseif value["zone_type"] == "environmental"
            env_hr += value["entitlement"]["HR"]
            env_lr += value["entitlement"]["LR"]
            hr_ent += value["entitlement"]["HR"]
            lr_ent += value["entitlement"]["LR"]
        elseif value["zone_type"] == "other"
            other_hr += value["entitlement"]["HR"]
            other_lr += value["entitlement"]["LR"]
            hr_ent += value["entitlement"]["HR"]
            lr_ent += value["entitlement"]["LR"]
        end
    end

    sw_state.hr_entitlement = hr_ent
    sw_state.lr_entitlement = lr_ent
    sw_state.farm_hr_entitlement = farm_hr
    sw_state.farm_lr_entitlement = farm_lr
    sw_state.other_hr_entitlements = other_hr
    sw_state.other_lr_entitlements = other_lr
    sw_state.env_state.hr_entitlement = env_hr - sw_state.env_state.fixed_annual_losses
    sw_state.env_state.lr_entitlement = env_lr

    return nothing
end

"""
    allocation_template()::Dict{String, Dict{String, Float64}}

Create allocation template dictionary structure for tracking water allocations
across different systems (campaspe, goulburn, environment, other) and reliability
levels (HR - High Reliability, LR - Low Reliability).

# Returns
- `Dict{String, Dict{String, Float64}}` : nested dictionary with system names as keys and HR/LR allocations as values
"""
function allocation_template()::Dict{String, Dict{String, Float64}}
    return Dict(
        "campaspe"=>Dict(
            "HR"=>0.0,
            "LR"=>0.0
        ),
        "goulburn"=>Dict(
            "HR"=>0.0,
            "LR"=>0.0
        ),
        "environment"=>Dict(
            "HR"=>0.0,
            "LR"=>0.0
        ),
        "other"=>Dict(
            "HR"=>0.0,
            "LR"=>0.0
        )
    )
end

"""
    additional_zone_info(total_n_weeks::Int64, total_n_years::Int64)::Dict{String, Any}

Create new dictionary instance with additional tracking information for a single zone.
This function creates fresh dictionary instances to avoid shared references between zones.

# Arguments
- `total_n_weeks` : total number of weeks for time series arrays.
- `total_n_years` : total number of years for time series arrays.

# Returns
- `Dict{String, Any}` : dictionary with zone tracking information including water orders,
  carryover states, allocations, and reserves.
"""
function additional_zone_info(total_n_weeks::Int64, total_n_years::Int64)::Dict{String, Any}
    return Dict(
        # water ordered in specific time step
        "ts_water_orders"=>Dict("campaspe"=>zeros(total_n_weeks), "goulburn"=>zeros(total_n_weeks)),
        # Carryover within year (should only decrease)
        "carryover_state"=>Dict("HR"=>0.0, "LR"=>0.0),
        "yearly_carryover"=>Dict("HR"=>zeros(total_n_years), "LR"=>zeros(total_n_years)), # Carryover over total_n_years
        # Allocated amount available
        "avail_allocation"=>allocation_template(),
        # Total vol allocated to zone
        "allocated_to_date"=>allocation_template(),
        "perc_Ent"=>allocation_template(),
        "reserves"=>Dict("HR"=>zeros(total_n_years), "op"=>zeros(total_n_years)), # Water reserves
        "zone_share"=>0.0,
    )
end
