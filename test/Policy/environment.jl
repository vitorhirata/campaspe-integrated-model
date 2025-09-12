@testset "#create EnvironmentState" begin
    @testset "simple parameters return correct struct" begin
        model_run_range::StepRange{Date, Period} = Date("1968-05-01"):Week(1):Date("1988-04-30")
        env_state = CampaspeIntegratedModel.EnvironmentState(model_run_range = model_run_range)

        @test typeof(env_state) == CampaspeIntegratedModel.EnvironmentState
        @test env_state.model_run_range == model_run_range
    end

    #@testset "invalid parameters raise error" begin end
end
