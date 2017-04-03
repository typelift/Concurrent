//
//  MVarSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 5/30/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

import Concurrent
import XCTest
import SwiftCheck
import func Darwin.C.stdlib.arc4random

private enum Action {
	case newEmptyMVar
	case newMVar(Int)
	case takeMVar
	case readMVar
	case putMVar(Int)
	case swapMVar(Int)
	case isEmptyMVar
	case returnInt(Int)
	case returnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

/// This spec is a faithful translation of GHC's MVar tests (except for some Gen stuff relying on 
/// lazy lists).
/// ~(https://github.com/ghc/ghc/blob/master/libraries/base/tests/Concurrent/MVar001.hs)
class MVarSpec : XCTestCase {
	func testProperties() {
		property("An empty MVar really is empty") <- self.formulate([.newEmptyMVar, .isEmptyMVar], [.newEmptyMVar, .returnBool(true)])

		property("A filled MVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.newMVar(n), .isEmptyMVar], [.newMVar(n), .returnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.newMVar(n), .takeMVar], [.newEmptyMVar, .returnInt(n)])
		}

		property("Filling then taking from an empty MVar is the same as an empty MVar") <- forAll { (n : Int) in
			return self.formulate([.newEmptyMVar, .putMVar(n), .takeMVar], [.newEmptyMVar, .returnInt(n)])
		}

		property("Reading a new MVar is the same as a full MVar") <- forAll { (n : Int) in
			return self.formulate([.newMVar(n), .readMVar], [.newMVar(n), .returnInt(n)])
		}

		property("Swapping a full MVar is the same as a full MVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.newMVar(m), .swapMVar(n)], [.newMVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty MVar.
	private func delta(_ b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .takeMVar:
				return self.delta(b ? error("take on empty MVar") : true, ac: xs)
			case .readMVar:
				return self.delta(b ? error("read on empty MVar") : false, ac: xs)
			case .swapMVar(_):
				return self.delta(b ? error("swap on empty MVar") : false, ac: xs)
			case .isEmptyMVar:
				fallthrough
			case .returnInt(_):
				fallthrough
			case .returnBool(_):
				fallthrough
			case .isEmptyMVar:
				return self.delta(b, ac: xs)
			case .putMVar(_):
				fallthrough
			case .newMVar(_):
				return self.delta(false, ac: xs)
			case .newEmptyMVar:
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
			while (arc4random() % UInt32(n)) != 0 {
				if empty {
					result = result + [.putMVar(Int.arbitrary.generate)] + ((arc4random() % 2) == 0 ? [.swapMVar(Int.arbitrary.generate)] : [.readMVar])
					empty = false
				} else {
					result = result + [.takeMVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(_ mv : MVar<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .takeMVar:
				let v = mv.take()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .readMVar:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .putMVar(let n):
				mv.put(n)
				return perform(mv, xs)
			case .swapMVar(let n):
				_ = mv.swap(n)
				return perform(mv, xs)
			case .isEmptyMVar:
				let v = mv.isEmpty
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating new MVars in the middle of a performance is forbidden")
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
			case .newEmptyMVar:
				return perform(MVar<Int>(), xs)
			case .newMVar(let n):
				return perform(MVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewMVar or NewEmptyMVar must be the first actions")
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
				((l1 == l2) <?> "MVar Values Match")
		}
	}
}
