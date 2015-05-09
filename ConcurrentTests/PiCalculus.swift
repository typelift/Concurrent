//
//  PiCalculus.swift
//  Parallel
//
//  Created by Robert Widmann on 10/8/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Concurrent
import class Swiftz.Box
import XCTest

typealias Name = String

/// An encoding of the Pi Calculus, a process calculus of names and channels with equal expressive
/// power to the Lambda Calculus.
enum π {
	/// Run the left and right computations simultaneously
	case Simultaneously(Box<π>, Box<π>)
	/// Repeatedly spawn and execute copies of this computation forever.
	case Rep(Box<π>)
	/// Create a new channel with a given name, then run the next computation.
	case New(Name, Box<π>)
	/// Send a value over the channel with a given name, then run the next computation.
	case Send(Name, Name, Box<π>)
	/// Recieve a value on the channel with a given name, bind the result to the name, then run
	/// the next computation.
	case Recieve(Name, Name, Box<π>)
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

func forever<A>(@autoclosure(escaping) io :  () -> A) -> (() -> A) {
	return { 
		io() 
		return forever(io)() 
	}
}

func runπ(var env : Environment, pi : π) -> () {
	switch pi {
		case .Simultaneously(let ba, let bb):
			let f = { x in forkIO(runπ(env, x)) }
			f(ba.value)
			f(bb.value)
		case .Rep(let bp):
			return runπ(env, π.Rep(bp))
		case .Terminate:
			return
		case .New(let bind, let bp):
			let c : Chan<Mu> = Chan()
			let mu = Mu(c)
			env[bind] = mu
			return runπ(env, bp.value)
		case .Send(let msg, let dest, let bp):
			let w = env[dest]
			w?.c.write(env[msg]!)
			return runπ(env, bp.value)
		case .Recieve(let src, let bind, let bp):
			let w = env[src]
			let recv = w?.c.read()
			env[bind] = recv
			forkIO(runπ(env, bp.value))
	}
}

func runCompute(pi : π) {
	return runπ(Dictionary(), pi)
}


/// MARK: Mini-DSL

infix operator !|! {
	associativity left
}

func !|! (l : π, r : π) -> π {
	return .Simultaneously(Box(l), Box(r))
}

func repeat(p : π) -> π {
	return .Rep(Box(p))
}

func terminate() -> π {
	return .Terminate
}

func newChannel(n : Name, then : π) -> π {
	return .New(n, Box(then))
}

func send(v : Name, on : Name, then : π) -> π {
	return .Send(v, on, Box(then))
}

func recieve(on : Name, v : Name, then : π) -> π {
	return .Recieve(v, on, Box(then))
}

class PiCalculusSpec : XCTestCase {
	func testPi() {
		let pi = newChannel("x", send("x", "z", terminate()) !|! recieve("x", "y", send("y", "x", recieve("x", "y", terminate()))) !|! send("z", "v", recieve("v", "v", terminate())))
		runCompute(pi)
	}
}

