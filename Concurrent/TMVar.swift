//
//  TMVar.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// TVars (Transactional MVars) are MVars whose operations are performed in the STM Monad.
public struct TMVar<A> {
	let tvar : TVar<Optional<A>>

	init(_ tvar : TVar<Optional<A>>) {
		self.tvar = tvar
	}
	
	public init() {
		self.init(TVar(.None))
	}

	public init(initial : A) {
		let t : TVar<Optional<A>> = TVar(.Some(initial))
		self.init(t)
	}

	/// Returns an operation to get the contents of the receiver.
	///
	/// If the TMVar is empty, this will block retrying the operation until a value is put into the 
	/// TMVar.  If the TMVar is full, the operation returns the value and the TMVar is emptied.
	public func take() -> STM<A> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .None:
				return retry()
			case .Some(let a):
				return do_ { () -> A in
					self.tvar.write(.None)
					return a
				}
			}
		}
	}

	/// Returns an operation to atomically read the contents of the receiver.
	///
	/// If the TMVar is currently empty, the operation will block retrying until a value is put into
	/// it.  If the TMVar is full, the operation returns the contents of the receiver, but it
	/// remains full.
	public func read() -> STM<A> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .None:
				return retry()
			case .Some(let a):
				return do_ { () in a }
			}
		}
	}

	/// Returns an operation to put a value into the receiver.
	///
	/// If the TMVar is currently full, the operation will block retrying until it becomes empty 
	/// again.
	public func put(x : A) -> STM<()> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .Some(_):
				return retry()
			case .None:
				return self.tvar.write(.Some(x))
			}
		}
	}

	/// Returns an operation that attempts to return the contents of the receiver without blocking.
	///
	/// If the TMVar is empty, the operation will immediately return a .None.  If the TMVar is full,
	/// the operation returns its contents and the TMVar is emptied.
	public func tryTake() -> STM<Optional<A>> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .None:
				return do_ { () in .None }
			case .Some(let a):
				return do_ { () -> Optional<A> in
					self.tvar.write(.None)
					return .Some(a)
				}
			}
		}
	}

	/// Returns an operation that attempts to read the contents of the receiver without blocking.
	///
	/// If the TMVar is empty, the operation returns .None.  If the TMVar is full, the operation 
	/// wraps the value in .Some and returns.
	public func tryRead() -> STM<Optional<A>> {
		return self.tvar.read()
	}

	/// Returns an operation that attempts to put a value into the receiver without blocking.
	///
	/// If the TMVar is empty, the operation immediately returns true.  If the TMVar is full, 
	/// nothing occurs and false is returned.
	public func tryPut(x : A) -> STM<Bool> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .Some(_):
				return do_ { () in false }
			case .None:
				return do_ { () -> Bool in
					!self.tvar.write(.Some(x))
					return true
				}
			}
		}
	}

	/// Returns an operation that takes a value from the receiver, puts a given new value in the 
	/// receiver, then returns the receiver's old value.
	public func swap(x : A) -> STM<A> {
		return do_ {
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .None:
				return retry()
			case .Some(let a):
				return do_ { () -> A in
					!self.tvar.write(.Some(x))
					return a
				}
			}
		}
	}

	/// Returns an operation that checks whether the receiver is empty.
	///
	/// This operation is just a snapshot of the state of the TMVar at that point in time.  
	/// In heavily concurrent computations, this may change out from under you without warning, or 
	/// even by the time it can be acted on.  It is better to use one of the direct actions above.
	public func isEmpty() -> STM<Bool> {
		return do_ { () -> Bool in
			let m : Optional<A> = !self.tvar.read()
			switch m {
			case .None:
				return true
			case .Some(_):
				return false
			}
		}
	}

}

public func newTMVar<A>(x : A) -> STM<TMVar<A>> {
	return do_ { () -> TMVar<A> in
		let t : TVar<Optional<A>> = !newTVar(Optional.Some(x))
		return TMVar(t)
	}
}

public func newEmptyTMVar<A>() -> STM<TMVar<A>> {
	return do_ { () -> TMVar<A> in
		let t : TVar<Optional<A>>! = !newTVar(.None)
		return TMVar(t)
	}
}

