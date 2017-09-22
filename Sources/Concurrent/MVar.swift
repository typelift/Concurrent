//
//  `MVar`.swift
//  Basis
//
//  Created by Robert Widmann on 9/12/14.
//  Copyright © 2014-2016 TypeLift. All rights reserved.
//

/// `MVar`s (literally "Mutable Variables") are mutable references that are
/// either empty or contain a value of type `A`. In this way, they are a form of
/// synchronization primitive that can be used to make threads wait on a value
/// before proceeding with a computation.
///
/// - Reading an empty `MVar` causes the reader to block.
///
/// - Reading a filled 'MVar' empties it, returns a value, and potentially wakes
///   up a blocked writer.
///
/// - Writing to an empty 'MVar' fills it with a value and potentially wakes up
///   a blocked reader.
///
/// - Writing to a filled 'MVar' causes the writer to block.
public final class MVar<A> {
	private var val : A?
	private let lock : UnsafeMutablePointer<pthread_mutex_t>
	private let takeCond : UnsafeMutablePointer<pthread_cond_t>
	private let putCond : UnsafeMutablePointer<pthread_cond_t>

	/// Creates a new empty `MVar`.
	public init() {
		self.val = .none
		self.lock = UnsafeMutablePointer.allocate(capacity: MemoryLayout<pthread_mutex_t>.size)
		self.takeCond = UnsafeMutablePointer.allocate(capacity: MemoryLayout<pthread_cond_t>.size)
		self.putCond = UnsafeMutablePointer.allocate(capacity: MemoryLayout<pthread_cond_t>.size)

		pthread_mutex_init(self.lock, nil)
		pthread_cond_init(self.takeCond, nil)
		pthread_cond_init(self.putCond, nil)
	}

	/// Creates a new `MVar` containing the supplied value.
	public convenience init(initial : A) {
		self.init()
		self.put(initial)
	}

	/// Returns the contents of the `MVar`.
	///
	/// If the `MVar` is empty, this will block until a value is put into the
	/// `MVar`.  If the `MVar` is full, the value is returned and the `MVar` is
	/// emptied.
	public func take() -> A {
		pthread_mutex_lock(self.lock)
		while self.val == nil {
			pthread_cond_wait(self.takeCond, self.lock)
		}
		let value = self.val!
		self.val = .none
		pthread_cond_signal(self.putCond)
		pthread_mutex_unlock(self.lock)
		return value
	}

	/// Atomically reads the contents of the `MVar`.
	///
	/// If the `MVar` is currently empty, this will block until a value is put
	/// into it.  If the `MVar` is full, the value is returned, but the `MVar`
	/// remains full.
	public func read() -> A {
		pthread_mutex_lock(self.lock)
		while self.val == nil {
			pthread_cond_wait(self.takeCond, self.lock)
		}
		let value = self.val!
		pthread_cond_signal(self.putCond)
		pthread_mutex_unlock(self.lock)
		return value
	}

	/// Puts a value into the `MVar`.
	///
	/// If the `MVar` is currently full, the function will block until it becomes
	/// empty again.
	public func put(_ x : A) {
		pthread_mutex_lock(self.lock)
		while self.val != nil {
			pthread_cond_wait(self.putCond, self.lock)
		}
		self.val = x
		pthread_cond_signal(self.takeCond)
		pthread_mutex_unlock(self.lock)
		return ()
	}

	/// Attempts to return the contents of the `MVar` without blocking.
	///
	/// If the `MVar` is empty, this will immediately return .none. If the `MVar`
	/// is full, the value is returned and the `MVar` is emptied.
	public func tryTake() -> Optional<A> {
		pthread_mutex_lock(self.lock)
		if self.val == nil {
			return .none
		}
		let value = self.val!
		self.val = .none
		pthread_cond_signal(self.putCond)
		pthread_mutex_unlock(self.lock)
		return value
	}

	/// Attempts to put a value into the `MVar` without blocking.
	///
	/// If the `MVar` is empty, this will immediately returns true.  If the `MVar`
	/// is full, nothing occurs and false is returned.
	public func tryPut(_ x : A) -> Bool {
		pthread_mutex_lock(self.lock)
		if self.val != nil {
			return false
		}
		self.val = x
		pthread_cond_signal(self.takeCond)
		pthread_mutex_unlock(self.lock)
		return true
	}

	/// Attempts to read the contents of the `MVar` without blocking.
	///
	/// If the `MVar` is empty, this function returns .none.  If the `MVar` is full,
	/// this function wraps the value in .some and returns.
	public func tryRead() -> Optional<A> {
		pthread_mutex_lock(self.lock)
		if self.val == nil {
			return .none
		}
		let value = self.val!
		pthread_cond_signal(self.putCond)
		pthread_mutex_unlock(self.lock)
		return value
	}

	/// Returns whether the `MVar` is empty.
	///
	/// This function is just a snapshot of the state of the `MVar` at that point in
	/// time.  In heavily concurrent computations, this may change out from under
	/// you without warning, or even by the time it can be acted on.  It is better
	/// to use one of the direct actions above.
	public var isEmpty : Bool {
		return (self.val == nil)
	}

	/// Atomically, take a value from the `MVar`, put a given new value in the
	/// `MVar`, then return the `MVar`'s old value.
	public func swap(_ x : A) -> A {
		let old = self.take()
		self.put(x)
		return old
	}

	/// An exception-safe way of using the value in the `MVar` in a computation.
	///
	/// On exception, the value previously stored in the `MVar` is put back into it
	/// and the exception is rethrown.
	public func withMVar<B>(_ f : (A) throws -> B) throws -> B {
		let a = self.take()
		do {
			let b = try f(a)
			self.put(a)
			return b
		} catch let e {
			self.put(a)
			throw e
		}
	}

	/// An exception-safe way to modify the contents of the `MVar`.  On
	/// successful modification, the new value of the `MVar` is returned.
	///
	/// On exception, the value previously stored in the `MVar` is put back into it.
	public func modify<B>(_ f : (A) throws -> (A, B)) throws -> B {
		let a = self.take()
		do {
			let t = try f(a)
			self.put(t.0)
			return t.1
		} catch let e {
			self.put(a)
			throw e
		}
	}

	/// An exception-safe way to modify the contents of the `MVar`.
	///
	/// On exception, the value previously stored in the `MVar` is put back into it.
	public func modify_(_ f : (A) throws -> A) {
		let a = self.take()
		do {
			let a1 = try f(a)
			self.put(a1)
		} catch _ {
			self.put(a)
		}
	}

	deinit {
		self.lock.deinitialize()
		self.takeCond.deinitialize()
		self.putCond.deinitialize()
	}
}

/// Equality over `MVar`s.
///
/// Two `MVar`s are equal if they both contain no value or if the values they
/// contain are equal.  This particular definition of equality is time-dependent
/// and fundamentally unstable.  By the time two `MVar`s can be read and
/// compared for equality, one may have already lost its value, or may have had
/// its value swapped out from under you.  It is better to `take()` the values
/// yourself if you need a stricter equality.
public func ==<A : Equatable>(lhs : `MVar`<A>, rhs : `MVar`<A>) -> Bool {
	if lhs.isEmpty && !rhs.isEmpty {
		return true
	}
	if lhs.isEmpty != rhs.isEmpty {
		return false
	}
	return lhs.read() == rhs.read()
}

#if os(Linux)
	import Glibc
#else
	import Darwin
#endif

