//
//  ConcurrentSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 8/8/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

import XCTest
import Concurrent
@testable import SwiftCheck
import Dispatch

public func error<A>(_ x : String) -> A {
	XCTFail(x)
	fatalError(x)
}

public func parCheck(_ t : Testable, _ n : UInt) -> Bool {
	let chan = Chan<Bool>()
	DispatchQueue.concurrentPerform(iterations: Int(n)) { _ in
		switch quickCheckWithResult(CheckerArguments(name: ""), t) {
		case .failure(_, _, _, _, _, _, _):
			chan.write(false)
		case .noExpectedFailure(_, _, _, _, _):
			chan.write(false)
		case .insufficientCoverage(_, _, _, _, _):
			chan.write(false)
		default:
			chan.write(true)
		}
	}
	return chan.contents().reduce(true, { $0 && $1 })
}
