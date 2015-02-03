//
//  TSem.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftx

public final class TSem : K0 {
	let tvar : TVar<Int>

	init(_ tvar : TVar<Int>) {
		self.tvar = tvar
	}
}

public func newTSem(i : Int) -> STM<TSem> {
	return do_ { () -> TSem in
		let v : TVar<Int> = !newTVar(i)
		return TSem(v)
	}
}

public func waitTSem(sem : TSem) -> STM<()> {
	let i : Int = !readTVar(sem.tvar)
	return (i <= 0) ? retry() : writeTVar(sem.tvar)(x: i - 1)
}

public func signalTSem(sem : TSem) -> STM<()> {
	let i : Int = !readTVar(sem.tvar)
	return writeTVar(sem.tvar)(x: i + 1)
}
