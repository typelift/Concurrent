//
//  ConcurrentSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 8/8/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

import XCTest

public func error<A>(x : String) -> A {
	XCTFail(x)
	fatalError(x)
}
