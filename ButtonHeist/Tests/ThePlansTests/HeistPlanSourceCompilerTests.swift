import Testing
import ThePlans

@Test func `inline plan source simple Activate compiles to HeistPlan`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    Activate(.label("Pay"))
    """)
    let expected = try HeistPlan(body: [
        .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source chained expectation compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    Activate(.label("Pay")).expect(.screenChanged)
    """)
    let expected = try HeistPlan(body: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Pay"))),
            expectation: WaitStep(predicate: .screenChanged, timeout: 0)
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source ForEach string compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    ForEach(["a", "b"]) { item in
        Activate(.label(item)).expect(.present(.label(item)))
    }
    """)
    let expected = try HeistPlan(body: [
        .forEachString(try ForEachStringStep(
            values: ["a", "b"],
            parameter: "item",
            body: [
                .action(try ActionStep(
                    command: .activate(.predicate(.label(.ref("item")))),
                    expectation: WaitStep(predicate: .state(.present(.label(.ref("item")))), timeout: 0)
                )),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source WaitFor and If compile`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    WaitFor(.present(.label("Home")), timeout: .seconds(1))
    If(.present(.label("Pay"))) {
        Warn("ready")
    }
    """)
    let expected = try HeistPlan(body: [
        .wait(WaitStep(predicate: .state(.present(.label("Home"))), timeout: 1)),
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Pay"))), body: [.warn(WarnStep(message: "ready"))]),
        ])),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source ForEach matching compiles`() throws {
    let plan = try HeistPlanSourceCompiler().compile("""
    ForEach(.matching(.label("Row")), limit: 2) { target in
        Activate(target).expect(.absent(target))
    }
    """)
    let expected = try HeistPlan(body: [
        .forEachElement(try ForEachElementStep(
            matching: .label("Row"),
            limit: 2,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(.ref("target")),
                    expectation: WaitStep(predicate: .state(.absentTarget(.ref("target"))), timeout: 0)
                )),
            ]
        )),
    ])

    #expect(plan == expected)
}

@Test func `inline plan source RunHeist syntax validates through normal runtime pipeline`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        RunHeist("CartScreen.checkout")
        """)
    }
}

@Test func `inline plan source unsupported Swift syntax is rejected`() throws {
    for source in [
        "let x = 1",
        "FileManager.default",
        "Process()",
        #"try ForEach(["a"]) { item in Warn("x") }"#,
    ] {
        #expect(throws: HeistPlanSourceCompilerError.self) {
            _ = try HeistPlanSourceCompiler().compile(source)
        }
    }
}

@Test func `inline plan source import Foundation is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        import Foundation
        Activate(.label("Pay"))
        """)
    }
}

@Test func `inline plan source while true is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        while true {
            Activate(.label("Pay"))
        }
        """)
    }
}

@Test func `inline plan source arbitrary function declaration is rejected`() throws {
    #expect(throws: HeistPlanSourceCompilerError.self) {
        _ = try HeistPlanSourceCompiler().compile("""
        func pay() {
            Activate(.label("Pay"))
        }
        """)
    }
}
