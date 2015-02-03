//
//  ParallelTests.swift
//  ParallelTests
//
//  Created by Robert Widmann on 9/20/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Concurrent
import Swiftx
import XCTest

class ParallelTests: XCTestCase {

	func testConcurrentFuture() {
		var e : NSError?

		let x : Future<Int> = forkFuture {
			usleep(1)
			return 4
		}
		 
		let res = x.read()
		XCTAssert(res == res, "future")
		XCTAssert({ "\($0)" } <^> res == Result.value("4"), "future map")
	}

	func testConcurrentChan() {
		let chan : Chan<Int> = Chan()
		let ft : Future<Int> = forkFuture {
			usleep(1)
			chan.write(2)
			return 2
		}

		let res = ft.read()
		let contents = chan.read()
		switch res {
			case .Error(_):
				XCTAssert(false, "")
			case .Value(let r):
				XCTAssert(contents == r.value, "simple read chan")
		}
	}

	func testConcurrentMVar() {
		let pingvar : MVar<String> = MVar()
		let pongvar : MVar<String> = MVar()
		let done = MVar<Void>()

		let ping : Future<()> = forkFuture {
			pingvar.put("hello")
			let contents = pongvar.take()
			XCTAssert(contents == "max", "mvar read");
			done.put(())
		}
		let pong : Future<()> = forkFuture {
			let contents = pingvar.take()
			XCTAssert(contents == "hello", "mvar read");
			pongvar.put("max")
		}

		done.take()
		XCTAssertTrue(pingvar.isEmpty && pongvar.isEmpty, "mvar empty")
	}

	/// Extracts all eithers that have values in order.
	func values<A>(l : [Result<A>]) -> [A] {
		return l.map({
			switch $0 {
				case .Value(let b):
					return [b.value]
				default:
					return []
			}
		}).reduce([], combine: +)
	}

	
	func testPerformanceExample() {
		// concurrent pi
		let pi : Int -> Float = { n in
			var ar : [() -> Float] = []
			for k in (0..<n) {
				ar.append({ () -> Float in
					return (4 * pow(-1, Float(k)) / (2.0 * Float(k) + 1.0))
				})
			}

			let ch = forkFutures(ar)
			let results = ch.contents()
			return self.values(results).reduce(0, combine: +)
		}

		self.measureBlock() {
			pi(200)
			Void()
		}
	}
	
}
