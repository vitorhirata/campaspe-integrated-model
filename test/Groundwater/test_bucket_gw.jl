using Test
using CampaspeIntegratedModel

@testset "Bucket Groundwater Model" begin
    @testset "Basic initialization" begin
        gw = CampaspeIntegratedModel.GWModel()

        @test gw.bore_ground_elevation == 100.0
        @test gw.G > 0.0
        @test length(gw.storage) == 1
        @test length(gw.heads) == 1
        @test length(gw.depths) == 1
        @test gw.storage[1] == gw.G
        @test gw.heads[1] ≈ gw.G * gw.e
        @test gw.depths[1] ≈ gw.bore_ground_elevation - gw.G * gw.e
    end

    @testset "Custom initialization" begin
        gw = CampaspeIntegratedModel.GWModel(a=2.0, b=0.5, c=15000.0, d=0.05, e=0.002, G=12000.0)

        @test gw.a == 2.0
        @test gw.b == 0.5
        @test gw.c == 15000.0
        @test gw.d == 0.05
        @test gw.e == 0.002
        @test gw.G == 12000.0
    end

    @testset "Water balance - no extraction" begin
        gw = CampaspeIntegratedModel.GWModel(a=1.0, b=0.1, c=10000.0, d=0.01, e=0.001, G=10000.0, bore_ground_elevation=100.0)

        # With G_t = c, exchange term is zero
        # G_new = 10000 + 1.0*10 - 0.1*5 - 0 + 0 = 10009.5
        rainfall = 10.0  # mm/day
        evap = 5.0       # mm/day
        extraction = 0.0  # ML/day

        G_new = CampaspeIntegratedModel.update_gw!(gw, rainfall, evap, extraction)

        @test G_new ≈ 10009.5
        @test gw.G ≈ 10009.5
        @test length(gw.storage) == 2
        @test length(gw.heads) == 2
        @test length(gw.depths) == 2
    end

    @testset "Water balance - with extraction" begin
        gw = CampaspeIntegratedModel.GWModel(a=1.0, b=0.1, c=10000.0, d=0.01, e=0.001, G=10000.0, bore_ground_elevation=100.0)

        # G_new = 10000 + 1.0*10 - 0.1*5 - 30 + 0 = 9979.5
        rainfall = 10.0  # mm/day
        evap = 5.0       # mm/day
        extraction = 30.0  # ML/day (total)

        G_new = CampaspeIntegratedModel.update_gw!(gw, rainfall, evap, extraction)

        @test G_new ≈ 9979.5
        @test gw.G ≈ 9979.5
    end

    @testset "Dam-GW exchange - low GW (dam recharges GW)" begin
        gw = CampaspeIntegratedModel.GWModel(a=0.0, b=0.0, c=10000.0, d=0.1, e=0.001, G=8000.0, bore_ground_elevation=100.0)

        # When G_t < c: positive exchange (dam -> GW)
        # G_new = 8000 + 0 - 0 - 0 + (10000 - 8000)*0.1 = 8000 + 200 = 8200
        extraction = 0.0

        G_new = CampaspeIntegratedModel.update_gw!(gw, 0.0, 0.0, extraction)

        @test G_new ≈ 8200.0
        @test gw.G ≈ 8200.0
    end

    @testset "Dam-GW exchange - high GW (GW feeds dam)" begin
        gw = CampaspeIntegratedModel.GWModel(a=0.0, b=0.0, c=10000.0, d=0.1, e=0.001, G=12000.0, bore_ground_elevation=100.0)

        # When G_t > c: negative exchange (GW -> dam)
        # G_new = 12000 + 0 - 0 - 0 + (10000 - 12000)*0.1 = 12000 - 200 = 11800
        extraction = 0.0

        G_new = CampaspeIntegratedModel.update_gw!(gw, 0.0, 0.0, extraction)

        @test G_new ≈ 11800.0
        @test gw.G ≈ 11800.0
    end

    @testset "Prevent negative volume" begin
        gw = CampaspeIntegratedModel.GWModel(a=0.0, b=0.0, c=10000.0, d=0.0, e=0.001, G=100.0, bore_ground_elevation=100.0)

        # Extraction exceeds available water
        extraction = 150.0

        G_new = CampaspeIntegratedModel.update_gw!(gw, 0.0, 0.0, extraction)

        @test G_new == 0.0
        @test gw.G == 0.0
    end

    @testset "GW levels for trigger and zones" begin
        gw = CampaspeIntegratedModel.GWModel(e=0.001, G=89000.0, bore_ground_elevation=100.0)

        trigger_head, avg_gw_depth = CampaspeIntegratedModel.gw_levels(gw)

        # Expected head: 89000 * 0.001 = 89.0 mAHD
        # Expected depth: 100.0 - 89.0 = 11.0 m below surface
        @test trigger_head["62589"] ≈ 89.0
        @test trigger_head["79324"] ≈ 89.0

        for zone_id in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"]
            @test avg_gw_depth[zone_id] ≈ 11.0
        end
    end

    @testset "Multi-timestep simulation" begin
        gw = CampaspeIntegratedModel.GWModel(a=1.0, b=0.1, c=10000.0, d=0.01, e=0.001, G=10000.0, bore_ground_elevation=100.0)

        # Run 10 timesteps
        for i in 1:10
            rainfall = 5.0 + rand() * 10.0  # 5-15 mm/day
            evap = 2.0 + rand() * 4.0       # 2-6 mm/day
            extraction = rand() * 10.0      # 0-10 ML/day

            CampaspeIntegratedModel.update_gw!(gw, rainfall, evap, extraction)
        end

        @test length(gw.storage) == 11  # Initial + 10 timesteps
        @test length(gw.heads) == 11
        @test length(gw.depths) == 11
        @test gw.G >= 0.0  # Volume should never be negative
        @test all(gw.storage .>= 0.0)  # All storage should be non-negative
        @test all(gw.depths .>= 0.0)  # All depths should be non-negative (above water table)
    end

    @testset "Parameter bounds" begin
        bounds = CampaspeIntegratedModel.get_parameter_bounds()

        @test haskey(bounds, :a)
        @test haskey(bounds, :b)
        @test haskey(bounds, :c)
        @test haskey(bounds, :d)
        @test haskey(bounds, :e)

        @test bounds[:a] == (0.1, 200.0)
        @test bounds[:b] == (0.01, 50.0)
        @test bounds[:c] == (100000.0, 2000000.0)
        @test bounds[:d] == (1e-6, 0.1)
        @test bounds[:e] == (1e-6, 1e-3)
    end
end
