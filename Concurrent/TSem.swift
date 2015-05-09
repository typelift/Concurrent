//
//  TSem.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// `TSem` is a transactional semaphore, a counting semaphore whose units are acquired and released
/// with operations inside the STM Monad.
public struct TSem {
	let tvar : TVar<Int>

	init(_ tvar : TVar<Int>) {
		self.tvar = tvar
	}

	/// Returns an operation that decrements the value of the semaphore by 1 and waits for a unit to
	/// become available.
	public func wait() -> STM<()> {
		let i : Int = !self.tvar.read()
		return (i <= 0) ? retry() : self.tvar.write(i - 1)
	}

	/// Returns an operation that increments the value of the semaphore by 1 and signals that a unit
	/// has become available.
	public func signal() -> STM<()> {
		return self.tvar.modify(+1)
	}
}

public func newTSem(i : Int) -> STM<TSem> {
	return do_ { () -> TSem in
		let v : TVar<Int> = !newTVar(i)
		return TSem(v)
	}
}

