module CampaspeIntegratedModel

using CSV
using YAML
using Dates
using DataFrames
using Parameters
using StatsBase

include("sample.jl")
include("io.jl")
include("Policy/policy.jl")
include("Farm/farm.jl")
include("SurfaceWater/surface_water.jl")
include("Groundwater/groundwater.jl")
include("PathwayDiversity/pathway_diversity.jl")
include("Metrics/metrics.jl")
include("run_model.jl")

end
