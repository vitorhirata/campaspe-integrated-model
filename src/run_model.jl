"""
    run_model(scenario::DataFrameRow)::Tuple{Dict, Vector{Float64}}

Run the Campaspe integrated water resource model.
Integrates four coupled submodels to simulate water resource dynamics.
1. Farm model (Agtor.jl) - Agricultural water demand and irrigation decisions
2. Surface water model (Streamfall.jl) - River and dam hydrology
3. Groundwater model - Aquifer dynamics and extraction (TODO: not yet implemented)
4. Policy model - Water allocation and environmental flow rules

The model runs on a daily timestep, with some models running on a coarser
resolution. Each internal models is responsible to check if it should be runned.

# Arguments
- `scenario::DataFrameRow` : Configuration row containing all model parameters and file paths
  - `:farm_climate_path` : Path to CSV with farm climate data (Date, rainfall, evaporation)
  - `:start_day` : Start date for model run (String or Date)
  - `:end_day` : End date for model run (String or Date)
  - `:dam_extractions_path` : Path to CSV with historical dam extractions
  - `:policy_path` : Path to water allocation policy configuration
  - `:goulburn_alloc` : Goulburn water allocation parameters
  - `:carryover_period` : Carryover period for water allocations
  - `:max_carryover_perc` : Maximum carryover percentage
  - `:restriction_type` : Type of water restrictions to apply
  - `:farm_path` : Path to farm basin specification
  - `:farm_step` : Timestep for farm model runs in days (e.g., 14 for fortnightly)
  - `:sw_climate_path` : Path to surface water climate data
  - `:sw_network_path` : Path to surface water network specification

# Returns
- `Tuple{Dict, Vector{Float64}}` :
  - First element: Dictionary of farm model results for each zone`
  - Second element: Vector of dam water levels over the simulation period (ML)
"""
function run_model(scenario::DataFrameRow)::Tuple{Dict, Vector{Float64}}
    # Load climate data farm
    farm_climate_path = scenario[:farm_climate_path]
    farm_climate = DataFrame(CSV.File(farm_climate_path))

    start_idx = findfirst(isequal(Date(scenario[:start_day])), farm_climate.Date)
    end_idx = findfirst(isequal(Date(scenario[:end_day])), farm_climate.Date)
    farm_climate = farm_climate[start_idx:end_idx, :]

    # Setup policy model
    dam_ext = DataFrame(CSV.File(scenario[:dam_extractions_path]))
    model_step::Day = farm_climate.Date[2] - farm_climate.Date[1]
    model_run_range::StepRange{Date, Period} = farm_climate.Date[1]:model_step:farm_climate.Date[end]

    policy_state = CampaspeIntegratedModel.PolicyState(
        scenario[:policy_path], model_run_range, scenario[:goulburn_alloc], dam_ext,
        scenario[:carryover_period], scenario[:max_carryover_perc], scenario[:restriction_type],
    )

    # Setup farm model
    basin_spec = CampaspeIntegratedModel.Agtor.load_spec(scenario[:farm_path])[:Campaspe]
    zone_specs = basin_spec[:zone_spec]
    OptimizingManager = CampaspeIntegratedModel.Agtor.EconManager("optimizing")
    manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))), )
    campaspe_basin = CampaspeIntegratedModel.Agtor.Basin(
        name=basin_spec[:name], zone_spec=zone_specs, managers=manage_zones,
        climate_data=farm_climate_path
    )
    # Create struct with dates that define model run
    farm_step = scenario[:farm_step] # default is fortnight
    farm_dates = farm_climate.Date[1]:Dates.Day(farm_step):farm_climate.Date[end]
    farm_state = FarmState(farm_dates = farm_dates)

    # Setup surface water model
    sw_climate = CampaspeIntegratedModel.Streamfall.Climate(scenario[:sw_climate_path], "_rain", "_evap")
    sn = CampaspeIntegratedModel.Streamfall.load_network("Campaspe", scenario[:sw_network_path])

    ## Additional parameters
    run_length = length(farm_climate.Date)
    rolling_avg_years = 3
    dam_extraction = DataFrame("Date" => sw_climate.climate_data.Date, "406000_releases_[ML]" => 0.0)
    farm_sw_orders_orig = Dict{String, Float64}((zone_id => 0.0) for zone_id in policy_state.gw_state.zone_info.ZoneID)
    farm_sw_orders = copy(farm_sw_orders_orig)
    farm_gw_orders_ML = copy(farm_sw_orders_orig)

    # Initialize groundwater model outputs (used when ts == run_length and groundwater model doesn't run)
    exchange = Dict{String, Float64}()
    trigger_head = Dict{String, Float64}()
    avg_gw_depth = Dict{String, Float64}()

    # Setup logging

    println("Starting model run.")
    for (ts, dt) in enumerate(model_run_range)
        next_day = ts + 1

        if ts < run_length
            # run groundwater model # TODO
            exchange, trigger_head, avg_gw_depth = update_groundwater()

            # Run surface water model
            add_ext = get_dam_extraction(policy_state.sw_state, dt)
            dam_extraction[ts, "406000_releases_[ML]"] += add_ext
            update_surface_water(sn, sw_climate, ts, dt, dam_extraction, exchange)
        end

        # Run policy model
        dam_rolling_level = get_rolling_dam_level(dt, rolling_avg_years, dam_level(sn), sw_climate.climate_data.Date)
        dam_release, farm_allocs = update_policy(
            policy_state, ts, dt,
            farm_sw_orders, farm_gw_orders_ML,
            dam_volume(sn, ts), dam_rolling_level, rochester_flow(sn), proj_inflow(sn, ts), trigger_head, farm_step
        )

        # Set dam release for all days in next fortnight and reset orders
        if isa(dam_release, Bool) ? dam_release : ((dam_release > 0) && !isapprox(dam_release, 0.0; atol=1e-6))
            end_date = (ts+farm_step <= nrow(dam_extraction)) ? ts+farm_step : size(dam_extraction)[1]
            dam_extraction[(ts+1):(end_date), "406000_releases_[ML]"] .+= dam_release
            farm_sw_orders = copy(farm_sw_orders_orig) # reset farm sw orders
        end
        farm_gw_orders_ML = copy(farm_sw_orders_orig) # reset farm gw orders

        # Run farm model every fortnight
        farm_sw_orders, farm_gw_orders_ML = update_farm(campaspe_basin, avg_gw_depth, farm_allocs, dt, ts, farm_state)
    end

    farm_results = CampaspeIntegratedModel.Agtor.collect_results(campaspe_basin)
    dam_level_ts = sn["406000"][2].level
    return farm_results, dam_level_ts
end
