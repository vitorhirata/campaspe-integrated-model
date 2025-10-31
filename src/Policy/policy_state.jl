@with_kw mutable struct PolicyState
    sw_cap::Float64 = 1.0
    gw_cap::Float64 = 0.6
    sw_state::SwState
    gw_state::GwState
end

"""
    PolicyState(data_path::String, model_run_range::StepRange{Date, Period}, goulburn_alloc_scenario::String, dam_ext::DataFrame, carryover_period::Int64, max_carryover_perc::Float64, restriction_type::String)::PolicyState

PolicyState constructor.

# Arguments
- `data_path` : full path with zone and groundwater trigger bore information.
- `model_run_range` : date range of model execution.
- `goulburn_alloc_scenario` : allocation scenario for the Goulburn catchment.
- `dam_ext` : water extractions not accounted for by discharge.
- `carryover_period` : carryover period.
- `max_carryover_perc` : maximin carryover percentage.
- `restriction_type` : restriction_type. Can be either "default" or "coupled".
"""
function PolicyState(
    data_path::String,
    model_run_range::Union{StepRange{Date, Period}, Vector{Date}},
    goulburn_alloc_scenario::String,
    dam_ext::DataFrame,
    carryover_period::Int64,
    max_carryover_perc::Float64,
    restriction_type::String
)::PolicyState
    farm_zone_info, env_sys, other_sys, zone_df = zonal_info(data_path)

    gw_state = GwState(zone_df, carryover_period, max_carryover_perc, restriction_type, data_path)
    sw_state = SwState(model_run_range, farm_zone_info, goulburn_alloc_scenario, deepcopy(dam_ext), env_sys, other_sys)

    return PolicyState(sw_state=sw_state, gw_state=gw_state)
end

"""
    zonal_info(zone_data_path::String)::Tuple{Dict{String, Any}, DataFrame, DataFrame, DataFrame}

Generate a dictionary of collated zonal information from shapefiles and CSV data.

Reads farm zone shapefile, agricultural area data, and calculates proportional
water entitlements based on cropping areas and trading zones.

# Returns
- `Tuple{Dict{String, Any}, DataFrame, DataFrame, DataFrame}` : (farm_zone_info, env_systems, other_systems, zone_df)
  - farm_zone_info: dictionary with zone names as keys, containing entitlement and area information
  - env_systems: DataFrame with environmental water delivery systems
  - other_systems: DataFrame with other water delivery systems
  - zone_df: processed DataFrame with all calculated fields
"""
function zonal_info(zone_data_path::String)::Tuple{Dict{String, Any}, DataFrame, DataFrame, DataFrame}
    # Read farm zone shapefile
    farm_zone_path = joinpath(zone_data_path, "farm_info.csv")
    zone_df = DataFrame(CSV.File(farm_zone_path, types=Dict("ZoneID" => String, "TrigBore" => String)))

    # Read agricultural area CSV and convert ZoneID to string
    ag_area_path = joinpath(zone_data_path, "areas_by_crop_type.csv")
    ag_area = DataFrame(CSV.File(ag_area_path, types=Dict("ZoneID" => String)))
    ag_area .= coalesce.(ag_area, 0)  # Replace missing values by 0

    # Merge agricultural area data with zone shapefile
    zone_df = leftjoin(zone_df, ag_area, on=:ZoneID)

    # Calculate water system aggregations
    # Filter out rows with missing WatSystem before groupby (matching Python's dropna=True behavior)
    zone_df_filtered = filter(row -> !ismissing(row.WatSystem), zone_df)

    # Group by WatSystem to get max wat_HR (Campaspe Entitlement for each SW zone)
    water_systems = combine(groupby(zone_df_filtered, :WatSystem), :wat_HR => maximum => :water_ent)

    # Group by WatSystem to sum agric_ha (Cropping area for each SW Zone)
    agri_area = combine(groupby(zone_df_filtered, :WatSystem), :agric_ha => sum => :area)

    # Combine into system_area DataFrame
    system_area = leftjoin(agri_area, water_systems, on=:WatSystem)

    # Calculate groundwater proportional area by trading zone
    gw_area = combine(groupby(zone_df, :TRADING_ZO), :zone_ha => sum => :zone_ha_sum)

    # Add calculated columns to zone_df
    zone_df[!, :watsys_agri_area] = zeros(nrow(zone_df))
    zone_df[!, :gw_Ent] = zeros(nrow(zone_df))
    zone_df[!, :prop_crop_area] = zeros(nrow(zone_df))

    # Calculate proportional values for each zone
    for (idx, row) in enumerate(eachrow(zone_df))
        if ismissing(row.WatSystem) || isnothing(row.WatSystem)
            zone_df[idx, :watsys_agri_area] = 0.0
            gw_proportional_area = 0.0
        else
            # Find the system area for this water system
            sys_match = filter(r -> r.WatSystem == row.WatSystem, system_area)
            if nrow(sys_match) > 0
                zone_df[idx, :watsys_agri_area] = sys_match[1, :area]
            else
                zone_df[idx, :watsys_agri_area] = 0.0
            end

            # Calculate groundwater proportional area
            gw_match = filter(r -> r.TRADING_ZO == row.TRADING_ZO, gw_area)
            if nrow(gw_match) > 0 && gw_match[1, :zone_ha_sum] > 0
                gw_proportional_area = row.zone_ha / gw_match[1, :zone_ha_sum]
            else
                gw_proportional_area = 0.0
            end
        end

        # Calculate groundwater entitlement
        zone_df[idx, :gw_Ent] = row.wat_GW * gw_proportional_area

        # Calculate proportional crop area
        prop_area = row.agric_ha / row.zone_ha
        if isinf(prop_area) || isnan(prop_area)
            zone_df[idx, :prop_crop_area] = 0.0
        else
            zone_df[idx, :prop_crop_area] = prop_area
        end
    end

    # Add Camp_HR_Ent and Camp_LR_Ent columns (these should come from the shapefile or be calculated)
    # Based on Python code, these appear to be proportional entitlements
    # For now, assuming they might need to be calculated or are in the shapefile
    if !hasproperty(zone_df, :Camp_HR_Ent)
        zone_df[!, :Camp_HR_Ent] = zone_df.wat_HR .* zone_df.prop_crop_area
    end
    if !hasproperty(zone_df, :Camp_LR_Ent)
        zone_df[!, :Camp_LR_Ent] = zone_df.wat_LR .* zone_df.prop_crop_area
    end

    # Adjust Goulburn entitlements based on proportional crop area
    zone_df[!, :goul_HR] = (zone_df.agric_ha ./ zone_df.zone_ha) .* zone_df.goul_HR
    zone_df[!, :goul_LR] = (zone_df.agric_ha ./ zone_df.zone_ha) .* zone_df.goul_LR

    # Replace NaN values with 0
    zone_df[!, :goul_HR] = coalesce.(zone_df.goul_HR, 0.0)
    zone_df[!, :goul_LR] = coalesce.(zone_df.goul_LR, 0.0)

    # Add Goul_HR_Ent and Goul_LR_Ent if not present
    if !hasproperty(zone_df, :Goul_HR_Ent)
        zone_df[!, :Goul_HR_Ent] = zone_df.goul_HR
    end
    if !hasproperty(zone_df, :Goul_LR_Ent)
        zone_df[!, :Goul_LR_Ent] = zone_df.goul_LR
    end

    zone_df[!, :Goul_HR_Ent] = coalesce.(zone_df.Goul_HR_Ent, 0.0)
    zone_df[!, :Goul_LR_Ent] = coalesce.(zone_df.Goul_LR_Ent, 0.0)

    # Calculate total zone entitlements weighted by crop area
    zone_df[!, :zone_crop_HR] = zone_df.Camp_HR_Ent .+ zone_df.Goul_HR_Ent
    zone_df[!, :zone_crop_LR] = zone_df.Camp_LR_Ent .+ zone_df.Goul_LR_Ent

    # Read environmental and other water delivery systems
    env_systems_path = joinpath(zone_data_path, "environmental_systems.csv")
    env_systems = DataFrame(CSV.File(env_systems_path))

    other_systems_path = joinpath(zone_data_path, "other_delivery_systems.csv")
    other_systems = DataFrame(CSV.File(other_systems_path))

    # Build farm_zone_info dictionary
    farm_zone_info = Dict{String, Any}()

    for row in eachrow(zone_df)
        farm_zone_info[row.FULLNAME] = Dict{String, Any}(
            "entitlement" => Dict{String, Float64}(
                "camp_HR" => row.Camp_HR_Ent,
                "camp_LR" => row.Camp_LR_Ent,
                "goul_HR" => row.Goul_HR_Ent,
                "goul_LR" => row.Goul_LR_Ent,
                "farm_HR" => row.zone_crop_HR,
                "farm_LR" => row.zone_crop_LR
            ),
            "water_system" => ismissing(row.WatSystem) ? nothing : row.WatSystem,
            "regulation_zone" => row.SurfaceTra,
            "areas" => Dict{String, Float64}(
                "crop_ha" => row.agric_ha,
                "zone_ha" => row.zone_ha
            ),
            "name" => row.FULLNAME,
            "zone_id" => row.ZoneID
        )
    end

    return farm_zone_info, env_systems, other_systems, zone_df
end
