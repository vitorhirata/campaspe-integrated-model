function save_inputs(scenarios::DataFrame, results_dir::String = "results")::String
    if !isdir(results_dir)
        mkdir(results_dir)
    end
    timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
    run_dir = joinpath(results_dir, timestamp)
    mkdir(run_dir)
    CSV.write(joinpath(run_dir, "input_scenarios.csv"), scenarios)

    @info "Results will be saved to: $(run_dir)"
    return run_dir
end

"""
    save_outputs(results::Vector{NamedTuple}, result_dir::String, start_date::Date; policy_step::Int=7)::Nothing

Save model outputs to CSV files in the result directory.

# Arguments
- `results::Vector{NamedTuple}` : Vector of scenario results from run_scenarios
- `result_dir::String` : Directory path where results will be saved
- `start_date::Date` : Start date of the simulation period
- `policy_step::Int` : Timestep for ecological index in days (default: 7 for weekly)
"""
function save_outputs(
    results::Vector{NamedTuple}, result_dir::String, start_date::Date; policy_step::Int=7
)::Nothing
    farm_dir = joinpath(result_dir, "farm")
    mkdir(farm_dir)

    for result in results
        CSV.write(joinpath(farm_dir, "scenario_$(result.scenario_id).csv"), result.farm_results)
    end

    # Generate date ranges based on actual data lengths
    n_daily = length(results[1].dam_level)
    n_policy = length(results[1].env_orders)
    daily_dates = collect(start_date:Day(1):(start_date + Day(n_daily - 1)))
    policy_dates = collect(start_date:Day(policy_step):(start_date + Day(policy_step * (n_policy - 1))))

    dam_level_df = DataFrame(date = daily_dates)
    rec_index_df = DataFrame(date = daily_dates)
    eco_index_df = DataFrame(date = policy_dates)

    for result in results
        col_name = "scenario_$(result.scenario_id)"
        dam_level_df[!, col_name] = result.dam_level
        rec_index_df[!, col_name] = result.recreational_index
        eco_index_df[!, col_name] = result.env_orders
    end

    # Save time series CSVs
    CSV.write(joinpath(result_dir, "dam_level.csv"), dam_level_df)
    CSV.write(joinpath(result_dir, "recreational_index.csv"), rec_index_df)
    CSV.write(joinpath(result_dir, "ecological_index.csv"), eco_index_df)

    @info "Outputs saved successfully to $(result_dir)"
    return nothing
end
