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
import Swiftz

private enum Action {
	case NewEmptyMVar
	case NewMVar(Int)
	case TakeMVar
	case ReadMVar
	case PutMVar(Int)
	case SwapMVar(Int)
	case IsEmptyMVar
	case ReturnInt(Int)
	case ReturnBool(Bool)
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
		property("An empty MVar really is empty") <- self.formulate([.NewEmptyMVar, .IsEmptyMVar], [.NewEmptyMVar, .ReturnBool(true)])

		property("A filled MVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.NewMVar(n), .IsEmptyMVar], [.NewMVar(n), .ReturnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.NewMVar(n), .TakeMVar], [.NewEmptyMVar, .ReturnInt(n)])
		}

		property("Filling then taking from an empty MVar is the same as an empty MVar") <- forAll { (n : Int) in
			return self.formulate([.NewEmptyMVar, .PutMVar(n), .TakeMVar], [.NewEmptyMVar, .ReturnInt(n)])
		}

		property("Reading a new MVar is the same as a full MVar") <- forAll { (n : Int) in
			return self.formulate([.NewMVar(n), .ReadMVar], [.NewMVar(n), .ReturnInt(n)])
		}

		property("Swapping a full MVar is the same as a full MVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.NewMVar(m), .SwapMVar(n)], [.NewMVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty MVar.
	private func delta(b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])
			switch x {
			case .TakeMVar:
				return self.delta(b ? error("take on empty MVar") : true, ac: xs)
			case .ReadMVar:
				return self.delta(b ? error("read on empty MVar") : false, ac: xs)
			case .SwapMVar(_):
				return self.delta(b ? error("swap on empty MVar") : false, ac: xs)
			case .IsEmptyMVar:
				fallthrough
			case .ReturnInt(_):
				fallthrough
			case .ReturnBool(_):
				fallthrough
			case .IsEmptyMVar:
				return self.delta(b, ac: xs)
			case .PutMVar(_):
				fallthrough
			case .NewMVar(_):
				return self.delta(false, ac: xs)
			case .NewEmptyMVar:
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
			while (rand() % Int32(n)) != 0 {
				if empty {
					result = result + [.PutMVar(Int.arbitrary.generate)] + ((rand() % 2) == 0 ? [.SwapMVar(Int.arbitrary.generate)] : [.ReadMVar])
					empty = false
				} else {
					result = result + [.TakeMVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(mv : MVar<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])

			switch x {
			case .ReturnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .ReturnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .TakeMVar:
				let v = mv.take()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .ReadMVar:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .PutMVar(let n):
				mv.put(n)
				return perform(mv, xs)
			case .SwapMVar(let n):
				mv.swap(n)
				return perform(mv, xs)
			case .IsEmptyMVar:
				let v = mv.isEmpty
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating new MVars in the middle of a performance is forbidden")
			}
		}
		return ([], [])
	}

	private func setupPerformance(ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])

			switch x {
			case .ReturnInt(let v):
				let (b, l) = setupPerformance(xs)
				return (b, [v] + l)
			case .ReturnBool(let v):
				let (b, l) = setupPerformance(xs)
				return ([v] + b, l)
			case .NewEmptyMVar:
				return perform(MVar<Int>(), xs)
			case .NewMVar(let n):
				return perform(MVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewMVar or NewEmptyMVar must be the first actions")
			}
		}
		return ([], [])
	}


	private func formulate(c : [Action], _ d : [Action]) -> Property {
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
