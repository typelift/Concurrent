//
//  STMSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/26/16.
//  Copyright © 2016 TypeLift. All rights reserved.
//

import Concurrent
import XCTest

let initTVars = STM<(TVar<Int>, TVar<Int>)>.pure((TVar(0), TVar(0)))

func optionOne(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return v1.read().flatMap({ x in
		return v1.write(x + 10)
	}).then(STM.retry())
}

func optionTwo(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return v2.read().flatMap { x in
		return v2.write(x + 10)
	}
}

func elseTestA(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return try! optionOne(v1, v2).orElse(optionTwo(v1, v2))
}

func elseTestB(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return try! optionTwo(v1, v2).orElse(optionOne(v1, v2))
}

func elseTestC(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return try! optionTwo(v1, v2).orElse(optionTwo(v1, v2))
}

func elseTestD(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return try! optionOne(v1, v2).orElse(try! optionOne(v1, v2).orElse(optionTwo(v1, v2)))
}

func elseTestE(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<()> {
	return try! optionOne(v1, v2).orElse(optionTwo(v1, v2)).orElse(optionTwo(v1, v2))
}

func snapshot(_ v1 : TVar<Int>, _ v2 : TVar<Int>) -> STM<(Int, Int)> {
	return v1.read().flatMap { s1 in
		return v2.read().flatMap { s2 in
			return STM<(Int, Int)>.pure((s1, s2))
		}
	}
}

class STMSpec : XCTestCase {
	func testMain() {
		let (sv1, sv2) = initTVars.atomically()

		_ = elseTestA(sv1, sv2).atomically()
		_ = {
			let vs = snapshot(sv1, sv2).atomically()
			XCTAssert(vs.0 == 0)
			XCTAssert(vs.1 == 10)
		}()

		_ = elseTestB(sv1, sv2).atomically()
		_ = {
			let vs = snapshot(sv1, sv2).atomically()
			XCTAssert(vs.0 == 0)
			XCTAssert(vs.1 == 20)
		}()

		_ = elseTestC(sv1, sv2).atomically()
		_ = {
			let vs = snapshot(sv1, sv2).atomically()
			XCTAssert(vs.0 == 0)
			XCTAssert(vs.1 == 30)
		}()

		_ = elseTestD(sv1, sv2).atomically()
		_ = {
			let vs = snapshot(sv1, sv2).atomically()
			XCTAssert(vs.0 == 0)
			XCTAssert(vs.1 == 40)
		}()

		_ = elseTestE(sv1, sv2).atomically()
		_ = {
			let vs = snapshot(sv1, sv2).atomically()
			XCTAssert(vs.0 == 0)
			XCTAssert(vs.1 == 50)
		}()
	}

	#if !os(macOS) && !os(iOS) && !os(tvOS)
	static var allTests = testCase([
		("testMain", testMain),
	])
	#endif
}
