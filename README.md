# Campaspe Integrated Model

An integrated assessment model that includes a farm model, surface and groundwater hydrology models, and a policy model.

## Description

This code implements a simplified version of the Campaspe Integrated model published
[here](https://doi.org/10.1016/j.ejrh.2020.100669). It is parameterised to model the Lower Campaspe Catchment in North
Central Victoria.
This repository uses two submodels - Agtor.jl for the farmer model and Stremfall.jl for the surface water hydrology
model -, implements the policy model and couples these sub-models.

## Usage
On first use setup the project:
```bash
$ julia --project=.

# Activate the package manager
julia> ]

# Instantiate project and dependencies
(CampaspeIntegratedModel) pkg> instantiate
```

Example run using past climate data. All runs assume you are at the repl and in the source of the repository.
```julia-repl
using CampaspeIntegratedModel, DataFrames
scenario_past = Dict(
     :start_day => "1981-01-01",
     :end_day => "1983-01-01",
     # Farm parameters
     :farm_climate_path => "data/climate/historic/farm_climate.csv",
     :farm_path => "data/farm/basin",
     :farm_step => 14,
     # Policy parameters
     :policy_path => "data/policy",
     :goulburn_alloc => "high",
     :restriction_type => "default",
     :max_carryover_perc => 0.25,
     :carryover_period => 1,
     :dam_extractions_path => "data/policy/eppalock_extractions.csv",
     # Surface water parameters
     :sw_climate_path => "data/climate/historic/sw_climate.csv",
     :sw_network_path => "data/surface_water/campaspe_network.yml",
)
scenario_past = DataFrame(scenario_past)[1,:]
result_past = CampaspeIntegratedModel.run_model(scenario_past)
```

Example run using future climate projection:
```julia-repl
using CampaspeIntegratedModel, DataFrames

scenario_future = Dict(
     :start_day => "2024-01-01",
     :end_day => "2025-01-20",
     # Farm parameters
     :farm_climate_path => "data/climate/best_case_rcp45_2016-2045/farm_climate.csv",
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
     :sw_climate_path => "data/climate/best_case_rcp45_2016-2045/sw_climate.csv",
     :sw_network_path => "data/surface_water/campaspe_network.yml",
)
scenario_future = DataFrame(scenario_future)[1,:]
result_future = CampaspeIntegratedModel.run_model(scenario_future)
```
