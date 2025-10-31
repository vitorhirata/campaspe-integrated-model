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

    for i in 1:length(results)
        result = results[i]
        gdf = groupby(result.farm_results[:,["zone_id", "Date", "Dollar per Ha"]], :Date)

        push!(final_df, [
            i,
            result.farm_option,
            result.policy_option,
            mean(combine(gdf, "Dollar per Ha" => mean)[:,"Dollar per Ha_mean"]),
            mean(combine(gdf, "Dollar per Ha" => var)[:,"Dollar per Ha_var"]),
            mean(result.env_orders),
            mean(result.recreational_index)]
        )
    end

    cols = ["mean_profit_per_ha", "var_profit_per_ha", "ecological_index", "recreational_index"]
    for col in cols
        final_df[:,"change_" * col] = (final_df[:,col] .- final_df[1,col]) / final_df[1,col]
    end

    return final_df
end
function constraints_change(results_dir::String)::DataFrame
    # Load input scenarios to get farm and policy options
    input_scenarios = CSV.read(joinpath(results_dir, "input_scenarios.csv"), DataFrame)

    # Load time series data
    ecological_df = CSV.read(joinpath(results_dir, "ecological_index.csv"), DataFrame)
    recreational_df = CSV.read(joinpath(results_dir, "recreational_index.csv"), DataFrame)

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

        # Group by date and compute mean and variance of profit per hectare
        gdf = groupby(farm_results[:, ["zone_id", "Date", "Dollar per Ha"]], :Date)
        profit_stats = combine(gdf,
            "Dollar per Ha" => mean => "Dollar per Ha_mean",
            "Dollar per Ha" => var => "Dollar per Ha_var"
        )

        # Get farm and policy options
        farm_opt = ismissing(input_scenarios[i,:farm_option]) ? "" : input_scenarios[i, :farm_option]
        policy_opt = ismissing(input_scenarios[i,:policy_option]) ? "" : input_scenarios[i, :policy_option]

        # Add row to final DataFrame
        push!(final_df, [
            i,
            farm_opt,
            policy_opt,
            mean(profit_stats[:, "Dollar per Ha_mean"]),
            mean(profit_stats[:, "Dollar per Ha_var"]),
            mean(ecological_df[:, "scenario_$(i)"]),
            mean(recreational_df[:, "scenario_$(i)"])
        ])
    end

    cols = ["mean_profit_per_ha", "var_profit_per_ha", "ecological_index", "recreational_index"]
    for col in cols
        final_df[:, "change_" * col] = (final_df[:, col] .- final_df[1, col]) / final_df[1, col]
    end

    return final_df
end

