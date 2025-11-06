using Test
using CampaspeIntegratedModel
using DataFrames
using Statistics

@testset "constraints_change functionality" begin
    # Mock farm results
    farm_results_1 = DataFrame(
        "zone_id" => repeat(["1", "2"], 2),
        "Date" => repeat(["2021-01-01", "2022-01-01"], inner=2),
        "Dollar per Ha" => [800.0, 850.0, 820.0, 870.0]
    )
    farm_results_2 = DataFrame(
        "zone_id" => repeat(["1", "2"], 2),
        "Date" => repeat(["2021-01-01", "2022-01-01"], inner=2),
        "Dollar per Ha" => [850.0, 900.0, 870.0, 920.0]  # Higher profit
    )
    farm_results_3 = DataFrame(
        "zone_id" => repeat(["1", "2"], 2),
        "Date" => repeat(["2021-01-01", "2022-01-01"], inner=2),
        "Dollar per Ha" => [780.0, 830.0, 800.0, 850.0]  # Lower profit
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
    # Baseline (Scenario 1) - no changes
    @test metrics[1, :change_mean_profit_per_ha] == 0.0
    @test metrics[1, :change_var_profit_per_ha] == 0.0
    @test metrics[1, :change_ecological_index] == 0.0
    @test metrics[1, :change_recreational_index] == 0.0

    # Scenario 1 weighted metrics
    # Zone 1: mean=810.0, var=200.0, area=34076.9448139 (from farm_info.csv)
    # Zone 2: mean=860.0, var=200.0, area=6600.76501169 (from farm_info.csv)
    # Total area = 40677.70982559
    # Weighted mean = (810.0*34076.9448139 + 860.0*6600.76501169) / 40677.70982559 = 818.066...
    # Weighted var = (200.0*34076.9448139 + 200.0*6600.76501169) / 40677.70982559 = 200.0
    area_zone1 = 34076.9448139
    area_zone2 = 6600.76501169
    total_area = area_zone1 + area_zone2
    s1_mean = (810.0 * area_zone1 + 860.0 * area_zone2) / total_area
    s1_var = (200.0 * area_zone1 + 200.0 * area_zone2) / total_area

    @test metrics[1, :mean_profit_per_ha] ≈ s1_mean atol=1e-8
    @test metrics[1, :var_profit_per_ha] ≈ s1_var atol=1e-8
    @test metrics[1, :ecological_index] ≈ 100.0 atol=1e-8
    @test metrics[1, :recreational_index] ≈ 0.8 atol=1e-8

    # Scenario 2 weighted metrics
    # Zone 1: mean=860.0, var=200.0, area=34076.9448139
    # Zone 2: mean=910.0, var=200.0, area=6600.76501169
    # Weighted mean = (860.0*34076.9448139 + 910.0*6600.76501169) / 40677.70982559 = 868.066...
    # Weighted var = (200.0*34076.9448139 + 200.0*6600.76501169) / 40677.70982559 = 200.0
    s2_mean = (860.0 * area_zone1 + 910.0 * area_zone2) / total_area
    s2_var = (200.0 * area_zone1 + 200.0 * area_zone2) / total_area

    @test metrics[2, :mean_profit_per_ha] ≈ s2_mean atol=1e-8
    @test metrics[2, :var_profit_per_ha] ≈ s2_var atol=1e-8
    @test metrics[2, :change_mean_profit_per_ha] ≈ (s2_mean - s1_mean) / s1_mean atol=1e-8
    @test metrics[2, :change_var_profit_per_ha] ≈ (s2_var - s1_var) / s1_var atol=1e-8
    @test metrics[2, :change_recreational_index] ≈ (0.85 - 0.8) / 0.8 atol=1e-8  # 0.0625

    # Scenario 3 weighted metrics
    # Zone 1: mean=790.0, var=200.0, area=34076.9448139
    # Zone 2: mean=840.0, var=200.0, area=6600.76501169
    # Weighted mean = (790.0*34076.9448139 + 840.0*6600.76501169) / 40677.70982559 = 798.066...
    # Weighted var = (200.0*34076.9448139 + 200.0*6600.76501169) / 40677.70982559 = 200.0
    s3_mean = (790.0 * area_zone1 + 840.0 * area_zone2) / total_area
    s3_var = (200.0 * area_zone1 + 200.0 * area_zone2) / total_area

    @test metrics[3, :mean_profit_per_ha] ≈ s3_mean atol=1e-8
    @test metrics[3, :var_profit_per_ha] ≈ s3_var atol=1e-8
    @test metrics[3, :change_mean_profit_per_ha] ≈ (s3_mean - s1_mean) / s1_mean atol=1e-8
    @test metrics[3, :change_ecological_index] ≈ (12.0 - 10.0) / 10.0 atol=1e-8  # 0.2
    @test metrics[3, :change_recreational_index] ≈ (0.75 - 0.8) / 0.8 atol=1e-8  # -0.0625
end
