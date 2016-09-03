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
	case NewEmptyTMVar
	case NewTMVar(Int)
	case TakeTMVar
	case ReadTMVar
	case PutTMVar(Int)
	case SwapTMVar(Int)
	case IsEmptyTMVar
	case ReturnInt(Int)
	case ReturnBool(Bool)
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
		property("An empty TMVar really is empty") <- self.formulate([.NewEmptyTMVar, .IsEmptyTMVar], [.NewEmptyTMVar, .ReturnBool(true)])

		property("A filled TMVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.NewTMVar(n), .IsEmptyTMVar], [.NewTMVar(n), .ReturnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.NewTMVar(n), .TakeTMVar], [.NewEmptyTMVar, .ReturnInt(n)])
		}

		property("Filling then taking from an empty TMVar is the same as an empty TMVar") <- forAll { (n : Int) in
			return self.formulate([.NewEmptyTMVar, .PutTMVar(n), .TakeTMVar], [.NewEmptyTMVar, .ReturnInt(n)])
		}

		property("Reading a new TMVar is the same as a full TMVar") <- forAll { (n : Int) in
			return self.formulate([.NewTMVar(n), .ReadTMVar], [.NewTMVar(n), .ReturnInt(n)])
		}

		property("Swapping a full TMVar is the same as a full TMVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.NewTMVar(m), .SwapTMVar(n)], [.NewTMVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty TMVar.
	private func delta(b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])
			switch x {
			case .TakeTMVar:
				return self.delta(b ? error("take on empty TMVar") : true, ac: xs)
			case .ReadTMVar:
				return self.delta(b ? error("read on empty TMVar") : false, ac: xs)
			case .SwapTMVar(_):
				return self.delta(b ? error("swap on empty TMVar") : false, ac: xs)
			case .IsEmptyTMVar:
				fallthrough
			case .ReturnInt(_):
				fallthrough
			case .ReturnBool(_):
				fallthrough
			case .IsEmptyTMVar:
				return self.delta(b, ac: xs)
			case .PutTMVar(_):
				fallthrough
			case .NewTMVar(_):
				return self.delta(false, ac: xs)
			case .NewEmptyTMVar:
				return self.delta(true, ac: xs)
			}
		}
		return b
	}

	// The only thing that couldn't be reproduced.  So take the lazy way out and naïvely unroll the
	// gist of the generator function.
	private func actionsGen(e : Bool) -> Gen<ArrayOf<Action>> {
		return Gen.sized({ n in
			var empty = e
			var result = [Action]()
			if n == 0 {
				return Gen.pure(ArrayOf(result))
			}
			while (arc4random() % UInt32(n)) != 0 {
				if empty {
					result = result + [.PutTMVar(Int.arbitrary.generate)] + ((arc4random() % 2) == 0 ? [.SwapTMVar(Int.arbitrary.generate)] : [.ReadTMVar])
					empty = false
				} else {
					result = result + [.TakeTMVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(mv : TMVar<Int>, _ ac : [Action]) -> STM<([Bool], [Int])> {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])

			switch x {
			case .ReturnInt(let v):
				return perform(mv, xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure((b, [v] + l))
				}
			case .ReturnBool(let v):
				return perform(mv, xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure(([v] + b, l))
				}
			case .TakeTMVar:
				return takeTMVar(mv).flatMap { v in
					return self.perform(mv, xs).flatMap { (b, l) in
						return STM<([Bool], [Int])>.pure((b, [v] + l))
					}
				}
			case .ReadTMVar:
				return readTMVar(mv).flatMap { v in
					return self.perform(mv, xs).flatMap { (b, l) in
						return STM<([Bool], [Int])>.pure((b, [v] + l))
					}
				}
			case .PutTMVar(let n):
				return putTMVar(mv, n).then(perform(mv, xs))
			case .SwapTMVar(let n):
				return swapTMVar(mv, n).then(perform(mv, xs))
			case .IsEmptyTMVar:
				return isEmptyTMVar(mv).flatMap { v in
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

	private func setupPerformance(ac : [Action]) -> STM<([Bool], [Int])> {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])

			switch x {
			case .ReturnInt(let v):
				return setupPerformance(xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure((b, [v] + l))
				}
			case .ReturnBool(let v):
				return setupPerformance(xs).flatMap { (b, l) in
					return STM<([Bool], [Int])>.pure(([v] + b, l))
				}
			case .NewEmptyTMVar:
				return perform(TMVar<Int>(), xs)
			case .NewTMVar(let n):
				return perform(TMVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewTMVar or NewEmptyTMVar must be the first actions")
			}
		}
		return STM<([Bool], [Int])>.pure(([], []))
	}


	private func formulate(c : [Action], _ d : [Action]) -> Property {
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
