@with_kw mutable struct GwState
    initial_gw_levels::Dict{String, Float64} = Dict("62589" => 0.0, "79324" => 0.0)
    gw_levels::Union{Dict{String, Float64}, Nothing} = nothing
    drought_count::Int64 = 0
    current_year::Int64 = 1
    sw_perc_entitlement::Float64 = 0.0
    season_start::Date = Date(1900, 7, 1) # Year is ignored
    season_end::Date = Date(1900, 4, 30) # Year is ignored
    drought_trigger::Float64 = 0.3
    max_drought_years::Int64 = 3
    zone_info::DataFrame = DataFrame()
    trigger_tables::Dict{String, Dict{String, DataFrame}} = Dict()
    zone_rows::Dict{String, BitVector} = Dict()
    carryover_period::Int64
    max_carryover_perc::Float64
    restriction_type::String
end

"""
    GwState(zone_info::DataFrame, carryover_period::Int64, max_carryover_perc::Float64, restriction_type::String, data_path::String)::GwState

GwState constructor.

# Arguments
- `zone_info` : dataframe with farming zones info.
- `carryover_period` : carryover period.
- `max_carryover_perc` : maximin carryover percentage.
- `restriction_type` : restriction_type. Can be either "default" or "coupled".
- `data_path` : full path with groundwater trigger bore information.
-
"""
function GwState(
        zone_info::DataFrame,
        carryover_period::Int64,
        max_carryover_perc::Float64,
        restriction_type::String,
        data_path::String
)::GwState
    zone_info = create_zone_info(zone_info)
    trigger_tables = create_trigger_tables(zone_info, data_path)
    zone_rows = create_zone_rows(zone_info)

    return GwState(zone_info=zone_info, trigger_tables=trigger_tables, zone_rows=zone_rows,
       carryover_period=carryover_period, max_carryover_perc=max_carryover_perc, restriction_type=restriction_type
    )
end

"""
    create_zone_info(zone_info::DataFrame)::DataFrame

Setup zone_info, translating some types and creating new columns.

# Arguments
- `zone_info` : data frame with zone information.
"""
function create_zone_info(zone_info::DataFrame)::DataFrame
    zone_info = zone_info[:, ["ZoneID", "TRADING_ZO", "gw_Ent", "TrigBore"]]
    zone_info.ZoneID = string.(zone_info.ZoneID)

    zone_info.gw_triggerbore_level .= 0.0 # Current trigger level for bore
    zone_info.gw_proportion .= 0.0        # Proportion of Entitlement for a season
    zone_info.gw_alloc .= 0.0             # Total allocated volume for a season
    zone_info.gw_carryover .= 0.0         # Carryover for a season
    zone_info.gw_used .= 0.0              # Cumulative counter of GW used
    return zone_info
end

"""
    create_trigger_tables(zone_info::DataFrame, data_path::String)::Dict{String, Dict{String, DataFrame}}

Create trigger_tables, loading files based on the data_path.

# Arguments
- `zone_info` : data frame with zone information.
- `data_path` : path to groundwater trigger data.
"""
function create_trigger_tables(zone_info::DataFrame, data_path::String)::Dict{String, Dict{String, DataFrame}}
    zone_trigbores = unique(zone_info.TrigBore)
    trigger_bores = filter(isdir, readdir(joinpath(data_path, "trigger_bores"), join=true))

    if length(trigger_bores) != length(zone_trigbores)
        throw(ArgumentError("Number of trigger bores in shapefile do not match number of data folders"))
    end

    result = Dict()
    for bore in trigger_bores
        tmp = Dict()
        tmp["current"] = DataFrame(CSV.File(joinpath(bore, "current_trigger.csv")), ["Depth", "Proportion"])
        tmp["drought"] = DataFrame(CSV.File(joinpath(bore, "drought_trigger.csv")), ["Depth", "Proportion"])
        tmp["nondrought"] = DataFrame(CSV.File(joinpath(bore, "nondrought_trigger.csv")), ["Depth", "Proportion"])

        result[basename(bore)] = tmp
    end
    return result
end

"""
    create_zone_rows(zone_info::DataFrame)::Dict{String, BitVector}

Create zone_rows based on zone_info.

# Arguments
- `zone_info` : data frame with zone information.
"""
function create_zone_rows(zone_info::DataFrame)::Dict{String, BitVector}
    result = Dict()

    for bore_id in unique(zone_info.TrigBore)
        zones = zone_info[zone_info.TrigBore .== bore_id, "ZoneID"]
        zones = lowercase(join(vcat(zones, [bore_id]), "|"))

        result[zones] = zone_info.TrigBore .== bore_id
    end

    return result
end
