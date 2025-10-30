@testset "recreational_index" begin
    @testset "default parameters" begin
        # Test with dam levels below and above threshold
        dam_level = [50.0, 60.0, 61.2, 100.0]
        # threshold = 0.3, capacity = 204.0, so threshold level = 61.2
        rec_index = CampaspeIntegratedModel.recreational_index(dam_level)

        @test rec_index[1] == 0.0  # 50/204 = 0.245 < 0.3
        @test rec_index[2] == 0.0  # 60/204 = 0.294 < 0.3
        @test rec_index[3] == 1.0  # 61.2/204 = 0.3 >= 0.3
        @test rec_index[4] == 1.0  # 100/204 = 0.490 >= 0.3
        @test length(rec_index) == length(dam_level)
    end

    @testset "custom threshold" begin
        dam_level = [100.0, 150.0, 200.0]
        # threshold = 0.5, capacity = 204.0, so threshold level = 102.0
        rec_index = CampaspeIntegratedModel.recreational_index(dam_level, threshold=0.5)

        @test rec_index[1] == 0.0  # 100/204 = 0.490 < 0.5
        @test rec_index[2] == 1.0  # 150/204 = 0.735 >= 0.5
        @test rec_index[3] == 1.0  # 200/204 = 0.980 >= 0.5
        @test length(rec_index) == length(dam_level)
    end

    @testset "custom capacity" begin
        dam_level = [50.0, 100.0, 150.0]
        # threshold = 0.3, capacity = 200.0, so threshold level = 60.0
        rec_index = CampaspeIntegratedModel.recreational_index(dam_level, dam_capacity=200.0)

        @test rec_index[1] == 0.0  # 50/200 = 0.25 < 0.3
        @test rec_index[2] == 1.0  # 100/200 = 0.5 >= 0.3
        @test rec_index[3] == 1.0  # 150/200 = 0.75 >= 0.3
        @test length(rec_index) == length(dam_level)
    end
end
