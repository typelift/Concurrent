//
//  IVarSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/28/16.
//  Copyright © 2016 TypeLift. All rights reserved.
//

import Foundation
import Concurrent
import XCTest
import SwiftCheck

private enum Action {
	case newEmptyIVar
	case newIVar(Int)
	case readIVar
	case putIVar(Int)
	case isEmptyIVar
	case returnInt(Int)
	case returnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

class IVarSpec : XCTestCase {
	func testProperties() {
		property("An empty IVar really is empty") <- self.formulate([.newEmptyIVar, .isEmptyIVar], [.newEmptyIVar, .returnBool(true)])

		property("A filled IVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.newIVar(n), .isEmptyIVar], [.newIVar(n), .returnBool(false)])
		}

		property("Reading a new IVar is the same as a full IVar") <- forAll { (n : Int) in
			return self.formulate([.newIVar(n), .readIVar], [.newIVar(n), .returnInt(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty IVar.
	private func delta(_ b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .readIVar:
				return self.delta(b ? error("read on empty IVar") : false, ac: xs)
			case .returnInt(_):
				fallthrough
			case .returnBool(_):
				fallthrough
			case .isEmptyIVar:
				return self.delta(b, ac: xs)
			case .putIVar(_):
				fallthrough
			case .newIVar(_):
				return self.delta(false, ac: xs)
			case .newEmptyIVar:
				return self.delta(true, ac: xs)
			}
		}
		return b
	}

	// The only thing that couldn't be reproduced.  So take the lazy way out and naïvely unroll the
	// gist of the generator function.
	private func actionsGen(_ e : Bool) -> Gen<ArrayOf<Action>> {
		return Gen.sized({ n in
			var empty = e
			var result = [Action]()
			if n == 0 {
				return Gen.pure(ArrayOf(result))
			}
			while (randomInteger() % UInt32(n)) != 0 {
				if empty {
					result = result + [.putIVar(Int.arbitrary.generate), .readIVar]
					empty = false
				} else {
					result = result + [.readIVar]
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(_ mv : IVar<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .readIVar:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .putIVar(let n):
				try! mv.put(n)
				return perform(mv, xs)
			case .isEmptyIVar:
				let v = mv.tryRead() == nil
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating new IVars in the middle of a performance is forbidden")
			}
		}
		return ([], [])
	}

	private func setupPerformance(_ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = setupPerformance(xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = setupPerformance(xs)
				return ([v] + b, l)
			case .newEmptyIVar:
				return perform(IVar<Int>(), xs)
			case .newIVar(let n):
				return perform(IVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewIVar or NewEmptyIVar must be the first actions")
			}
		}
		return ([], [])
	}


	private func formulate(_ c : [Action], _ d : [Action]) -> Property {
		return forAll(actionsGen(delta(true, ac: c))) { suff in
			let (b1, l1) = self.setupPerformance(c + suff.getArray)
			let (b2, l2) = self.setupPerformance(d + suff.getArray)
			return
				((b1 == b2) <?> "Boolean Values Match")
				^&&^
				((l1 == l2) <?> "IVar Values Match")
		}
	}

	#if !os(macOS) && !os(iOS) && !os(tvOS)
	static var allTests = testCase([
		("testProperties", testProperties),
	])
	#endif
}
