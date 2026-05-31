import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class FleetMappingTests: XCTestCase {
    func testSingleTaskGroupedByEpic() {
        let wire = FleetWireTask(
            id: "t1",
            title: "Implement feature X",
            status: "in_progress",
            lockedBy: "impl-drone",
            frontmatter: .init(epic: "agent-factory", startedAt: nil),
            phase: nil,
            parentId: nil
        )
        let missions = [wire].toMissions()
        XCTAssertEqual(missions.count, 1)
        XCTAssertEqual(missions[0].name, "agent-factory")
        XCTAssertEqual(missions[0].tasks.count, 1)
        XCTAssertEqual(missions[0].tasks[0].status, .inProgress)
        XCTAssertEqual(missions[0].tasks[0].lockedBy, "impl-drone")
    }

    func testTasksGroupedByEpicKey() {
        let wires = [
            FleetWireTask(id: "a", title: "A", status: "done", lockedBy: nil, frontmatter: .init(epic: "epic1", startedAt: nil), phase: nil, parentId: nil),
            FleetWireTask(id: "b", title: "B", status: "todo", lockedBy: nil, frontmatter: .init(epic: "epic1", startedAt: nil), phase: nil, parentId: nil),
            FleetWireTask(id: "c", title: "C", status: "todo", lockedBy: nil, frontmatter: .init(epic: "epic2", startedAt: nil), phase: nil, parentId: nil),
        ]
        let missions = wires.toMissions()
        XCTAssertEqual(missions.count, 2)
        let epic1 = missions.first { $0.id == "epic1" }!
        XCTAssertEqual(epic1.doneCount, 1)
        XCTAssertEqual(epic1.totalCount, 2)
        let epic2 = missions.first { $0.id == "epic2" }!
        XCTAssertEqual(epic2.doneCount, 0)
        XCTAssertEqual(epic2.totalCount, 1)
    }

    func testFallsBackToParentIdWhenNoEpic() {
        let wire = FleetWireTask(
            id: "t1",
            title: "Task",
            status: "todo",
            lockedBy: nil,
            frontmatter: nil,
            phase: nil,
            parentId: "parent-abc"
        )
        let missions = [wire].toMissions()
        XCTAssertEqual(missions.count, 1)
        XCTAssertEqual(missions[0].id, "parent-abc")
    }

    func testUngroupedWhenNoEpicOrParent() {
        let wire = FleetWireTask(
            id: "t1",
            title: "Orphan",
            status: "failed_validation",
            lockedBy: nil,
            frontmatter: nil,
            phase: nil,
            parentId: nil
        )
        let missions = [wire].toMissions()
        XCTAssertEqual(missions.count, 1)
        XCTAssertEqual(missions[0].id, "ungrouped")
        XCTAssertEqual(missions[0].tasks[0].status, .failedValidation)
    }

    func testStatusIconMapping() {
        XCTAssertEqual(FleetTaskStatus.done.displayIcon, "✅")
        XCTAssertEqual(FleetTaskStatus.inProgress.displayIcon, "🔵")
        XCTAssertEqual(FleetTaskStatus.todo.displayIcon, "⏳")
        XCTAssertEqual(FleetTaskStatus.failedValidation.displayIcon, "❌")
        XCTAssertEqual(FleetTaskStatus.replanFailed.displayIcon, "🔴")
    }

    func testEmptyInputProducesNoMissions() {
        XCTAssertEqual([FleetWireTask]().toMissions().count, 0)
    }

    func testPreservesInsertionOrderOfEpics() {
        let wires = [
            FleetWireTask(id: "1", title: "T1", status: "todo", lockedBy: nil, frontmatter: .init(epic: "z-epic", startedAt: nil), phase: nil, parentId: nil),
            FleetWireTask(id: "2", title: "T2", status: "todo", lockedBy: nil, frontmatter: .init(epic: "a-epic", startedAt: nil), phase: nil, parentId: nil),
        ]
        let missions = wires.toMissions()
        XCTAssertEqual(missions[0].name, "z-epic")
        XCTAssertEqual(missions[1].name, "a-epic")
    }
}
