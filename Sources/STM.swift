//
//  STM.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015-2016 TypeLift. All rights reserved.
//

/// A monad supporting atomic memory transactions.
///
/// `STM` is the interface to the atomic memory transaction manager and subsumes
/// the use of fine-grained locking for shared mutable memory entirely.  This
/// implementation guarantees consistency with respect to the effects of all
/// executing transactions, atomicity with respect to each individual operation,
/// and isolation of effects down to each subpart of a transaction.  `STM` is 
/// also exception-safe.  Any transactions that throw exceptions will be rolled 
/// back and their effects elided.
///
/// The main use for `STM` is interacting with transactional variables 
/// (`TVar`s).  By design, this is because the type system prevents you reading 
/// or writing a `TVar` outside an atomic `STM` block.
///
/// `STM` also exposes operations to allow blocking and choice, `retry()` and
/// `orElse` respectively.
///
/// Note that it is possible to deadlock under this scheme if a transaction
/// `retry()`s without another transaction mutating its memory.  It is also
/// highly discouraged that side effects be executed inside of transactions.  It
/// makes a transaction fundamentally non-atomic to do so, and the results of
/// committing such a transaction are undefined.
///
/// `STM` actions can be composed together with `flatMap` or `then`.
///
/// *"The free lunch is over."*
public struct STM<T> {
	/// Perform a series of STM actions atomically.
	///
	/// A call to `atomically()` guarantees the following postconditions:
	///
	/// - Atomicity: the effects of an atomic act become visible to another
	///   thread all at once.
	/// - Isolation: during the call, the action is completely unaffected by 
	///   other threads.  It is as if the action takes a snapshot of the state 
	///   of the world when it begins running, and then executes against that 
	///   snapshot.
	public func atomically() -> T {
		do {
			return try TLog.atomically { try self.unSTM($0) }
		} catch _ {
			fatalError("Retry should have been caught internally.")
		}
	}

	/// Retry execution of the current memory transaction because it has seen
	/// values in `TVar`s which mean that it should not continue.
	///
	/// The implementation may block the thread until one of the `TVar`s that it
	/// has read from has been updated.
	public static func retry() -> STM<T>  {
		return STM { trans in
			return try trans.retry()
		}
	}

	/// Compose two alternative STM actions.
	///
	/// If the first action completes without retrying then it forms the result
	/// of the `orElse`. Otherwise, if the first action retries, then the second
	/// action is tried in its place. If both actions retry then the `orElse` as
	/// a whole retries.
	public func orElse(_ b : STM<T>) throws -> STM<T>  {
		return STM { trans in
			return try trans.orElse(self.unSTM, q: b.unSTM)
		}
	}

	fileprivate let unSTM : (TLog) throws -> T

	internal init(_ unSTM : @escaping (TLog) throws -> T) {
		self.unSTM = unSTM
	}
}

extension STM /*: Functor*/ {
	/// Apply a function to the result of an STM transaction.
	public func fmap<B>(_ f : @escaping (T) throws -> B) -> STM<B> {
		return self.flatMap { x in STM<B>.pure(try f(x)) }
	}
}

extension STM /*: Pointed*/ {
	/// Lift a value into a trivial STM transaction.
	public static func pure<T>(_ x : T) -> STM<T> {
		return STM<T> { _ in
			return x
		}
	}
}

extension STM /*: Applicative*/ {
	/// Atomically apply a function to the result of an STM transaction.
	public func ap<B>(_ fab : STM<(T) throws -> B>) -> STM<B> {
		return fab.flatMap(self.fmap)
	}
}

extension STM /*: Monad*/ {
	/// Atomically apply a function to the result of an STM transaction that
	/// yields a continuation transaction to be executed later.
	///
	/// This function can be used to implement other atomic primitives.
	public func flatMap<B>(_ rest : @escaping (T) throws -> STM<B>) -> STM<B> {
		return STM<B> { trans in
			return try rest(try self.unSTM(trans)).unSTM(trans)
		}
	}

	/// Atomically execute the first action then execute the second action
	/// immediately after.
	public func then<B>(_ then : STM<B>) -> STM<B> {
		return self.flatMap { _ in
			return then
		}
	}
}
