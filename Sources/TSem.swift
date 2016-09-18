//
//  TSem.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

/// `TSem is a transactional semaphore. It holds a certain number of units, and 
/// units may be acquired or released by `wait()` and `signal()` respectively. 
/// When the TSem is empty, `wait()` blocks.
///
/// Note that `TSem` has no concept of fairness, and there is no guarantee that
/// threads blocked in `wait()` will be unblocked in the same order; in fact 
/// they will all be unblocked at the same time and will fight over the TSem. 
/// Hence TSem is not suitable if you expect there to be a high number of 
/// threads contending for the resource. However, like other STM abstractions, 
/// TSem is composable.
public struct TSem {
	let tvar : TVar<Int>

	private init(_ tvar : TVar<Int>) {
		self.tvar = tvar
	}
	
	/// Uses an STM transaction to atomically create and initialize a new
	/// transactional semaphore.
	public func create(_ i : Int) -> STM<TSem> {
		let v : TVar<Int> = TVar(i)
		return STM<TSem>.pure(TSem(v))
	}
	
	/// Uses an STM transaction to atomically decrement the value of the
	/// semaphore by 1 and waits for a unit to become available.
	public func wait() -> STM<()> {
		return self.tvar.read().flatMap { i in
			if (i <= 0) {
				return STM.retry()
			}
			return self.tvar.write((i - 1))
		}
	}
	
	/// Uses an STM transaction to atomically increment the value of the 
	/// semaphore by 1 and signals that a unit has become available.
	public func signal() -> STM<()> {
		return self.tvar.read().flatMap { i in
			return self.tvar.write((i + 1))
		}
	}
}

