//
//  PiCalculus.swift
//  Parallel
//
//  Created by Robert Widmann on 10/8/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Concurrent
import XCTest

typealias Name = String

/// An encoding of the Pi Calculus, a process calculus of names and channels with equal expressive
/// power to the Lambda Calculus.
indirect enum π {
	/// Run the left and right computations simultaneously
	case Simultaneously(π, π)
	/// Repeatedly spawn and execute copies of this computation forever.
	case Rep(π)
	/// Create a new channel with a given name, then run the next computation.
	case New(Name, π)
	/// Send a value over the channel with a given name, then run the next computation.
	case Send(Name, Name, π)
	/// Receive a value on the channel with a given name, bind the result to the name, then run
	/// the next computation.
	case Receive(Name, Name, π)
	/// Terminate the process.
	case Terminate
}

/// An agent in the Pi-Calculus.  Defined recursively.
struct Mu {
	let c : Chan<Mu>

	init(_ c : Chan<Mu>) {
		self.c = c
	}
}

typealias Environment = Dictionary<Name, Mu>

func runπ(inout env : Environment, _ pi : π) -> () {
	switch pi {
		case .Simultaneously(let ba, let bb):
			let f = { x in forkIO(runπ(&env, x)) }
			f(ba)
			f(bb)
		case .Rep(let bp):
			return runπ(&env, π.Rep(bp))
		case .Terminate:
			return
		case .New(let bind, let bp):
			let c : Chan<Mu> = Chan()
			let mu = Mu(c)
			env[bind] = mu
			return runπ(&env, bp)
		case .Send(let msg, let dest, let bp):
			let w = env[dest]
			w?.c.write(env[msg]!)
			return runπ(&env, bp)
		case .Receive(let src, let bind, let bp):
			let w = env[src]
			let recv = w?.c.read()
			env[bind] = recv
			forkIO(runπ(&env, bp))
	}
}

func runCompute(pi : π) {
    var ctx = Environment()
	return runπ(&ctx, pi)
}


/// MARK: Mini-DSL

infix operator !|! {
	associativity left
}

func !|! (l : π, r : π) -> π {
	return .Simultaneously(l, r)
}

func `repeat`(p : π) -> π {
	return .Rep(p)
}

func terminate() -> π {
	return .Terminate
}

func newChannel(n : Name, then : π) -> π {
	return .New(n, then)
}

func send(v : Name, on : Name, then : π) -> π {
	return .Send(v, on, then)
}

func receive(on : Name, v : Name, then : π) -> π {
	return .Receive(v, on, then)
}

class PiCalculusSpec : XCTestCase {
	func testPi() {
		let pi = newChannel("x", then:
					send("x", on: "z", then: terminate())
					!|!
					receive("x", v: "y", then: send("y", on: "x", then: receive("x", v: "y", then: terminate())))
					!|!
					send("z", on: "v", then: receive("v", v: "v", then: terminate())))
		runCompute(pi)
	}
}

