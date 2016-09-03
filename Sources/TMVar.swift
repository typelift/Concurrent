//
//  TMVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

/// A TMVar is a synchronising variable, used for communication between 
/// concurrent threads. It can be thought of as a box, which may be empty.
///
/// A TMVar functions much like an MVar but uses an STM to manage the 
/// transactions it can perform.
///
/// - Reading an empty `TMVar` causes the reader to block.
///
/// - Reading a filled 'TMVar' empties it, returns a value, and potentially wakes up a blocked writer.
///
/// - Writing to an empty 'TMVar' fills it with a value and potentially wakes up a blocked reader.
///
/// - Writing to a filled 'TMVar' causes the writer to block.
public struct TMVar<A> {
	let tvar : TVar<Optional<A>>

	/// Creates a new empty TMVar.
	public init() {
		self.tvar = TVar<Optional<A>>(nil)
	}

	/// Creates a new TMVar containing the supplied value.
	public init(initial : A) {
		self.tvar = TVar<Optional<A>>(.Some(initial))
	}
	
	/// Uses an STM transaction to atomically return the contents of the receiver.
	///
	/// If the TMVar is empty, this will block until a value is put into the TMVar.  
	/// If the TMVar is full, the value is returned and the TMVar is emptied.	
	public func take() -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return STM.retry()
			case .Some(let x):
				return self.tvar.write(.None).then(STM<A>.pure(x))
			}
		}
	}
	
	/// Uses an STM transaction to atomically attempt to return the contents of the receiver without blocking.
	///
	/// If the TMVar is empty, this will immediately return .None. If the TMVar is full, the value is 
	/// returned and the TMVar is emptied.
	public func tryTake() -> STM<Optional<A>> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return STM<Optional<A>>.pure(.None)
			case .Some(let x):
				return self.tvar.write(.None).then(STM<A>.pure(.Some(x)))
			}
		}
	}
	
	/// Uses an STM transaction to atomically put a value into the receiver.
	///
	/// If the TMVar is currently full, the function will block until it becomes empty again.
	public func put(val : A) -> STM<()> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return self.tvar.write(.Some(val))
			case .Some(_):
				return STM.retry()
			}
		}
	}
	
	/// Uses an STM transaction to atomically attempt to put a value into the receiver without blocking.
	///
	/// If the TMVar is empty, this will immediately returns true.  If the TMVar is full, nothing 
	/// occurs and false is returned.
	public func tryPut(val : A) -> STM<Bool> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return self.tvar.write(.Some(val)).then(STM<Bool>.pure(true))
			case .Some(_):
				return STM<Bool>.pure(false)
			}
		}
	}

	/// Uses an STM transaction to atomically read the contents of the receiver.
	///
	/// If the TMVar is currently empty, this will block until a value is put into it.  If the TMVar 
	/// is full, the value is returned, but the TMVar remains full.
	public func read() -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return STM.retry()
			case .Some(let x):
				return STM<A>.pure(x)
			}
		}
	}
	
	/// Uses an STM transaction to atomically attempt to read the contents of the receiver without blocking.
	///
	/// If the TMVar is empty, this function returns .None.  If the TMVar is full, this function wraps
	/// the value in .Some and returns.
	public func tryRead() -> STM<Optional<A>> {
		return self.tvar.read()
	}

	/// Uses an STM transaction to atomically, take a value from the receiver, put a given new value in the receiver, then 
	/// return the receiver's old value.
	public func swap(new : A) -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return STM.retry()
			case .Some(let old):
				return self.tvar.write(.Some(new)).then(STM<A>.pure(old))
			}
		}
	}
	
	/// Uses an STM transaction to atomically return whether the receiver is empty.
	public func isEmpty() -> STM<Bool> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .None:
				return STM<Bool>.pure(true)
			case .Some(_):
				return STM<Bool>.pure(false)
			}
		}
	}
}


