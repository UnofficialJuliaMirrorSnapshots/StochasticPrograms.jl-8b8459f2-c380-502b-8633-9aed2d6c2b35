# Creation macros #
# ========================== #
"""
    @scenario(def)

Define a scenario type compatible with StochasticPrograms using the syntax
```julia
@scenario name = begin
    ...structdef...

    [@zero begin
        ...
        return zero(scenario)
    end]

    [@expectation begin
        ...
        return expected(scenarios)
     end]
end
```
The generated type is referenced through `name` and a default constructor is always generated. This constructor accepts the keyword `probability` to set the probability of the scenario occuring. Otherwise, any internal variables and specialized constructors are defined in the @scenario block as they would be in any Julia struct.

If possible, a `zero` method and an `expected` method will be generated for the defined type. Otherwise, or if the default implementation is not desired, these can be user provided through [`@zero`](@ref) and [`@expectation`](@ref).

The defined scenario type will be available on all Julia processes.

## Examples

The following defines a simple scenario ``ξ`` with a single value.

```jldoctest
@scenario ExampleScenario = begin
    ξ::Float64
end

ExampleScenario(1.0, probability = 0.5)

# output

ExampleScenario with probability 0.5
  ξ: 1.0

```

See also: [`@zero`](@ref), [`@expectation`](@ref), [`@sampler`](@ref)
"""
macro scenario(arg)
    @capture(arg, scenarioname_Symbol = scenariodef_) || error("Invalid syntax. Expected: scenarioname = begin scenariodef end")
    vars = Vector{Symbol}()
    vartypes = Vector{Union{Expr,Symbol}}()
    vardefs = Vector{Expr}()
    zerodefs = Vector{Expr}()
    expectdefs = Vector{Expr}()
    def = postwalk(prettify(scenariodef)) do x
        if @capture(x, var_Symbol::vartype_)
            push!(vars, var)
            push!(vartypes, vartype)
            push!(vardefs, x)
            return x
        end
        if @capture(x, @zero zerodef_)
            push!(zerodefs, zerodef)
            return @q begin end
        end
        if @capture(x, @expectation expectdef_)
            push!(expectdefs, expectdef)
            return @q begin end
        end
        return x
    end
    # Handle zero definition
    if length(zerodefs) > 1
        error("Only provide one zero implementation")
    end
    provided_zerodef, zerodef = if length(zerodefs) == 1
        zerodef = zerodefs[1]
        true, zerodef
    else
        false, Expr(:block)
    end
    # Handle expectation definition
    if length(expectdefs) > 1
        error("Only provide one expectation implementation")
    end
    provided_expectdef, expectdef = if length(expectdefs) == 1
        expectdef = expectdefs[1]
        expectdef = postwalk(prettify(expectdef)) do x
            @capture(x, constructor_Symbol(args__)) && constructor == scenarioname && return :(StochasticPrograms.ExpectedScenario($x))
            return x
        end
        true, expectdef
    else
        false, Expr(:block)
    end
    # Prepare automatic expectation definition
    combine = Expr(:call)
    push!(combine.args, scenarioname)
    push!(combine.args, :($(Expr(:parameters, :(probability = 1.0)))))
    for var in vars
        push!(combine.args, :(probability(s1)*s1.$var + probability(s2)*s2.$var))
    end
    # Prepare automatic scenariotext definition
    textdef = Expr(:block)
    for var in vars
        key = Meta.quot(var)
        push!(textdef.args, :(print(io, "\n  $($key): $(scenario.$var)")))
    end
    # Define scenario type
    code = @q begin
        if StochasticPrograms.supports_expected([$(vartypes...)], $provided_expectdef) || $provided_expectdef
            if StochasticPrograms.supports_zero([$(vartypes...)], $provided_zerodef) || $provided_zerodef
                struct $scenarioname <: AbstractScenario
                    probability::Probability
                    $def
                    function (::Type{$scenarioname})($(vardefs...); probability::AbstractFloat = 1.0)
                        return new(Probability(probability), $(vars...))
                    end
                end
                if $provided_zerodef
                    function Base.zero(::Type{$scenarioname})
                        $zerodef
                    end
                else
                    function Base.zero(::Type{$scenarioname})
                        return $scenarioname(zero.([$(vartypes...)])...; probability = 1.0)
                    end
                end
                if $provided_expectdef
                    function StochasticPrograms.expected(scenarios::Vector{$scenarioname})
                        isempty(scenarios) && return StochasticPrograms.ExpectedScenario(zero($scenarioname))
                        $expectdef
                    end
                else
                    function StochasticPrograms.expected(scenarios::Vector{$scenarioname})
                        isempty(scenarios) && return StochasticPrograms.ExpectedScenario(zero($scenarioname))
                        return StochasticPrograms.ExpectedScenario(reduce(scenarios) do s1, s2
                                                                   $combine
                                                                   end)
                    end
                end
                function StochasticPrograms.scenariotext(io::IO, scenario::$scenarioname)
                    $textdef
                    return io
                end
            else
                @warn "The scenario type $(string($(Meta.quot(scenarioname)))) was not defined. A user-provided implementation \n\n    function zero(::Type{{$(string($(Meta.quot(scenarioname))))})\n        ...\n    end\n\nis required."
            end
        else
            @warn "The scenario type $(string($(Meta.quot(scenarioname)))) was not defined. A user-provided implementation \n\n    function expected(scenarios::Vector{$(string($(Meta.quot(scenarioname))))})\n        ...\n    end\n\nis required."
        end
    end
    code = prettify(code)
    code = @q begin
        if (@__MODULE__) == $(esc(:Main))
            @everywhere begin
                $code
            end
        else
            $(esc(code))
        end
    end
    return prettify(code)
end
"""
    @zero(def)

Define the additive zero scenario inside a @scenario block using the syntax:
```julia
@zero begin
    ...
    return zero_scenario
end
```

## Examples

The following defines a zero scenario for the example scenario defined in [`@scenario`](@ref)

```julia
@zero begin
    return ExampleScenario(0.0)
end
```

See also [`@scenario`](@ref)
"""
macro zero(def) @warn "@zero should be used inside a @scenario block." end
"""
    @expectation(def)

Define how to form the expected scenario inside a @scenario block. The scenario collection is accessed through the reserved keyword `scenarios`.

```julia
@zero begin
    ...
    return zero_scenario
end
```

## Examples

The following defines expectation for the example scenario defined in [`@scenario`](@ref)

```julia
@expectation begin
    return ExampleScenario(sum([probability(s)*s.ξ for s in scenarios]))
end
```

See also [`@scenario`](@ref)
"""
macro expectation(def) @warn "@expectation should be used inside a @scenario block." end
"""
    @sampler(def)

Define a sampler type for some `scenariotype` compatible with StochasticPrograms using the syntax
```julia
@sampler samplername = begin
    ...internals...

    @sample scenariotype begin
        ...
        return scenario
    end
end
```
Any internal state required by the sampler, as well as any specialized constructor, are defined in the @sampler block as they would be in any Julia struct. Define the sample operation inside the [`@sample`](@ref) block and specify the `scenariotype` that the sampler returns. The defined sampler will be available on all Julia processes.

## Examples

The following defines a simple dummy sampler, with some internal weight value, for the scenario defined in [`@scenario`](@ref), and samples one scenario.

```jldoctest; setup = :(@scenario ExampleScenario = ξ::Float64), filter = r".*"
@sampler ExampleSampler = begin
    w::Float64

    ExampleSampler(w::AbstractFloat) = new(w)

    @sample ExampleScenario begin
        @parameters w
        return ExampleScenario(w*randn(), probability = rand())
    end
end
s = ExampleSampler(2.0)
s()

# output

ExampleScenario with probability 0.29
  ξ: 1.48


```

See also: [`@sample`](@ref), [`@scenario`](@ref)
"""
macro sampler(arg)
    @capture(prettify(arg), samplername_Symbol = samplerdef_) || error("Invalid syntax. Expected: sampler = begin samplerdef end")
    scenarioname = :undefined
    sampledefs = Vector{Expr}()
    def = postwalk(prettify(samplerdef)) do x
        if @capture(x, @parameters args__)
            code = Expr(:block)
            for param in args
                push!(code.args, :($param = sampler.$param))
            end
            return code
        elseif @capture(x, @sample sname_ sampledef_)
            scenarioname = sname
            push!(sampledefs, sampledef)
            return @q begin end
        else
            return x
        end
    end
    # Handle sample definition
    length(sampledefs) == 1 || error("Must provide exactly one @sample operation.")
    sampledef = sampledefs[1]
    # Define sampler type
    code = @q begin
        struct $samplername <: AbstractSampler{$scenarioname}
            $def
        end
        function (sampler::$samplername)()
            $sampledef
        end
    end
    code = prettify(code)
    code = @q begin
        if (@__MODULE__) == $(esc(:Main))
            @everywhere begin
                $code
            end
        else
            $(esc(code))
        end
    end
    return prettify(code)
end
"""
    @sample(def)

Define the sample operaton inside a @sampler block, using the syntax
```julia
@sample begin
    ...
    return sampled_scenario
end
```
The sampler object is referenced through the reserved keyword `sampler`, from which any internals can be accessed.
"""
macro sample(def) @warn "@sample should be used inside a @sampler block." end
"""
    @first_stage(def)

Add a first stage model generation recipe to `stochasticprogram` using the syntax
```julia
@first_stage stochasticprogram::StochasticProgram = begin
    ...
end [defer]
```
where JuMP syntax is used inside the block to define the first stage model. During definition, the first stage model is referenced through the reserved keyword `model`.

Optionally, give the keyword `defer` after the  to delay generation of the first stage model.

## Examples

The following defines the first stage model given by:

```math
  minimize 100x₁ + 150x₂
    s.t  x₁ + x₂ ≤ 120
         x₁ ≥ 40
         x₂ ≥ 20
```

```julia
@first_stage sp = begin
    @variable(model, x₁ >= 40)
    @variable(model, x₂ >= 20)
    @objective(model, Min, 100*x₁ + 150*x₂)
    @constraint(model, x₁ + x₂ <= 120)
end
```

See also: [`@second_stage`](@ref)
"""
macro first_stage(arg) esc(:(@first_stage $arg generate)) end
macro first_stage(arg, defer)
    return esc(:(@stage 1 $arg $defer))
end
"""
    @second_stage(def)

Add a second stage model generation recipe to `stochasticprogram` using the syntax
```julia
@second_stage stochasticprogram::StochasticProgram = begin
    @decision var1 var2 ...
    ...
end [defer]
```
where JuMP syntax is used inside the block to define the second stage model. During definition, the second stage model is referenced through the reserved keyword `model`.

Optionally, give the keyword `defer` after the  to delay generation of the first stage model.

## Examples

The following defines the second stage model given by:
```math
  minimize q₁(ξ)y₁ + q₂(ξ)y₂
    s.t  6y₁ + 10y₂ ≤ 60x₁
         8y₁ + 5y₂ ≤ 60x₂
         0 ≤ y₁ ≤ d₁(ξ)
         0 ≤ y₂ ≤ d₂(ξ)
```
where ``q₁(ξ), q₂(ξ), d₁(ξ), d₂(ξ)`` depend on the scenario ``ξ`` and ``x₁, x₂`` are first stage variables. Two scenarios are added so that two second stage models are generated.

```julia
@second_stage sp = begin
    @decision x₁ x₂
    @uncertain q₁ q₂ d₁ d₂
    @variable(model, 0 <= y₁ <= d₁)
    @variable(model, 0 <= y₂ <= d₂)
    @objective(model, Min, q₁*y₁ + q₂*y₂)
    @constraint(model, 6*y₁ + 10*y₂ <= 60*x₁)
    @constraint(model, 8*y₁ + 5*y₂ <= 80*x₂)
end
```

See also: [`@first_stage`](@ref)
"""
macro second_stage(arg) esc(:(@second_stage $arg generate)) end
macro second_stage(arg, defer)
    return esc(:(@stage 2 $arg $defer))
end
"""
    @parameters(def)

Define the problem parameters in a @stage block
```julia
@parameters param1, param2, ...
```
possibly with default values. Any defined parameter without a default value must be supplied as a keyword argument to [`instantiate`](@ref) or [`SAA`](@ref) when creating models.

## Examples

```julia
@parameters d

@parameters begin
    Crops = [:wheat, :corn, :beets]
    Cost = Dict(:wheat=>150, :corn=>230, :beets=>260)
    Budget = 500
end
```

See also [`@decision`](@ref), [`@uncertain`](@ref), [`@stage`](@ref)
"""
macro parameters(def) @warn "@parameters should be used inside a @stage block." end
"""
    @decision(def)

In a @stage block, annotate each decision taken in the previous stage using the syntax
```julia
@decision var1, var2, ...
```

## Examples

```julia
@decision x₁, x₂
```

See also [`@parameters`](@ref), [`@uncertain`](@ref), [`@stage`](@ref)
"""
macro decision(def) @warn "@decision should be used inside a @stage block." end
"""
    @uncertain(def)

In a @stage block, annotate each uncertain variable using the syntax
```julia
@uncertain var1, var2, ...
```
This assumes that the [`Scenario`] type is used. Alternatively, user-defined scenarios can be specified by annotating the type. Also, inside a @stochastic_model block, user-defined scenarios can be created during the @uncertain annotation, following [`@scenario`](@ref).

## Examples

```julia
@uncertain q₁ q₂ d₁ d₂

@scenario Simple = begin
    q₁::Float64
    q₂::Float64
    d₁::Float64
    d₂::Float64
end
@uncertain ξ::SimpleScenario

@stochastic_model begin
    ...
    @uncertain ξ::SimpleScenario = begin
        q₁::Float64
        q₂::Float64
        d₁::Float64
        d₂::Float64
    end
    ...
end
```

See also [`@scenario`](@ref), [`@parameters`](@ref), [`@decision`](@ref), [`@stage`](@ref)
"""
macro uncertain(def) @warn "@uncertain should be used inside a @stage block." end
"""
    @stage(def)

Add a stage model generation recipe to `stochasticprogram` using the syntax
```julia
@stage stage stochasticprogram::StochasticProgram = begin
    @parameters param1 param2 ...
    @decision var1 var2 ...
    @uncertain ξ
    ... JuMPdef ...
    ...
end [defer]
```
where JuMP syntax is used inside the block to define the stage model. During definition, the second stage model is referenced through the reserved keyword `model`.

Optionally, give the keyword `defer` after the  to delay generation of the stage model.

## Examples

The following defines the first stage model given by:
```math
  minimize 100x₁ + 150x₂
    s.t  x₁ + x₂ ≤ 120
         x₁ ≥ 40
         x₂ ≥ 20
```
and the second-stage model given by:
```math
  minimize q₁(ξ)y₁ + q₂(ξ)y₂
    s.t  6y₁ + 10y₂ ≤ 60x₁
         8y₁ + 5y₂ ≤ 60x₂
         0 ≤ y₁ ≤ d₁(ξ)
         0 ≤ y₂ ≤ d₂(ξ)
```
where ``q₁(ξ), q₂(ξ), d₁(ξ), d₂(ξ)`` depend on the scenario ``ξ`` and ``x₁, x₂`` are first stage variables. Two scenarios are added so that two second stage models are generated.

```jldoctest
ξ₁ = Scenario(q₁ = -24.0, q₂ = -28.0, d₁ = 500.0, d₂ = 100.0, probability = 0.4)
ξ₂ = Scenario(q₁ = -28.0, q₂ = -32.0, d₁ = 300.0, d₂ = 300.0, probability = 0.6)

sp = StochasticProgram([ξ₁, ξ₂])

@stage 1 sp = begin
    @variable(model, x₁ >= 40)
    @variable(model, x₂ >= 20)
    @objective(model, Min, 100*x₁ + 150*x₂)
    @constraint(model, x₁ + x₂ <= 120)
end

@stage 2 sp = begin
    @decision x₁ x₂
    @uncertain q₁ q₂ d₁ d₂
    @variable(model, 0 <= y₁ <= d₁)
    @variable(model, 0 <= y₂ <= d₂)
    @objective(model, Min, q₁*y₁ + q₂*y₂)
    @constraint(model, 6*y₁ + 10*y₂ <= 60*x₁)
    @constraint(model, 8*y₁ + 5*y₂ <= 80*x₂)
end

# output

Stochastic program with:
 * 2 decision variables
 * 2 recourse variables
 * 2 scenarios of type Scenario
Solver is default solver

```

See also: [`@parameters`](@ref), [`@decision`](@ref), [`@uncertain`](@ref)
"""
macro stage(stage, arg) esc(:(@stage $stage $arg generate)) end
macro stage(stage, args, defer)
    generate = if defer == :defer
        :false
    elseif defer == :generate
        :true
    else
        error("Unknown option $defer")
    end
    @capture(args, sp_Symbol = def_) || error("Invalid syntax. Expected stage, multistage = begin JuMPdef end")
    # Save variable definitions separately
    vardefs = Expr(:block)
    for line in block(def).args
        if @capture(line, @constraint(m_Symbol, constdef__)) || @capture(line, @objective(m_Symbol, objdef__)) || @capture(line, @parameters args__) || @capture(line, @decision args__) || @capture(line, @uncertain args__)
            continue
        else
            push!(vardefs.args, line)
        end
    end
    # Handle parameters
    def = postwalk(def) do x
        if @capture(x, @parameters arg_)
            code = Expr(:block)
            for paramdef in prettify(arg).args
                if @capture(paramdef, key_Symbol = val_) || @capture(paramdef, key_Symbol)
                    push!(code.args, :($key = stage.$key))
                else
                    error("Incorrect @parameters syntax. Specify parameter names, possibly with a default value.")
                end
            end
            pushfirst!(vardefs.args, code)
            return code
        elseif @capture(x, @parameters args__)
            code = Expr(:block)
            for param in args
                push!(code.args, :($param = stage.$param))
            end
            pushfirst!(vardefs.args, code)
            return code
        elseif @capture(x, @decision args__)
            stage == 1 && error("@decision links cannot be used in the first stage.")
            code = Expr(:block)
            for var in args
                varkey = Meta.quot(var)
                decisiondef = @q begin
                    haskey(parent.objDict, $varkey) || error("Decision $($varkey) not present in parent model.")
                    $var = parent.objDict[$varkey]
                end
                push!(code.args, decisiondef)
            end
            return code
        elseif @capture(x, @uncertain var_Symbol::t_Symbol)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            return :($var::$t = scenario)
        elseif @capture(x, @uncertain vars__ from scenvar_Symbol::t_Symbol)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            code = @q begin
                $scenvar::$t = scenario
            end
            for var in vars
                varkey = Meta.quot(var)
                push!(code.args, :($var = getproperty($scenvar, $varkey)))
            end
            return code
        elseif @capture(x, @uncertain vars__ from t_Symbol)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            code = @q begin
                scenvar::$t = scenario
            end
            for var in vars
                varkey = Meta.quot(var)
                push!(code.args, :($var = getproperty(scenvar, $varkey)))
            end
            return code
        elseif @capture(x, @uncertain var_Symbol::t_Symbol = scenariodef_)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            return @q begin
                $var::$t = scenario
            end
        elseif @capture(x, @uncertain vars__ from scenvar_Symbol::t_Symbol = scenariodef_)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            code = @q begin
                $scenvar::$t = scenario
            end
            for var in vars
                varkey = Meta.quot(var)
                push!(code.args, :($var = getproperty($scenvar, $varkey)))
            end
            return code
        elseif @capture(x, @uncertain vars__ from t_Symbol = scenariodef_)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            code = @q begin
                scenvar::$t = scenario
            end
            for var in vars
                varkey = Meta.quot(var)
                push!(code.args, :($var = getproperty(scenvar, $varkey)))
            end
            return code
        elseif @capture(x, @uncertain args__)
            stage == 1 && error("@uncertain declarations cannot be used in the first stage.")
            code = Expr(:block)
            for var in args
                varkey = Meta.quot(var)
                push!(code.args, :($var = scenario[$varkey]))
            end
            return code
        else
            return x
        end
    end
    # The first stage is treated different from the subsequent stages
    generatordefs = if stage == 1
        @q begin
            $(esc(sp)).generator[:stage_1] = ($(esc(:model))::JuMP.Model, $(esc(:stage))) -> begin
                $(esc(def))
	        return $(esc(:model))
            end
        end
    else
        @q begin
            $(esc(sp)).generator[Symbol(:stage_,$stage)] = ($(esc(:model))::JuMP.Model, $(esc(:stage)), $(esc(:scenario))::AbstractScenario, $(esc(:parent))::JuMP.Model) -> begin
                $(esc(def))
	        return $(esc(:model))
            end
        end
    end
    # Create definition code
    code = @q begin
        isa($(esc(sp)), StochasticProgram) || error("Given object is not a stochastic program.")
        $(esc(sp)).generator[Symbol(:stage_,$stage,:_vars)] = ($(esc(:model))::JuMP.Model, $(esc(:stage))) -> begin
            $(esc(vardefs))
	    return $(esc(:model))
        end
        $generatordefs
        if $generate
            generate_stage!($(esc(sp)), $stage)
        end
        $(esc(sp))
    end
    # Return code
    return prettify(code)
end
# ========================== #
