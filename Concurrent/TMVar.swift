//
//  TMVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TMVar<A> {
	let tvar : TVar<Optional<A>>

	public init() {
		self.tvar = TVar<Optional<A>>(nil)
	}

	public init(initial : A) {
		self.tvar = TVar<Optional<A>>(.Some(initial))
	}
}

public func takeTMVar<A>(v : TMVar<A>) -> STM<A> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			do {
				return try retry()
			} catch _ {
				fatalError()
			}
		case .Some(let x):
			return writeTVar(v.tvar, value: .None).then(STM<A>.pure(x))
		}
	}
}

public func takeTMVar<A>(v : TMVar<A>) -> STM<Optional<A>> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			return STM<Optional<A>>.pure(.None)
		case .Some(let x):
			return writeTVar(v.tvar, value: .None).then(STM<A>.pure(.Some(x)))
		}
	}
}

public func putTMVar<A>(v : TMVar<A>, _ val : A) -> STM<()> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			return writeTVar(v.tvar, value: .Some(val))
		case .Some(_):
			do {
				return try retry()
			} catch _ {
				fatalError()
			}
		}
	}
}

public func tryPutTMVar<A>(v : TMVar<A>, _ val : A) -> STM<Bool> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			return writeTVar(v.tvar, value: .Some(val)).then(STM<Bool>.pure(true))
		case .Some(_):
			return STM<Bool>.pure(false)
		}
	}
}

public func readTMVar<A>(v : TMVar<A>) -> STM<A> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			do {
				return try retry()
			} catch _ {
				fatalError()
			}
		case .Some(let x):
			return STM<A>.pure(x)
		}
	}
}

public func tryReadTMVar<A>(v : TMVar<A>) -> STM<Optional<A>> {
	return readTVar(v.tvar)
}

public func swapTMVar<A>(v : TMVar<A>, _ new : A) -> STM<A> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			do {
				return try retry()
			} catch _ {
				fatalError()
			}
		case .Some(let old):
			return writeTVar(v.tvar, value: .Some(new)).then(STM<A>.pure(old))
		}
	}
}

public func isEmptyTMVar<A>(v : TMVar<A>) -> STM<Bool> {
	return readTVar(v.tvar).flatMap { m in
		switch m {
		case .None:
			return STM<Bool>.pure(true)
		case .Some(_):
			return STM<Bool>.pure(false)
		}
	}
}


