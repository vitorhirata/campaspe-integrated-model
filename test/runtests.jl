using Test
using CampaspeIntegratedModel

using DataFrames, Dates

include("./constructors.jl")
include("./Policy/gw_state.jl")
include("./Policy/gw_update.jl")
include("./Policy/environment.jl")
include("./Policy/sw_state.jl")
include("./Policy/sw_update.jl")
include("./Policy/sw_allocation.jl")
include("./Policy/policy.jl")
include("./Policy/policy_state.jl")
