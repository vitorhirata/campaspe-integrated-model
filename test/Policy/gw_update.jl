@testset "#run update_groundwater" begin
    gw_state = create_gw_state()

    date = Date(2020, 7,1)
    gw_orders = Dict("1" => 10.3, "2" => 1.1, "3" => 4.0, "4" => 100.0)
    gw_levels = Dict("62589" => 10000.0, "79324" => 60000.0)
    result = CampaspeIntegratedModel.update_groundwater(gw_state, date, gw_orders, gw_levels)

    @test typeof(result) == Vector{Float64}
    @test length(result) == 8
end
