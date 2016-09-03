//
//  ChanSpec.swift
//  Concurrent
//
//  Created by Robert Widmann on 5/30/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

import Concurrent
import XCTest
import SwiftCheck

private enum Action {
	case newChan
	case readChan
	case writeChan(Int)
	case isEmptyChan
	case returnInt(Int)
	case returnBool(Bool)
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

/// This spec is a faithful translation of GHC's Chan tests (except for some Gen stuff relying on
/// lazy lists).
/// ~(https://github.com/ghc/ghc/blob/master/libraries/base/tests/Concurrent/Chan001.hs)
class ChanSpec : XCTestCase {
	func testProperties() {
		property("New channels start empty") <- self.formulate([.newChan, .isEmptyChan], [.newChan, .returnBool(true)])

		property("Written-to channels are non-empty") <- forAll { (n : Int) in
			return self.formulate([.newChan, .writeChan(n), .isEmptyChan], [.newChan, .writeChan(n), .returnBool(false)])
		}

		property("Reading from a freshly written chan is the same as the value written") <- forAll { (n : Int) in
			return self.formulate([.newChan, .writeChan(n), .readChan], [.newChan, .returnInt(n)])
		}
	}

	// Calculates the number of items in the channel at the end of executing the list of actions.
	fileprivate func delta(_ i : Int, ac : [Action]) -> Int {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .readChan:
				return self.delta((i == 0) ? error("read on empty MVar") : (i - 1), ac: xs)
			case .isEmptyChan:
				fallthrough
			case .returnInt(_):
				fallthrough
			case .returnBool(_):
				fallthrough
			case .isEmptyChan:
				return self.delta(i, ac: xs)
			case .writeChan(_):
				return self.delta(i+1, ac: xs)
			case .newChan:
				return self.delta(0, ac: xs)
			}
		}
		return i
	}

	// Based on the given number of items, produce an item-neutral sequence of fluff actions.
	fileprivate func actionsGen(_ emp : Int) -> Gen<ArrayOf<Action>> {
        var empty = emp
		if empty == 0 {
			return Gen.pure(ArrayOf([]))
		}

		var result = [Action]()
		while empty != 0 {
            empty -= 1
			let branch = arc4random() % 3
			if branch == 0 {
				return Gen.pure(ArrayOf(Array(repeating: .readChan, count: empty) + result))
			} else if branch == 1 {
				result = [.isEmptyChan] + result + [.readChan]
			} else {
				result = [.writeChan(Int.arbitrary.generate)] + result + [.readChan]
			}
		}
		return Gen.pure(ArrayOf(result))
	}

	fileprivate func perform(_ mv : Chan<Int>, _ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			case .readChan:
				let v = mv.read()
				let (b, l) = perform(mv, xs)
				return (b, [v] + l)
			case .writeChan(let n):
				mv.write(n)
				return perform(mv, xs)
			case .isEmptyChan:
				let v = mv.isEmpty
				let (b, l) = perform(mv, xs)
				return ([v] + b, l)
			default:
				return error("Fatal: Creating a new channel in the middle of a performance is forbidden")
			}
		}
		return ([], [])
	}

	fileprivate func setupPerformance(_ ac : [Action]) -> ([Bool], [Int]) {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case .returnInt(let v):
				let (b, l) = setupPerformance(xs)
				return (b, [v] + l)
			case .returnBool(let v):
				let (b, l) = setupPerformance(xs)
				return ([v] + b, l)
			case .newChan:
				return perform(Chan(), xs)
			default:
				return error("Fatal: NewChan must be the first action")
			}
		}
		return ([], [])
	}


	fileprivate func formulate(_ c : [Action], _ d : [Action]) -> Property {
		return forAll(actionsGen(delta(0, ac: c))) { suff in
			let (b1, l1) = self.setupPerformance(c + suff.getArray)
			let (b2, l2) = self.setupPerformance(d + suff.getArray)
			return
				((b1 == b2) <?> "Boolean Values Match")
				^&&^
				((l1 == l2) <?> "MVar Values Match")
		}
	}
}
