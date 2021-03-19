
function run_test_sim(result_dir::String)
    sim_name = "results_sim"
    sim_path = joinpath(result_dir, sim_name)
    c_sys5_hy_uc = PSB.build_system(PSB.SIIPExampleSystems, "5_bus_hydro_uc_sys")
    c_sys5_hy_ed = PSB.build_system(PSB.SIIPExampleSystems, "5_bus_hydro_ed_sys")
    function add_re!(sys)
        re = RenewableDispatch(
            "WindBusA",
            true,
            get_component(Bus, sys, "bus5"),
            0.0,
            0.0,
            1.200,
            PrimeMovers.WT,
            (min = 0.0, max = 0.0),
            1.0,
            TwoPartCost(0.220, 0.0),
            100.0,
        )
        add_component!(sys, re)
        copy_time_series!(re, get_component(PowerLoad, sys, "bus2"))
    end
    add_re!(c_sys5_hy_uc)
    add_re!(c_sys5_hy_ed)

    if ispath(sim_path)
        executions = tryparse.(Int, readdir(sim_path))
        sim = joinpath(sim_path, string(maximum(executions)))
        @info "Reading results from last execution" sim
    else
        mkpath(result_dir)
        GLPK_optimizer =
            optimizer_with_attributes(GLPK.Optimizer, "msg_lev" => GLPK.GLP_MSG_OFF)

        template_hydro_st_uc = template_unit_commitment()
        set_device_model!(template_hydro_st_uc, HydroDispatch, FixedOutput)
        set_device_model!(
            template_hydro_st_uc,
            HydroEnergyReservoir,
            HydroDispatchReservoirStorage,
        )

        template_hydro_st_ed = template_economic_dispatch()
        set_device_model!(template_hydro_st_ed, HydroDispatch, FixedOutput)
        set_device_model!(
            template_hydro_st_ed,
            HydroEnergyReservoir,
            HydroDispatchReservoirStorage,
        )
        template_hydro_st_ed.services = Dict() #remove ed services

        problems = SimulationProblems(
            UC = OperationsProblem(
                template_hydro_st_uc,
                c_sys5_hy_uc,
                optimizer = GLPK_optimizer,
            ),
            ED = OperationsProblem(
                template_hydro_st_ed,
                c_sys5_hy_ed,
                optimizer = GLPK_optimizer,
                constraint_duals = [:CopperPlateBalance],
                balance_slack_variables = true,
            ),
        )

        sequence = SimulationSequence(
            problems = problems,
            feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24)),
            intervals = Dict(
                "UC" => (Hour(24), Consecutive()),
                "ED" => (Hour(1), Consecutive()),
            ),
            feedforward = Dict(
                ("ED", :devices, :ThermalStandard) => SemiContinuousFF(
                    binary_source_problem = PSI.ON,
                    affected_variables = [PSI.ACTIVE_POWER],
                ),
                ("ED", :devices, :HydroEnergyReservoir) => IntegralLimitFF(
                    variable_source_problem = PSI.ACTIVE_POWER,
                    affected_variables = [PSI.ACTIVE_POWER],
                ),
            ),
            cache = Dict(
                ("UC",) => TimeStatusChange(PSY.ThermalStandard, PSI.ON),
                ("UC", "ED") => StoredEnergy(PSY.HydroEnergyReservoir, PSI.ENERGY),
            ),
            ini_cond_chronology = InterProblemChronology(),
        )
        sim = Simulation(
            name = "results_sim",
            steps = 2,
            problems = problems,
            sequence = sequence,
            simulation_folder = result_dir,
        )
        build!(sim)
        execute!(sim)
    end

    results = SimulationResults(sim)
    results_uc = get_problem_results(results, "UC")
    set_system!(results_uc, c_sys5_hy_uc)
    results_ed = get_problem_results(results, "ED")
    set_system!(results_ed, c_sys5_hy_ed)

    return results_uc, results_ed
end
