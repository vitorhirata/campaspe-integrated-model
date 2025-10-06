function create_gw_state()
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
    return gw_state
end

function create_sw_state()
    model_run_range::StepRange{Date, Period} = Date("1970-07-01"):Day(1):Date("1971-06-30")
    goulburn_alloc_scenario = "high"
    dam_ext = DataFrame(
        Time = [Date("1970-07-01")],
        Extraction = [10.0]
    )
    env_systems = DataFrame(
        "Water System" => ["Campaspe River Environment"],
        "HR_Entitlement" => [1000.0],
        "LR_Entitlement" => [50.0]
    )
    other_systems = DataFrame(
        "Water System" => ["Eppalock Reservoir"],
        "HR_Entitlement" => [500.0],
        "LR_Entitlement" => [10.0]
    )
    zone_info = Dict{String, Any}(
        "Zone1" => Dict(
            "entitlement" => Dict(
                "camp_HR" => 2000.0, "camp_LR" => 50.0,
                "goul_HR" => 10.0, "goul_LR" => 5.0,
                "farm_HR" => 1000.0, "farm_LR" => 50.0
            ),
            "water_system" => "Campaspe Irrigation Area",
            "regulation_zone" => "Regulated 4C",
            "areas" => Dict("crop_ha" => 1000.0, "zone_ha" => 10000.0),
            "name" => "Test Zone 1"
        ),
        "Zone2" => Dict(
            "entitlement" => Dict(
                "camp_HR" => 2000.0, "camp_LR" => 50.0,
                "goul_HR" => 10.0, "goul_LR" => 5.0,
                "farm_HR" => 1000.0, "farm_LR" => 50.0
            ),
            "water_system" => "Campaspe Irrigation Area",
            "regulation_zone" => "Regulated 4A",
            "areas" => Dict("crop_ha" => 1000.0, "zone_ha" => 10000.0),
            "name" => "Test Zone 2"
        )
    )

    sw_state = CampaspeIntegratedModel.SwState(
        model_run_range, zone_info, goulburn_alloc_scenario,
        dam_ext, env_systems, other_systems
    )

    # Set projected inflows to high values to ensure HR allocation reaches 100%
    # This is necessary for later_allocation to properly update avail_allocation
    # (otherwise zones don't get avail_allocation updated when HR < 100%)
    sw_state.proj_inflow .= 500000.0  # 500,000 ML per timestep

    return sw_state
end

