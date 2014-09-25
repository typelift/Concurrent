//
//  ParallelTests.swift
//  ParallelTests
//
//  Created by Robert Widmann on 9/20/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Parallel
import Basis
import XCTest

class ParallelTests: XCTestCase {
    
	func testConcurrentFuture() {
		var e : NSError?
		var x : Future<Int>!

		x <- forkFuture(do_ { () -> Int in
			usleep(1)
			return 4
		})
		var res : Result<Int>!
		res <- readFuture(x)
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
		var chan : Chan<Int>!
		var ft : Future<Int>!
		var contents : Int!

		chan <- newChan()
		ft <- forkFuture(do_ { () -> Int in
			var exec : ()
			usleep(1)
			exec <- writeChan(chan)(x: 2)
			return 2
		})

		var res : Result<Int>!
		res <- readFuture(ft)

		contents <- readChan(chan)
		switch res.destruct() {
			case .Error(_):
				XCTAssert(false, "")
			case .Value(let r):
				XCTAssert(contents! == r.unBox(), "simple read chan")
		}
	}

	func testConcurrentMVar() {
		var pingvar: MVar<String>!
		var pongvar: MVar<String>!
		var done: MVar<()>!

		pingvar <- newEmptyMVar()
		pongvar <- newEmptyMVar()
		done <- newEmptyMVar()

		var ping : Future<()>!
		var pong : Future<()>!

		ping <- forkFuture(do_ { () -> () in
			var exec : ()
			var contents : String!

			exec <- putMVar(pingvar)(x: "hello")
			contents <- takeMVar(pongvar)
			XCTAssert(contents == "max", "mvar read");
			exec <- putMVar(done)(x: ())
		})
		pong <- forkFuture(do_ { () -> () in
			var exec : ()
			var contents : String!


			contents <- takeMVar(pingvar)
			XCTAssert(contents == "hello", "mvar read");
			exec <- putMVar(pongvar)(x: "max")
		})

		var contents : ()
		contents <- takeMVar(done)

		var empty : Bool!
		var empty2 : Bool!

		empty <- isEmptyMVar(pingvar)
		empty2 <- isEmptyMVar(pongvar)
		XCTAssertTrue(empty! && empty2!, "mvar empty")
	}

	func testPerformanceExample() {
		// concurrent pi
		let pi:Int -> Float = {
			(n:Int) -> Float in
			var ch : Chan<Result<Float>>!
			var results : [Result<Float>]!

			var ar : [IO<Float>] = []
			for k in (0..<n) {
				ar.append(do_ { () -> Float in
					return (4 * pow(-1, Float(k)) / (2.0 * Float(k) + 1.0))
				})
			}

			ch <- forkFutures(ar)
			results <- getChanContents(ch)
			return foldr(+)(z: 0)(l: rights(results))
		}


		self.measureBlock() {
			pi(200)
			Void()
		}
	}

}
