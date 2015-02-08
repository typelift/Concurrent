//
//  TChan.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

internal enum TList<A> {
	case TNil
	case TCons(A, TVar<TList<A>>)
}

public struct TChan<A> {
	let readHead : TVar<TVar<TList<A>>>
	let writeHead : TVar<TVar<TList<A>>>

	private init(_ readHead : TVar<TVar<TList<A>>>, _ writeHead : TVar<TVar<TList<A>>>) {
		self.readHead = readHead
		self.writeHead = writeHead
	}
	
	public init() {
		let hole : TVar<TList<A>> = TVar(TList.TNil)
		let read = TVar(hole)
		let write = TVar(hole)
		self = TChan(read, write)
	}
}

public func newTChan<A>() -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hole : TVar<TList<A>> = !newTVar(TList.TNil)
		let read = !newTVar(hole)
		let write = !newTVar(hole)
		return TChan(read, write)
	}
}

public func newBroadcastTChan<A>() -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hole : TVar<TList<A>> = !newTVar(TList.TNil)
		let read : TVar<TVar<TList<A>>> = !newTVar(error(""))
		let write = !newTVar(hole)
		return TChan(read, write)
	}
}

public func newBroadcastTChanIO<A>() -> TChan<A> {
	let hole : TVar<TList<A>> = TVar(TList.TNil)
	let read : TVar<TVar<TList<A>>> = TVar(error(""))
	let write = TVar(hole)
	return TChan(read, write)
}

public func writeTChan<A>(c : TChan<A>) -> A -> STM<()> {
	return { x in
		do_ { () -> () in
			let l = !readTVar(c.writeHead)
			let nl : TVar<TList<A>> = !newTVar(TList.TNil)
			writeTVar(l)(x: TList.TCons(x, nl))
			writeTVar(c.writeHead)(x: nl)
		}
	}
}

public func readTChan<A>(c : TChan<A>) -> STM<A> {
	return do_ {
		let hd = !readTVar(c.readHead)
		let lst = !readTVar(hd)
		switch lst {
			case .TNil:
				return retry()
			case .TCons(let x, let xs):
				return do_ { () -> A in
					writeTVar(c.readHead)(x: xs)
					return x
				}
		}
	}
}

public func tryReadTChan<A>(c : TChan<A>) -> STM<Optional<A>> {
	return do_ { () -> STM<Optional<A>> in
		let hd = !readTVar(c.readHead)
		let lst = !readTVar(hd)
		switch lst {
			case .TNil:
				return do_ { () in .None }
			case .TCons(let x, let xs):
				return do_ { () -> Optional<A> in
					writeTVar(c.readHead)(x: xs)
					return .Some(x)
				}
		}
	}
}

public func peekTChan<A>(c : TChan<A>) -> STM<A> {
	return do_ { () -> STM<A> in
		let hd = !readTVar(c.readHead)
		let lst = !readTVar(hd)
		switch lst {
			case .TNil:
				return retry()
			case .TCons(let x, let xs):
				return do_ { () in x }
		}
	}
}

public func tryPeekTChan<A>(c : TChan<A>) -> STM<Optional<A>> {
	return do_ { () -> Optional<A> in
		let hd = !readTVar(c.readHead)
		let lst = !readTVar(hd)
		switch lst {
			case .TNil:
				return .None
			case .TCons(let x, let xs):
				return .Some(x)
		}
	}
}

public func dupTChan<A>(c : TChan<A>) -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hd = !readTVar(c.writeHead)
		let newread = !newTVar(hd)
		return TChan(newread, c.writeHead)
	}
}

public func unGetTChan<A>(c : TChan<A>) -> A -> STM<()> {
	return { x in
		do_ {
			let hd = !readTVar(c.readHead)
			let newhd = !newTVar(TList.TCons(x, hd))
			return writeTVar(c.readHead)(x: newhd)
		}
	}
}

public func isEmptyTChan<A>(c : TChan<A>) -> STM<Bool> {
	return do_ { () -> Bool in
		let hd = !readTVar(c.readHead)
		let lst = !readTVar(hd)
		switch lst {
			case .TNil:
				return true
			case .TCons(_, _):
				return false
		}
	}
}

public func cloneTChan<A>(c : TChan<A>) -> STM<TChan<A>> {
	return do_ { () -> TChan<A> in
		let hd = !readTVar(c.readHead)
		let newread = !newTVar(hd)
		return TChan(newread, c.writeHead)
	}
}



