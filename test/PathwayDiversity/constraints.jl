using Test
using CampaspeIntegratedModel
using DataFrames
using Statistics

@testset "constraints_change functionality" begin
    # Mock farm results
    farm_results_1 = DataFrame(
        :zone_id => repeat(["1", "2"], 2),
        :Date => repeat(["2021-01-01", "2022-01-01"], inner=2),
        Symbol("Dollar per Ha") => [800.0, 850.0, 820.0, 870.0]
    )
    farm_results_2 = DataFrame(
        :zone_id => repeat(["1", "2"], 2),
        :Date => repeat(["2021-01-01", "2022-01-01"], inner=2),
        Symbol("Dollar per Ha") => [850.0, 900.0, 870.0, 920.0]  # Higher profit
    )
    farm_results_3 = DataFrame(
        :zone_id => repeat(["1", "2"], 2),
        :Date => repeat(["2021-01-01", "2022-01-01"], inner=2),
        Symbol("Dollar per Ha") => [780.0, 830.0, 800.0, 850.0]  # Lower profit
    )
    # Mock results vector - explicitly type as Vector{NamedTuple}
    results = Vector{NamedTuple}([
        (
            scenario_id = 1,
            farm_option = "",
            policy_option = "",
            farm_results = farm_results_1,
            dam_level = fill(150.0, 100),
            recreational_index = fill(0.8, 100),
            env_orders = fill(10.0, 20)
        ),
        (
            scenario_id = 2,
            farm_option = "improve_irrigation_efficiency",
            policy_option = "",
            farm_results = farm_results_2,
            dam_level = fill(152.0, 100),
            recreational_index = fill(0.85, 100),
            env_orders = fill(10.5, 20)
        ),
        (
            scenario_id = 3,
            farm_option = "",
            policy_option = "increase_environmental_water",
            farm_results = farm_results_3,
            dam_level = fill(148.0, 100),
            recreational_index = fill(0.75, 100),
            env_orders = fill(12.0, 20)
        )
    ])

    metrics = CampaspeIntegratedModel.constraints_change(results)

    @test nrow(metrics) == 3
    @test metrics.scenario_id == [1, 2, 3]
    @test metrics[1, :farm_option] == ""
    @test metrics[1, :policy_option] == ""
    @test metrics[2, :farm_option] == "improve_irrigation_efficiency"
    @test metrics[2, :policy_option] == ""
    @test metrics[3, :farm_option] == ""
    @test metrics[3, :policy_option] == "increase_environmental_water"
    @test metrics[1, :change_mean_profit_per_ha] == 0.0
    @test metrics[1, :change_var_profit_per_ha] == 0.0
    @test metrics[1, :change_ecological_index] == 0.0
    @test metrics[1, :change_recreational_index] == 0.0
    @test metrics[1, :mean_profit_per_ha] > 0.0
    @test metrics[1, :var_profit_per_ha] >= 0.0
    @test metrics[1, :ecological_index] > 0.0
    @test metrics[1, :recreational_index] > 0.0
    @test metrics[2, :change_mean_profit_per_ha] > 0.0
    @test metrics[3, :change_ecological_index] > 0.0
    baseline_profit = metrics[1, :mean_profit_per_ha]
    scenario2_profit = metrics[2, :mean_profit_per_ha]
    expected_change = (scenario2_profit - baseline_profit) / baseline_profit
    @test metrics[2, :change_mean_profit_per_ha] ≈ expected_change atol=1e-8
end
