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
import func Darwin.C.stdlib.arc4random

private enum Action {
	case NewEmptySVar
	case NewSVar(Int)
	case TakeSVar
	case PutSVar(Int)
	case IsEmptySVar
	case ReturnInt(Int)
	case ReturnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

class SVarSpec : XCTestCase {
	func testProperties() {
		property("An empty SVar really is empty") <- self.formulate([.NewEmptySVar, .IsEmptySVar], [.NewEmptySVar, .ReturnBool(true)])

		property("A filled SVar really is filled") <- forAll { (n : Int) in
			return self.formulate([.NewSVar(n), .IsEmptySVar], [.NewSVar(n), .ReturnBool(false)])
		}

		property("A take after filling == A return after an empty") <- forAll { (n : Int) in
			return self.formulate([.NewSVar(n), .TakeSVar], [.NewEmptySVar, .ReturnInt(n)])
		}

		property("Filling then taking from an empty SVar is the same as an empty SVar") <- forAll { (n : Int) in
			return self.formulate([.NewEmptySVar, .PutSVar(n), .TakeSVar], [.NewEmptySVar, .ReturnInt(n)])
		}

		property("Taking a new SVar is the same as a full SVar") <- forAll { (n : Int) in
			return self.formulate([.NewSVar(n), .TakeSVar], [.NewSVar(n), .ReturnInt(n)])
		}

		property("Swapping a full SVar is the same as a full SVar with the swapped value") <- forAll { (m : Int, n : Int) in
			return self.formulate([.NewSVar(m), .PutSVar(n)], [.NewSVar(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty SVar.
	private func delta(b : Bool, ac : [Action]) -> Bool {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])
			switch x {
			case .TakeSVar:
				return self.delta(b ? error("take on empty SVar") : true, ac: xs)
			case .IsEmptySVar:
				fallthrough
			case .ReturnInt(_):
				fallthrough
			case .ReturnBool(_):
				fallthrough
			case .IsEmptySVar:
				return self.delta(b, ac: xs)
			case .PutSVar(_):
				fallthrough
			case .NewSVar(_):
				return self.delta(false, ac: xs)
			case .NewEmptySVar:
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
					result = result + [.PutSVar(Int.arbitrary.generate)]
					empty = false
				} else {
					result = result + [.TakeSVar]
					empty = true
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(mv : SVar<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[1..<ac.endIndex])

			switch x {
			case .ReturnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .ReturnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .TakeSVar:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .PutSVar(let n):
				mv.write(n)
				return perform(mv, xs)
			case .IsEmptySVar:
				let v = mv.isEmpty
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating new SVars in the middle of a performance is forbidden")
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
			case .NewEmptySVar:
				return perform(SVar<Int>(), xs)
			case .NewSVar(let n):
				return perform(SVar<Int>(initial: n), xs)
			default:
				return error("Fatal: NewSVar or NewEmptySVar must be the first actions")
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
				((l1 == l2) <?> "SVar Values Match")
		}
	}
}
