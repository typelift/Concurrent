//
//  SVarSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 6/6/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

import Concurrent
import XCTest
import SwiftCheck

private enum Action {
	case newEmptySVar
	case newSVar(Int)
	case takeSVar
	case putSVar(Int)
	case isEmptySVar
	case returnInt(Int)
	case returnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

class SVarSpec : XCTestCase {
	func testProperties() {
		property("An empty SVar really is empty") <- self.formulate([.newEmptySVar, .isEmptySVar], [.newEmptySVar, .returnBool(true)])

		property("A filled SVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.newSVar(n), .isEmptySVar], [.newSVar(n), .returnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.newSVar(n), .takeSVar], [.newEmptySVar, .returnInt(n)])
		}

		property("Filling then taking from an empty SVar is the same as an empty SVar") <- forAll { (n : Int) in
			return self.formulate([.newEmptySVar, .putSVar(n), .takeSVar], [.newEmptySVar, .returnInt(n)])
		}

		property("Taking a new SVar is the same as a full SVar") <- forAll { (n : Int) in
			return self.formulate([.newSVar(n), .takeSVar], [.newSVar(n), .returnInt(n)])
		}

		property("Swapping a full SVar is the same as a full SVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.newSVar(m), .putSVar(n)], [.newSVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty SVar.
	private func delta(_ b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .takeSVar:
				return self.delta(b ? error("take on empty SVar") : true, ac: xs)
			case .returnInt(_):
				fallthrough
			case .returnBool(_):
				fallthrough
			case .isEmptySVar:
				return self.delta(b, ac: xs)
			case .putSVar(_):
				fallthrough
			case .newSVar(_):
				return self.delta(false, ac: xs)
			case .newEmptySVar:
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
					result = result + [.putSVar(Int.arbitrary.generate)]
					empty = false
				} else {
					result = result + [.takeSVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(_ mv : SVar<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .takeSVar:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .putSVar(let n):
				mv.write(n)
				return perform(mv, xs)
			case .isEmptySVar:
				let v = mv.isEmpty
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating new SVars in the middle of a performance is forbidden")
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
			case .newEmptySVar:
				return perform(SVar<Int>(), xs)
			case .newSVar(let n):
				return perform(SVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewSVar or NewEmptySVar must be the first actions")
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
				((l1 == l2) <?> "SVar Values Match")
		}
	}

	#if !os(macOS) && !os(iOS) && !os(tvOS)
	static var allTests = testCase([
		("testProperties", testProperties),
	])
	#endif
}
