module CampaspeIntegratedModel

using CSV
using YAML
using Dates
using DataFrames
using GeoDataFrames
using Parameters
using StatsBase

include("Policy/policy.jl")
include("Farm/farm.jl")
include("SurfaceWater/surface_water.jl")

end
