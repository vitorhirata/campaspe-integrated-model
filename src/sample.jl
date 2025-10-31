"""
    sample_individual_options(start_day::String, end_day::String, climate_type::String)::DataFrame

Generate scenarios DataFrame for testing individual farm and policy adaptation options.
Creates a baseline scenario plus one scenario for each farm and policy option, allowing
evaluation of individual adaptation strategies.

# Arguments
- `start_day::String` : Start date of simulation period (format: "YYYY-MM-DD")
- `end_day::String` : End date of simulation period (format: "YYYY-MM-DD")
- `climate_type::String` : Climate scenario type (e.g., "historic", "best_case_rcp45_2016-2045")

# Returns
- `DataFrame` : Scenarios DataFrame with 13 rows (1 baseline + 6 farm options + 6 policy options)
"""
function sample_individual_options(start_day::String, end_day::String, climate_type::String)::DataFrame
    if climate_type == "historic"
        farm_climate_path = "data/climate/historic/farm_climate.csv"
        sw_climate_path = "data/climate/historic/sw_climate.csv"
    else
        farm_climate_path = "data/climate/$(climate_type)_2016-2045/farm_climate.csv"
        sw_climate_path = "data/climate/$(climate_type)_2016-2045/sw_climate.csv"
    end
    scenario = DataFrame(Dict(
        :start_day => start_day,
        :end_day => end_day,
        # Farm parameters
        :farm_climate_path => farm_climate_path,
        :farm_path => "data/farm/basin",
        :farm_step => 14,
        # Policy parameters
        :policy_path => "data/policy",
        :goulburn_alloc => "high",
        :restriction_type => "default",
        :max_carryover_perc => 0.25,
        :carryover_period => 1,
        :dam_extractions_path => "",
        # Surface water parameters
        :sw_climate_path => sw_climate_path,
        :sw_network_path => "data/surface_water/campaspe_network.yml",
    ))

    farm_options = ["improve_irrigation_efficiency", "implement_solar_panels", "adopt_drought_resistant_crops",
        "improve_soil_TAW", "increase_farm_entitlements", "decrease_farm_entitlements"
    ]
    policy_options = ["implement_coupled_allocations", "increase_environmental_water", "increase_water_price",
        "raise_dam_level", "subsidise_irrigation_efficiency", "subsidise_solar_pump"
    ]

    n_scenarios = 1 + length(farm_options) + length(policy_options)
    scenario = vcat([scenario for _ in 1:n_scenarios]...)
    scenario.farm_option .= ""
    scenario.policy_option .= ""

    for (i, farm_opt) in enumerate(farm_options)
        scenario[1 + i, :farm_option] = farm_opt
    end
    for (i, policy_opt) in enumerate(policy_options)
        scenario[1 + length(farm_options) + i, :policy_option] = policy_opt
    end

    return scenario
end
