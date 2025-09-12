@with_kw mutable struct EnvironmentState
    current_time::Int64 = 0
    season_order::Int64 = 0
    water_order::Int64 = 0
    fixed_annual_losses::Int64 = 1656
    hr_entitlement::Float64 = 25716.0 - fixed_annual_losses
    lr_entitlement::Float64 = 8409.0
    model_run_range::StepRange{Date, Period}
end
