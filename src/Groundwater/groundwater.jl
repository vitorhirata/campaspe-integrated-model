# TODO: Implement model. This is a placeholder that returns realistic default values
function update_groundwater()
    # Gauge IDs for groundwater-surface water exchange
    gauges = ["406214", "406219", "406201", "406224", "406218", "406202", "406265"]
    # Set small exchange rate (ML/day) - groundwater contribution to surface water
    exchange = Dict(zip(gauges, fill(10.0, length(gauges))))

    # Bore IDs for trigger level monitoring
    bore = ["79324", "62589"]
    # Trigger heads at approximately 50% of observed range (mAHD)
    # Bore 79324: mid-range ~85 mAHD (range 73.1-97.1)
    # Bore 62589: mid-range ~121 mAHD (range 110.8-131.8)
    trigger_head = Dict("79324" => 85.0, "62589" => 121.0)

    # Zone IDs for farm groundwater depth
    zones = string.(collect(1:12))
    # Average groundwater depth below surface (meters)
    # Set at 25m based on initial head in groundwater.yml
    avg_gw_depth = Dict(zip(zones, fill(25.0, length(zones))))

    return exchange, trigger_head, avg_gw_depth
end
