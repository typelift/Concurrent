//
//  TChan.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

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
	let hole : TVar<TList<A>> = TVar(TList.TNil)
	let read = TVar(hole)
	let write = TVar(hole)
	return STM<TChan<A>>.pure(TChan(read, write))
}

public func newBroadcastTChan<A>() -> STM<TChan<A>> {
	let hole : TVar<TList<A>> = TVar(TList.TNil)
	let read : TVar<TVar<TList<A>>> = TVar(undefined())
	let write = TVar(hole)
	return STM<TChan<A>>.pure(TChan(read, write))
}

public func newBroadcastTChanIO<A>() -> TChan<A> {
	let hole : TVar<TList<A>> = TVar(TList.TNil)
	let read : TVar<TVar<TList<A>>> = TVar(undefined())
	let write = TVar(hole)
	return TChan(read, write)
}

public func writeTChan<A>(c : TChan<A>, _ val : A) -> STM<()> {
	return readTVar(c.writeHead).flatMap { l in
		let nl : TVar<TList<A>> = TVar(TList.TNil)
		return writeTVar(l, value: TList.TCons(val, nl)).then(writeTVar(c.writeHead, value: nl))
	}
}

public func readTChan<A>(c : TChan<A>) -> STM<A> {
	return readTVar(c.readHead).flatMap { hd in
		return readTVar(hd).flatMap { lst in
			switch lst {
			case .TNil:
				do {
					return try retry()
				} catch _ {
					fatalError()
				}
			case .TCons(let x, let xs):
				return writeTVar(c.readHead, value: xs).then(STM<A>.pure(x))
			}
		}
	}
}

public func tryReadTChan<A>(c : TChan<A>) -> STM<Optional<A>> {
	return readTVar(c.readHead).flatMap { hd in
		return readTVar(hd).flatMap { lst in
			switch lst {
			case .TNil:
				return STM<Optional<A>>.pure(nil)
			case .TCons(let x, let xs):
				return writeTVar(c.readHead, value: xs).then(STM<Optional<A>>.pure(.Some(x)))
			}
		}
	}
}

public func peekTChan<A>(c : TChan<A>) -> STM<A> {
	return readTVar(c.readHead).flatMap { hd in
		return readTVar(hd).flatMap { lst in
			switch lst {
			case .TNil:
				do {
					return try retry()
				} catch _ {
					fatalError()
				}
			case .TCons(let x, _):
				return STM<A>.pure(x)
			}
		}
	}
}

public func tryPeekTChan<A>(c : TChan<A>) -> STM<Optional<A>> {
	return readTVar(c.readHead).flatMap { hd in
		return readTVar(hd).flatMap { lst in
			switch lst {
			case .TNil:
				return STM<Optional<A>>.pure(.None)
			case .TCons(let x, _):
				return STM<Optional<A>>.pure(.Some(x))
			}
		}
	}
}

public func dupTChan<A>(c : TChan<A>) -> STM<TChan<A>> {
	return readTVar(c.writeHead).flatMap { hd in
		let newread = TVar(hd)
		return STM<TChan<A>>.pure(TChan(newread, c.writeHead))
	}
}

public func unGetTChan<A>(c : TChan<A>, _ x : A) -> STM<()> {
	return readTVar(c.readHead).flatMap { hd in
		let newhd = TVar(TList.TCons(x, hd))
		return writeTVar(c.readHead, value: newhd)
	}
}

public func isEmptyTChan<A>(c : TChan<A>) -> STM<Bool> {
	return readTVar(c.readHead).flatMap { hd in
		return readTVar(hd).flatMap { lst in
			switch lst {
			case .TNil:
				return STM<Bool>.pure(true)
			case .TCons(_, _):
				return STM<Bool>.pure(false)
			}
		}
	}
}

public func cloneTChan<A>(c : TChan<A>) -> STM<TChan<A>> {
	return readTVar(c.readHead).flatMap { hd in
		let newread = TVar(hd)
		return STM<TChan<A>>.pure(TChan(newread, c.writeHead))
	}
}

private func undefined<A>() -> A {
	fatalError("")
}
