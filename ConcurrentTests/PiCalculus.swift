//
//  PiCalculus.swift
//  Parallel
//
//  Created by Robert Widmann on 10/8/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Concurrent
import Basis
import XCTest

typealias Name = String

enum π {
	case Simultaneously(Box<π>, Box<π>)
	case Rep(Box<π>)
	case Terminate
	case New(Name, Box<π>)
	case Send(Name, Name, Box<π>)
	case Recieve(Name, Name, Box<π>)
}

struct Mu {
	let c : Chan<Mu>

	init(_ c : Chan<Mu>) {
		self.c = c
	}
}

typealias Environment = Map<Name, Mu>

func forever<A>(io : IO<A>) -> IO<A> {
	return io >> forever(io)
}

func runπ(env : Environment) -> π -> IO<()> {
	return { pi in
		switch pi {
			case .Simultaneously(let ba, let bb):
				let f = { x in forkIO(runπ(env)(x)) }
				return (f(ba.unBox()) >> f(bb.unBox())) >> IO.pure(())
			case .Rep(let bp):
				return runπ(env)(π.Rep(bp))
			case .Terminate:
				return IO.pure(())
			case .New(let bind, let bp):
				return do_ {
					let c : Chan<Mu> = !newChan()
					let mu = Mu(c)
					return runπ(insert(bind)(mu)(env))(bp.unBox())
				}
			case .Send(let dest, let msg, let bp):
				return do_ {
					let w = find(dest)(env)
					!writeChan(w.c)(x: find(msg)(env))
					return runπ(env)(bp.unBox())
				}
			case .Recieve(let src, let bind, let bp):
				return do_ {
					let w = find(src)(env)
					let recv = !readChan(w.c)
					!forkIO(runπ(insert(bind)(recv)(env))(bp.unBox()))
					return IO.pure(())
				}
		}
	}
}

func run(pi : π) -> IO<()> {
	return runπ(empty())(pi)
}

