//
//  ParallelTests.swift
//  ParallelTests
//
//  Created by Robert Widmann on 9/20/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Concurrent
import Basis
import XCTest

class ParallelTests: XCTestCase {

	func testConcurrentFuture() {
		var e : NSError?

		let x = !forkFuture(do_ { () -> Int in
			usleep(1)
			return 4
		})
		let res = !readFuture(x)
		//		XCTAssert(res == res, "future")
		//		XCTAssert(x.map({ $0.description }).result() == "4", "future map")
		//		XCTAssert(x.flatMap({ (x: Int) -> Future<Int> in
		//			return forkPromise(do_ { usleep(1); return x + 1 })
		//		}).result() == 5, "future flatMap")

		//    let x: Future<Int> = Future(exec: gcdExecutionContext, {
		//      return NSString.stringWithContentsOfURL(NSURL.URLWithString("http://github.com"), encoding: 0, error: nil)
		//    })
		//    let x1 = (x.result().lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
		//    let x2 = (x.result().lengthOfBytesUsingEncoding(NSUTF8StringEncoding))
		//    XCTAssert(x1 == x2)
	}

	func testConcurrentChan() {
		let chan : Chan<Int> = !newChan()
		let ft = !forkFuture(do_ { () -> Int in
			var exec : ()
			usleep(1)
			!writeChan(chan)(x: 2)
			return 2
		})

		let res = !readFuture(ft)
		let contents = !readChan(chan)
		switch res.destruct() {
			case .Error(_):
				XCTAssert(false, "")
			case .Value(let r):
				XCTAssert(contents == r.unBox(), "simple read chan")
		}
	}

	func testConcurrentMVar() {
		let pingvar : MVar<String> = !newEmptyMVar()
		let pongvar : MVar<String> = !newEmptyMVar()
		let done : MVar<()> = !newEmptyMVar()

		let ping = !forkFuture(do_ { () -> () in
			!putMVar(pingvar)("hello")
			let contents = !takeMVar(pongvar)
			XCTAssert(contents == "max", "mvar read");
			!putMVar(done)(())
		})
		let pong = !forkFuture(do_ { () -> () in
			let contents =  !takeMVar(pingvar)
			XCTAssert(contents == "hello", "mvar read");
			!putMVar(pongvar)("max")
		})

		!takeMVar(done)
		XCTAssertTrue(!isEmptyMVar(pingvar) && !isEmptyMVar(pongvar), "mvar empty")
	}

	func testPerformanceExample() {
		// concurrent pi
		let pi:Int -> Float = {
			(n:Int) -> Float in

			var ar : [IO<Float>] = []
			for k in (0..<n) {
				ar.append(do_ { () -> Float in
					return (4 * pow(-1, Float(k)) / (2.0 * Float(k) + 1.0))
					})
			}

			let ch = !forkFutures(ar)
			let results = !getChanContents(ch)
			return foldr(+)(0)(values(results))
		}


		self.measureBlock() {
			pi(200)
			Void()
		}
	}
	
}
