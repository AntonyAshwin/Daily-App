//
//  DailyAppTests.swift
//  DailyAppTests
//
//  Created by Ashwin, Antony on 12/10/25.
//

import Testing
@testable import DailyApp

struct DailyAppTests {

    @Test func parserTrimsAndSplits() throws {
        let input = " Workout , Read Book, ,Meditate ,,  Code  "
        let parsed = TaskInputParser.parse(input)
        #expect(parsed == ["Workout", "Read Book", "Meditate", "Code"])
    }
}
