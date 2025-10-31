import CampaspeIntegratedModel: Agtor, Streamfall

"""
    run_scenarios(scenarios::DataFrame)::Vector{NamedTuple}

Run the integrated model for multiple scenarios and collect results.

# Arguments
- `scenarios::DataFrame` : DataFrame where each row represents a scenario configuration

# Returns
- `Vector{NamedTuple}` : Vector of results, one per scenario, where each element contains:
  - `:scenario_id` : Row index of the scenario (Int)
  - `:farm_option` : Farm adaptation option applied (String)
  - `:policy_option` : Policy adaptation option applied (String)
  - `:farm_results` : DataFrame with farm model results by zone and year
  - `:dam_level` : Vector of dam water levels (mAHD) by day
  - `:recreational_index` : Vector of recreational index by day
  - `:env_orders` : Vector of environmental orders by week
"""
function run_scenarios(scenarios::DataFrame, save::Bool = true)::Vector{NamedTuple}
    if save
        result_dir = save_inputs(scenarios)
    end

    n_scenarios = nrow(scenarios)
    results = Vector{NamedTuple}(undef, n_scenarios)

    @info "Running $(n_scenarios) scenarios"
    for i in 1:n_scenarios
        scenario = scenarios[i, :]
        farm_opt = get(scenario, :farm_option, "default")
        policy_opt = get(scenario, :policy_option, "default")

        @info "Running scenario $(i)/$(n_scenarios): farm_option='$(farm_opt)', policy_option='$(policy_opt)'"
        farm_results, dam_level, rec_index, env_orders = run_model(scenario)

        results[i] = (
            scenario_id = i,
            farm_option = farm_opt,
            policy_option = policy_opt,
            farm_results = farm_results,
            dam_level = dam_level,
            recreational_index = rec_index,
            env_orders = env_orders
        )
    end

    @info "Completed all $(n_scenarios) scenarios"
    if save
        save_outputs(results, result_dir, Date(scenarios[1, :start_day]))
    end
    return results
end

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
  - First element: DataFrame of farm model results for each zone` (by harvest year and zone)
  - Second element: Vector of dam water levels over the simulation period (mAHD - meter above sea level) (by day)
  - Third element: Vector of recreational index over the simulation period (by day)
  - Forth element: Vector of environmental orders over the simulation period (by week)
"""
function run_model(scenario::DataFrameRow)::Tuple{DataFrame,Vector{Float64},Vector{Float64},Vector{Float64}}
    # Load climate data farm
    farm_climate_path = scenario[:farm_climate_path]
    farm_climate = DataFrame(CSV.File(farm_climate_path))

    start_idx = findfirst(isequal(Date(scenario[:start_day])), farm_climate.Date)
    end_idx = findfirst(isequal(Date(scenario[:end_day])), farm_climate.Date)
    farm_climate = farm_climate[start_idx:end_idx, :]

    # Setup surface water model
    sw_climate = CSV.read(scenario[:sw_climate_path], DataFrame; comment="#")

    start_idx = findfirst(isequal(Date(scenario[:start_day])), sw_climate.Date)
    end_idx = findfirst(isequal(Date(scenario[:end_day])), sw_climate.Date)
    sw_climate = sw_climate[start_idx:end_idx, :]

    sw_climate = CampaspeIntegratedModel.Streamfall.Climate(sw_climate, "_rain", "_evap")
    sn = CampaspeIntegratedModel.Streamfall.load_network("Campaspe", scenario[:sw_network_path])

    # Setup policy model
    if isempty(scenario[:dam_extractions_path])
        dam_extraction = DataFrame("Date" => sw_climate.climate_data.Date, "406000_releases_[ML]" => 0.0)
    else
        dam_extraction = DataFrame(CSV.File(scenario[:dam_extractions_path]))
    end

    # Assume daily data for now
    # model_step::Day = farm_climate.Date[2] - farm_climate.Date[1]
    model_run_range::Vector{Dates.Date} = farm_climate.Date

    policy_state = CampaspeIntegratedModel.PolicyState(
        scenario[:policy_path], model_run_range, scenario[:goulburn_alloc], dam_extraction,
        scenario[:carryover_period], scenario[:max_carryover_perc], scenario[:restriction_type],
    )

    # Setup farm model
    farm_spec = Agtor.load_spec(scenario[:farm_path])
    basin_spec = farm_spec[:Campaspe]
    zone_specs = basin_spec[:zone_spec]
    OptimizingManager = Agtor.EconManager("optimizing")
    manage_zones = ((OptimizingManager, Tuple(collect(keys(zone_specs)))),)
    campaspe_basin = Agtor.Basin(
        name=basin_spec[:name], zone_spec=zone_specs, managers=manage_zones,
        climate_data=farm_climate_path
    )
    # Update climate data and crop dates to align with simulation period
    update_climate_data!(campaspe_basin, farm_climate.Date[1], farm_climate.Date[end])
    update_crop_dates!(campaspe_basin, farm_climate.Date[1])
    # Create struct with dates that define farm model run
    farm_step = scenario[:farm_step] # default is fortnight
    farm_dates = farm_climate.Date[1]:Dates.Day(farm_step):farm_climate.Date[end]
    farm_state = FarmState(farm_dates=farm_dates)

    ## Additional parameters
    run_length = length(farm_climate.Date)
    rolling_avg_years = 3
    farm_sw_orders_orig = Dict{String,Float64}((zone_id => 0.0) for zone_id in policy_state.gw_state.zone_info.ZoneID)
    farm_sw_orders = copy(farm_sw_orders_orig)
    farm_gw_orders_ML = copy(farm_sw_orders_orig)

    # Initialize groundwater model outputs (used when ts == run_length and groundwater model doesn't run)
    exchange = Dict{String,Float64}()
    trigger_head = Dict{String,Float64}()
    avg_gw_depth = Dict{String,Float64}()

    # Apply farm and policy adaptation options if specified
    if !isempty(get(scenario, :farm_option, ""))
        implement_farm_option!(scenario[:farm_option], campaspe_basin, scenario[:farm_path], farm_state, policy_state)
    end
    if !isempty(get(scenario, :policy_option, ""))
        implement_policy_option!(scenario[:policy_option], policy_state, farm_state, sn, campaspe_basin)
    end

    @info "Starting model run"
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
        water_release, farm_allocs = update_policy(
            policy_state, ts, dt,
            farm_sw_orders, farm_gw_orders_ML,
            dam_volume(sn, ts), dam_rolling_level, rochester_flow(sn), proj_inflow(sn, ts), trigger_head, farm_step
        )

        # Set dam release for all days in next fortnight and reset orders
        if !isa(water_release, Bool)
            # Python-based implementation:
            # update_policy() returns false if the component did not run.
            # If it is a boolean, then no water was released, so this if-block can be
            # skipped.
            was_released = (water_release > 0.0)
            not_zero_release = !isapprox(water_release, 0.0; atol=1e-6)
            if was_released && not_zero_release
                end_date = (ts + farm_step <= nrow(dam_extraction)) ? ts + farm_step : size(dam_extraction)[1]
                dam_extraction[(ts+1):(end_date), "406000_releases_[ML]"] .+= water_release
                farm_sw_orders = copy(farm_sw_orders_orig) # reset farm sw orders
            end
        end

        farm_gw_orders_ML = copy(farm_sw_orders_orig) # reset farm gw orders

        # Run farm model every fortnight
        farm_sw_orders, farm_gw_orders_ML = update_farm(campaspe_basin, avg_gw_depth, farm_allocs, dt, ts, farm_state)
    end

    farm_results = parse_farm_results(Agtor.collect_results(campaspe_basin))
    dam_level_ts = dam_level(sn)

    @info "Finished run"
    return farm_results, dam_level_ts, recreational_index(dam_level_ts), policy_state.sw_state.env_orders
end
