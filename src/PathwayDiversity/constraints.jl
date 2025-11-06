using Base.Iterators
"""
    constraints_change(results::Vector{NamedTuple})::DataFrame
    constraints_change(results_dir::String)::DataFrame

Receive as input full results or path to saved results. Compute performance metrics and changes relative to baseline.

# Arguments
- `results::Vector{NamedTuple}` : Vector with complete results.
- `results_dir::String` : Path to results directory

# Returns
- `DataFrame` : Summary metrics with constraints and change in constraints.
"""
function constraints_change(results::Vector{NamedTuple})::DataFrame
    final_df = DataFrame(
          :scenario_id => Int[],
          :farm_option => String[],
          :policy_option => String[],
          :mean_profit_per_ha => Float64[],
          :var_profit_per_ha => Float64[],
          :ecological_index => Float64[],
          :recreational_index => Float64[]
    )
    zone_info = DataFrame(CSV.File("data/policy/farm_info.csv", types=Dict("ZoneID"=>String)))[:,["ZoneID", "Area_Ha"]]
    zone_info = zone_info[in.(zone_info.ZoneID, Ref(results[1].farm_results.zone_id)), :] # Filter only valid zone_ids

    for i in 1:length(results)
        result = results[i]
        metrics = process_scenario(result.farm_results, result.env_orders, result.recreational_index, zone_info)
        push!(final_df, [i, result.farm_option, result.policy_option, metrics[1], metrics[2], metrics[3], metrics[4]])
    end

    cols = ["mean_profit_per_ha", "var_profit_per_ha", "ecological_index", "recreational_index"]
    for col in cols
        final_df[:,"change_" * col] = (final_df[:,col] .- final_df[1,col]) / final_df[1,col]
    end

    return final_df[:,["scenario_id", "farm_option", "policy_option", ("change_" .* cols)..., cols...]]
end
function constraints_change(results_dir::String)::DataFrame
    # Load input scenarios to get farm and policy options
    input_scenarios = CSV.read(joinpath(results_dir, "input_scenarios.csv"), DataFrame)

    # Load time series data
    ecological_df = CSV.read(joinpath(results_dir, "ecological_index.csv"), DataFrame)
    recreational_df = CSV.read(joinpath(results_dir, "recreational_index.csv"), DataFrame)
    zone_info = DataFrame(CSV.File("data/policy/farm_info.csv"))[:,["ZoneID", "Area_Ha"]]

    # Get number of scenarios from input file
    n_scenarios = nrow(input_scenarios)

    # Initialize results DataFrame
    final_df = DataFrame(
        :scenario_id => Int[],
        :farm_option => String[],
        :policy_option => String[],
        :mean_profit_per_ha => Float64[],
        :var_profit_per_ha => Float64[],
        :ecological_index => Float64[],
        :recreational_index => Float64[]
    )

    # Process each scenario
    for i in 1:n_scenarios
        # Load farm results for this scenario
        farm_file = joinpath(results_dir, "farm", "scenario_$(i).csv")
        farm_results = CSV.read(farm_file, DataFrame)

        metrics = process_scenario(farm_results, ecological_df, recreational_df, zone_info)
        farm_opt = ismissing(input_scenarios[i,:farm_option]) ? "" : input_scenarios[i, :farm_option]
        policy_opt = ismissing(input_scenarios[i,:policy_option]) ? "" : input_scenarios[i, :policy_option]

        push!(final_df, [i, farm_opt, policy_opt, metrics[1], metrics[2], metrics[3], metrics[4]])
    end

    cols = ["mean_profit_per_ha", "var_profit_per_ha", "ecological_index", "recreational_index"]
    for col in cols
        final_df[:, "change_" * col] = (final_df[:, col] .- final_df[1, col]) / final_df[1, col]
    end

    return final_df[:,["farm_option", "policy_option", ("change_" .* cols)..., cols...]]
end

function process_scenario(farm_results::DataFrame, ecological_results::Vector{Float64}, recreational_results::Vector{Float64}, zone_info::DataFrame)::Vector{Float64}
    profit_mean = 0
    profit_var = 0

    for zone_id in string.(1:length(unique(farm_results.zone_id)))
        zone_farm_results = farm_results[farm_results.zone_id .== zone_id, "Dollar per Ha"]
        zone_agric_area = zone_info[zone_info.ZoneID .== zone_id, "Area_Ha"][1]

        profit_mean += (mean(zone_farm_results) * zone_agric_area)
        profit_var += (var(zone_farm_results) * zone_agric_area)
    end
    profit_mean /= sum(zone_info[:,"Area_Ha"])
    profit_var /= sum(zone_info[:,"Area_Ha"])

    n_season = length(unique(farm_results.Date))
    season_env_orders = [sum(chunk) for chunk in partition(ecological_results, ceil(Int, length(ecological_results)/n_season))]
    season_recreational_index = [mean(chunk) for chunk in partition(recreational_results, ceil(Int, length(recreational_results)/n_season))]

    return[profit_mean, profit_var, mean(season_env_orders), mean(season_recreational_index)]
end
