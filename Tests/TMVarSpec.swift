//
//  TMVarSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

import Concurrent
import XCTest
import SwiftCheck
import func Darwin.C.stdlib.arc4random

private enum Action {
	case newEmptyTMVar
	case newTMVar(Int)
	case takeTMVar
	case readTMVar
	case putTMVar(Int)
	case swapTMVar(Int)
	case isEmptyTMVar
	case returnInt(Int)
	case returnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

/// This spec is a faithful translation of GHC's TMVar tests (except for some Gen stuff relying on
/// lazy lists).
/// ~(https://github.com/ghc/ghc/blob/master/libraries/base/tests/Concurrent/TMVar001.hs)
class TMVarSpec : XCTestCase {
	func testProperties() {
		property("An empty TMVar really is empty") <- self.formulate([.newEmptyTMVar, .isEmptyTMVar], [.newEmptyTMVar, .returnBool(true)])

		property("A filled TMVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.newTMVar(n), .isEmptyTMVar], [.newTMVar(n), .returnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.newTMVar(n), .takeTMVar], [.newEmptyTMVar, .returnInt(n)])
		}

		property("Filling then taking from an empty TMVar is the same as an empty TMVar") <- forAll { (n : Int) in
			return self.formulate([.newEmptyTMVar, .putTMVar(n), .takeTMVar], [.newEmptyTMVar, .returnInt(n)])
		}

		property("Reading a new TMVar is the same as a full TMVar") <- forAll { (n : Int) in
			return self.formulate([.newTMVar(n), .readTMVar], [.newTMVar(n), .returnInt(n)])
		}

		property("Swapping a full TMVar is the same as a full TMVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.newTMVar(m), .swapTMVar(n)], [.newTMVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty TMVar.
	private func delta(_ b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .takeTMVar:
				return self.delta(b ? error("take on empty TMVar") : true, ac: xs)
			case .readTMVar:
				return self.delta(b ? error("read on empty TMVar") : false, ac: xs)
			case .swapTMVar(_):
				return self.delta(b ? error("swap on empty TMVar") : false, ac: xs)
			case .isEmptyTMVar:
				fallthrough
			case .returnInt(_):
				fallthrough
			case .returnBool(_):
				fallthrough
			case .isEmptyTMVar:
				return self.delta(b, ac: xs)
			case .putTMVar(_):
				fallthrough
			case .newTMVar(_):
				return self.delta(false, ac: xs)
			case .newEmptyTMVar:
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
					result = result + [.putTMVar(Int.arbitrary.generate)] + ((arc4random() % 2) == 0 ? [.swapTMVar(Int.arbitrary.generate)] : [.readTMVar])
					empty = false
				} else {
					result = result + [.takeTMVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(_ mv : TMVar<Int>, _ ac : [Action]) -> STM<([Bool], [Int])> {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				return perform(mv, xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure((b, [v] + l))
				}
			case .returnBool(let v):
				return perform(mv, xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure(([v] + b, l))
				}
			case .takeTMVar:
				return mv.take().flatMap { v in
					return self.perform(mv, xs).flatMap { (b, l) in
						return STM<([Bool], [Int])>.pure((b, [v] + l))
					}
				}
			case .readTMVar:
				return mv.read().flatMap { v in
					return self.perform(mv, xs).flatMap { (b, l) in
						return STM<([Bool], [Int])>.pure((b, [v] + l))
					}
				}
			case .putTMVar(let n):
				return mv.put(n).then(perform(mv, xs))
			case .swapTMVar(let n):
				return mv.swap(n).then(perform(mv, xs))
			case .isEmptyTMVar:
				return mv.isEmpty().flatMap { v in
					return self.perform(mv, xs).flatMap { (b, l) in
						return STM<([Bool], [Int])>.pure(([v] + b, l))
					}
				}
			default:
				return error("Fatal: Creating new TMVars in the middle of a performance is forbidden")
			}
		}
		return STM<([Bool], [Int])>.pure(([], []))
	}

	private func setupPerformance(_ ac : [Action]) -> STM<([Bool], [Int])> {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				return setupPerformance(xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure((b, [v] + l))
				}
			case .returnBool(let v):
				return setupPerformance(xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure(([v] + b, l))
				}
			case .newEmptyTMVar:
				return perform(TMVar<Int>(), xs)
			case .newTMVar(let n):
				return perform(TMVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewTMVar or NewEmptyTMVar must be the first actions")
			}
		}
		return STM<([Bool], [Int])>.pure(([], []))
	}


	private func formulate(_ c : [Action], _ d : [Action]) -> Property {
		return forAll(actionsGen(delta(true, ac: c))) { suff in
			let (b1, l1) = self.setupPerformance(c + suff.getArray).atomically()
			let (b2, l2) = self.setupPerformance(d + suff.getArray).atomically()
			return
				((b1 == b2) <?> "Boolean Values Match")
				^&&^
				((l1 == l2) <?> "TMVar Values Match")
		}
	}
}
