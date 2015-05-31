//
//  STMSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 2/8/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

import Concurrent
import func Swiftz.>>-
import XCTest

public class Coordinate : Equatable {
	public var x : Int = 0 
	public var y : Int = 0
	
	public init(_ x : Int, _ y : Int) {
		self.x = x
		self.y = y
	}
	
	public func getXY() -> (Int, Int) {
		return (self.x, self.y)
	}
}

public func ==(lhs : Coordinate, rhs : Coordinate) -> Bool {
	if (lhs.x == rhs.x) && (lhs.y == rhs.y) {
		return true
	} else {
		return false
	}
}

class STMSpec : XCTestCase {
	func testAll() {
		let someObj = Coordinate(11, 23)
		
		var tvar1 = TVar(someObj)
		let stmTest1 = tvar1.write(Coordinate(4,7))
			.then(tvar1.read())
			.then(tvar1.write(Coordinate(6,9)))
			.then(tvar1.read())
		
		let (x1, y1) = atomically(stmTest1).getXY()
		
		var tvar2 = TVar(someObj)
	
		let (x2, y2) = atomically(tvar2.read()).getXY()
	
		// XCTAssert(x1 == 6 && y1 == 9, "writeTVar then readTVar OK")
		XCTAssert(x2 == 11 && y2 == 23, "readTVar OK")
	}
}
