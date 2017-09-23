//
//  QSemSpec.swift
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
	case newQSem(UInt)
	case signalQSem
	case waitQSem
}

// Here to make the typechecker happy.  Do not invoke these.
extension Action : Arbitrary {
	static var arbitrary : Gen<Action> { return error("Cannot generate arbitrary Action.") }
}

class QSemSpec : XCTestCase {
	func testProperties() {
		property("Signaling and Waiting cancels") <- forAll { (n : UInt, iter : UInt) in
			return self.formulate([.newQSem(n), .signalQSem, .waitQSem], [.newQSem(n)])
		}

		property("Waiting and Signaling cancels") <- forAll { (n : UInt) in
			return (n >= 1) ==> self.formulate([.newQSem(n), .waitQSem, .signalQSem], [.newQSem(n)])
		}
	}

	// Returns whether or not a sequence of Actions leaves us with a full or empty QSem.
	private func delta(_ i : UInt, ac : [Action]) -> UInt {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case let .newQSem(i):
				return delta(i, ac: xs)
			case .signalQSem:
				return self.delta(i + 1, ac: xs)
			case .waitQSem:
				if i == 0 {
					fatalError("Wait on 'empty' QSem")
				}
				return i - 1
			}
		}
		return i
	}

	// The only thing that couldn't be reproduced.  So take the lazy way out and naïvely unroll the
	// gist of the generator function.
	private func actionsGen(_ i : UInt) -> Gen<ArrayOf<Action>> {
		return Gen.sized({ n in
			var quantity = i
			var result = [Action]()
			if n == 0 {
				return Gen.pure(ArrayOf(result))
			}
			while (randomInteger() % UInt32(n)) != 0 {
				if quantity <= 0 {
					result.append(.signalQSem)
					quantity += 1
				} else {
					result.append(.waitQSem)
					quantity -= 1
				}
			}
			return Gen.pure(ArrayOf(result))
		})
	}

	private func perform(_ qs : QSem, _ ac : [Action]) -> UInt {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])
			switch x {
			case .signalQSem:
				qs.signal()
				return perform(qs, xs)
			case .waitQSem:
				qs.wait()
				return perform(qs, xs)
			default:
				return error("Fatal: Creating new QSems in the middle of a performance is forbidden")
			}
		}
		return 0
	}

	private func setupPerformance(_ ac : [Action]) -> UInt {
		if let x = ac.first {
			let xs = [Action](ac[ac.indices.suffix(from: 1)])

			switch x {
			case let .newQSem(n):
				let qs = QSem(initial: n)
				return perform(qs, xs)
			default:
				return error("Fatal: NewQSem or NewEmptyQSem must be the first actions")
			}
		}
		return 0
	}


	private func formulate(_ c : [Action], _ d : [Action]) -> Property {
		return forAll(actionsGen(delta(0, ac: c))) { suff in
			return
				self.setupPerformance(c + suff.getArray)
				==
				self.setupPerformance(d + suff.getArray)
		}
	}

	#if !os(macOS) && !os(iOS) && !os(tvOS)
	static var allTests = testCase([
		("testProperties", testProperties),
	])
	#endif
}
