(results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR)

@testset "test filter results" begin
    gen = PG.get_generation_data(results_uc, curtailment = false)
    @test length(gen.data) == 4
    @test length(gen.time) == 48

    gen = PG.get_generation_data(
        results_uc,
        names = [
            :P__ThermalStandard,
            :P__RenewableDispatch,
            :P__max_active_power__RenewableDispatch_max_active_power,
        ],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 3,
    )
    @test length(gen.data) == 2
    @test length(gen.time) == 3

    load = PG.get_load_data(results_ed)
    @test length(load.data) == 1
    @test length(load.time) == 48
    @test !any(Matrix(PG.no_datetime(load.data[:P__PowerLoad])) .< 0.0)

    load = PG.get_load_data(
        results_ed,
        names = [:P__max_active_power__PowerLoad_max_active_power],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 3,
    )
    @test length(load.data) == 1
    @test length(load.time) == 3
    @test !any(Matrix(PG.no_datetime(load.data[:P__PowerLoad])) .< 0.0)

    srv = PG.get_service_data(results_ed)
    @test length(srv.data) == 0

    srv = PG.get_service_data(
        results_uc,
        names = [:REG1__VariableReserve_ReserveUp],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 5,
    )
    @test length(srv.data) == 1
    @test length(srv.time) == 5
end

@testset "test data aggregation" begin
    gen = PG.get_generation_data(results_uc)

    cat = PG.make_fuel_dictionary(results_uc.system)
    @test isempty(symdiff(keys(cat), ["Coal", "Wind", "Hydropower", "NG-CC", "NG-CT"]))

    fuel = PG.categorize_data(gen.data, cat)
    @test length(fuel) == 6

    fuel_agg = PG.combine_categories(fuel)
    @test size(fuel_agg) == (48, 5)
end

@testset "test html saving" begin
    plot_fuel(
        results_ed,
        set_display = false,
        save = TEST_RESULT_DIR,
        title = "fuel_html_output",
        format = "html",
    )
    @test isfile(joinpath(TEST_RESULT_DIR, "fuel_html_output.html"))
end
