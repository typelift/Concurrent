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
	case simultaneously(π, π)
	/// Repeatedly spawn and execute copies of this computation forever.
	case rep(π)
	/// Create a new channel with a given name, then run the next computation.
	case new(Name, π)
	/// Send a value over the channel with a given name, then run the next computation.
	case send(Name, Name, π)
	/// Receive a value on the channel with a given name, bind the result to the name, then run
	/// the next computation.
	case receive(Name, Name, π)
	/// Terminate the process.
	case terminate
}

/// An agent in the Pi-Calculus.  Defined recursively.
struct Mu {
	let c : Chan<Mu>

	init(_ c : Chan<Mu>) {
		self.c = c
	}
}

typealias Environment = Dictionary<Name, Mu>

func runπ(_ env : Environment, _ pi : π) {
	switch pi {
	case .simultaneously(let ba, let bb):
		_ = forkIO(runπ(env, ba))
		_ = forkIO(runπ(env, bb))
	case .rep(let bp):
		return runπ(env, π.rep(bp))
	case .terminate:
		return
	case .new(let bind, let bp):
		let c : Chan<Mu> = Chan()
		let mu = Mu(c)
		return runπ(env.merge([bind: mu]), bp)
	case .send(let msg, let dest, let bp):
		let w = env[dest]
		w?.c.write(env[msg]!)
		return runπ(env, bp)
	case .receive(let src, let bind, let bp):
		let w = env[src]
		if let recv = w?.c.read() {
			_ = forkIO(runπ(env.merge([bind: recv]), bp))
		}
	}
}

extension Dictionary {
	public func merge(_ right: [Key: Value]) -> [Key: Value] {
		var leftc = self
		for (k, v) in right {
			leftc.updateValue(v, forKey: k)
		}
		return leftc
	}
}

func runCompute(_ pi : π) {
	return runπ(Environment(), pi)
}


/// MARK: Mini-DSL

infix operator !|!

func !|! (l : π, r : π) -> π {
	return .simultaneously(l, r)
}

func `repeat`(_ p : π) -> π {
	return .rep(p)
}

func terminate() -> π {
	return .terminate
}

func newChannel(_ n : Name, then : π) -> π {
	return .new(n, then)
}

func send(_ v : Name, on : Name, then : π) -> π {
	return .send(v, on, then)
}

func receive(_ on : Name, v : Name, then : π) -> π {
	return .receive(v, on, then)
}

class PiCalculusSpec : XCTestCase {
	func testPi() {
		let pi = newChannel("x", then:
					(send("x", on: "z", then: terminate())
					!|!
					receive("x", v: "y", then: send("y", on: "x", then: receive("x", v: "y", then: terminate()))))
					!|!
					send("z", on: "v", then: receive("v", v: "v", then: terminate())))
		runCompute(pi)
	}
}

