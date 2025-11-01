@testset "#create SwState" begin
    @testset "simple parameters return correct struct" begin
        model_run_range = [
            Date("1990-10-10"), Date("1990-10-11"), Date("1990-10-12"), Date("1990-10-13")
        ]
        goulburn_alloc_scenario = "high"
        dam_ext = DataFrame(
            Time = [Date("1990-10-10"), Date("1990-10-11"), Date("1990-10-12"), Date("1990-10-13")],
            Extraction = [16.0, 61.0, 20.0, 33.0],
        )
        env_systems = DataFrame(
            "Water System" => ["Campaspe River Environment", "test"],
            "HR_Entitlement" => [1000.0, 2000.0],
            "LR_Entitlement" => [4000.0, 9000.0]
        )
        other_systems = DataFrame(
            "Water System" => ["Vic Murray (Zone 7)", "Eppalock Reservoir"],
            "HR_Entitlement" => [100.0, 0.0],
            "LR_Entitlement" => [500.0, 1000.0]
        )
        zone_info::Dict{String, Any} = Dict(
            "2"=>Dict(
                "entitlement"=>Dict(
                    "camp_HR"=>100.0, "camp_LR"=>100.0, "goul_HR"=>100.0, "goul_LR"=>100.0,
                    "farm_HR"=>100.0, "farm_LR"=>100.0
                ),
                "water_system"=>"Campaspe Irrigation Area",
                "zone_id" => "2",
                "regulation_zone"=>"Regulated 4C",
                "areas"=>Dict("crop_ha"=>10000.0, "zone_ha"=>100000.0),
                "name"=>"Bamawm cropping regulated 4C trading"
            ),
            "3"=>Dict(
                "entitlement"=>Dict(
                    "camp_HR"=>100.0, "camp_LR"=>100.0, "goul_HR"=>100.0, "goul_LR"=>100.0,
                    "farm_HR"=>100.0, "farm_LR"=>100.0
                ),
                "zone_id" => "3",
                "water_system"=>"Campaspe River (Eppalock to Weir)",
                "regulation_zone"=>"Unregulated 170",
                "areas"=>Dict("crop_ha"=>10000.0, "zone_ha"=>100000.0),
                "name"=>"Elmore-Rochester CID unregulated 140 trading"
            )
        )

        sw_state = CampaspeIntegratedModel.SwState(model_run_range, zone_info, goulburn_alloc_scenario, dam_ext,
            env_systems, other_systems)

        @test typeof(sw_state) == CampaspeIntegratedModel.SwState
        @test sw_state.dam_ext == dam_ext
        @test sw_state.goulburn_alloc_scenario == goulburn_alloc_scenario
        @test sw_state.model_run_range == model_run_range
    end

    #@testset "invalid parameters raise error" begin end
end

