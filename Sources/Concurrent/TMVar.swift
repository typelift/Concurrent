//
//  TMVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015-2016 TypeLift. All rights reserved.
//

/// A `TMVar` is a synchronising variable, used for communication between
/// concurrent threads. It can be thought of as a box, which may be empty.
///
/// A TMVar functions much like an `MVar` but uses an `STM` to manage the
/// transactions it can perform.
///
/// - Reading an empty `TMVar` causes the reader to block.
///
/// - Reading a filled `TMVar` empties it, returns a value, and potentially
///   wakes up a blocked writer.
///
/// - Writing to an empty `TMVar` fills it with a value and potentially wakes up
///   a blocked reader.
///
/// - Writing to a filled `TMVar` causes the writer to block.
public struct TMVar<A> {
	let tvar : TVar<Optional<A>>

	/// Creates a new empty TMVar.
	public init() {
		self.tvar = TVar<Optional<A>>(nil)
	}

	/// Creates a new TMVar containing the supplied value.
	public init(initial : A) {
		self.tvar = TVar<Optional<A>>(.some(initial))
	}

	/// Uses an STM transaction to atomically return the contents of the `TMVar`.
	///
	/// If the `TMVar` is empty, this will block until a value is put into the
	/// `TMVar`.  If the `TMVar` is full, the value is returned and the TMVar is
	/// emptied.
	public func take() -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return STM.retry()
			case .some(let x):
				return self.tvar.write(.none).then(STM<A>.pure(x))
			}
		}
	}

	/// Uses an STM transaction to atomically attempt to return the contents of
	/// the `TMVar` without blocking.
	///
	/// If the `TMVar` is empty, this will immediately return `.none`. If the
	/// `TMVar` is full, the value is returned and the `TMVar` is emptied.
	public func tryTake() -> STM<Optional<A>> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return STM<Optional<A>>.pure(.none)
			case .some(let x):
				return self.tvar.write(.none).then(STM<A>.pure(.some(x)))
			}
		}
	}

	/// Uses an STM transaction to atomically put a value into the `TMVar`.
	///
	/// If the `TMVar` is currently full, the function will block until it
	/// becomes empty again.
	public func put(_ val : A) -> STM<()> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return self.tvar.write(.some(val))
			case .some(_):
				return STM.retry()
			}
		}
	}

	/// Uses an STM transaction to atomically attempt to put a value into the
	/// `TMVar` without blocking.
	///
	/// If the `TMVar` is empty, this will immediately returns `true`.  If the
	/// `TMVar` is full, nothing occurs and `false` is returned.
	public func tryPut(_ val : A) -> STM<Bool> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return self.tvar.write(.some(val)).then(STM<Bool>.pure(true))
			case .some(_):
				return STM<Bool>.pure(false)
			}
		}
	}

	/// Uses an STM transaction to atomically read the contents of the `TMVar`.
	///
	/// If the `TMVar` is currently empty, this will block until a value is put
	/// into it.  If the `TMVar` is full, the value is returned, but the `TMVar`
	/// remains full.
	public func read() -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return STM.retry()
			case .some(let x):
				return STM<A>.pure(x)
			}
		}
	}

	/// Uses an STM transaction to atomically attempt to read the contents of
	/// the `TMVar` without blocking.
	///
	/// If the `TMVar` is empty, this function returns `.none`.  If the `TMVar`
	/// is full, this function wraps the value in `.some` and returns.
	public func tryRead() -> STM<Optional<A>> {
		return self.tvar.read()
	}

	/// Uses an STM transaction to atomically, take a value from the `TMVar`,
	/// put a given new value in the `TMVar`, then return the `TMVar`'s old
	/// value.
	public func swap(_ new : A) -> STM<A> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return STM.retry()
			case .some(let old):
				return self.tvar.write(.some(new)).then(STM<A>.pure(old))
			}
		}
	}

	/// Uses an STM transaction to atomically return whether the `TMVar` is
	/// empty.
	public func isEmpty() -> STM<Bool> {
		return self.tvar.read().flatMap { m in
			switch m {
			case .none:
				return STM<Bool>.pure(true)
			case .some(_):
				return STM<Bool>.pure(false)
			}
		}
	}
}


