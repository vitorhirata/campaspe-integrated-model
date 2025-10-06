@testset "#create GwState" begin
    @testset "simple parameters return correct struct" begin
        zone_info = DataFrame(
                              ZoneID = [1, 2, 3, 4],
                              TRADING_ZO = ["Echuca Zone", "Elmore-Rochester Zone", "Barnadown Zone", "Barnadown Zone"],
                              gw_Ent = [1000.0, 1500.0, 800.0, 1200.0],
                              TrigBore = ["62589", "79324", "62589", "79324"]
                             )
        carryover_period = 1
        max_carryover_perc = 0.25
        restriction_type = "default"
        data_path = "/home/vitor/Code/campaspe-integrated-model/data/"

        gw_state = CampaspeIntegratedModel.GwState(
            zone_info, carryover_period, max_carryover_perc, restriction_type, data_path
        )

        @test typeof(gw_state) == CampaspeIntegratedModel.GwState
        @test gw_state.carryover_period == carryover_period
        @test gw_state.max_carryover_perc == max_carryover_perc
        @test gw_state.restriction_type == restriction_type
    end

    #@testset "invalid parameters raise error" begin end
end

