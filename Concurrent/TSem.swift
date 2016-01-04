//
//  TSem.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TSem {
	let tvar : TVar<Int>

	init(_ tvar : TVar<Int>) {
		self.tvar = tvar
	}
}

public func newTSem(i : Int) -> STM<TSem> {
	let v : TVar<Int> = TVar(i)
	return STM<TSem>.pure(TSem(v))
}

public func waitTSem(sem : TSem) -> STM<()> {
	return readTVar(sem.tvar).flatMap { i in
		if (i <= 0) {
			do {
				return try retry()
			} catch _ {
				fatalError()
			}
		}
		return writeTVar(sem.tvar, value: i.predecessor())
	}
}

public func signalTSem(sem : TSem) -> STM<()> {
	return readTVar(sem.tvar).flatMap { i in
		return writeTVar(sem.tvar, value: i.successor())
	}
}