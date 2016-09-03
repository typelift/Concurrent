//
//  STM.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//
// This file is a fairly clean port of FSharpX's implementation 
// ~(https://github.com/fsprojects/FSharpx.Extras/)

/// A monad supporting atomic memory transactions.
public struct STM<T> {
	/// Perform a series of STM actions atomically.
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
	/// has read from has been udpated.
	public static func retry() -> STM<T>  {
		return STM { trans in
			return try trans.retry()
		}
	}
	
	/// Compose two alternative STM actions (GHC only). 
	///
	/// If the first action completes without retrying then it forms the result
	/// of the `orElse`. Otherwise, if the first action retries, then the second
	/// action is tried in its place. If both actions retry then the `orElse` as
	/// a whole retries.
	public func orElse(b : STM<T>) -> STM<T>  {
		return STM { trans in
			do {
				return try trans.orElse(self.unSTM, q: b.unSTM)
			} catch _ {
				fatalError()
			}
		}
	}
	
	private let unSTM : TLog throws -> T
	
	internal init(_ unSTM : TLog throws -> T) {
		self.unSTM = unSTM
	}
}

extension STM /*: Functor*/ {
	/// Apply a function to the result of an STM transaction.
	public func fmap<B>(f : T -> B) -> STM<B> {
		return self.flatMap { x in STM<B>.pure(f(x)) }
	}
}

extension STM /*: Pointed*/ {
	/// Lift a value into a trivial STM transaction.
	public static func pure<T>(x : T) -> STM<T> {
		return STM<T> { _ in
			return x
		}
	}
}

extension STM /*: Applicative*/ {
	/// Atomically apply a function to the result of an STM transaction.
	public func ap<B>(fab : STM<T -> B>) -> STM<B> {
		return fab.flatMap(self.fmap)
	}
}

extension STM /*: Monad*/ {
	/// Atomically apply a function to the result of an STM transaction that
	/// yields a continuation transaction to be executed later.
	///
	/// This function can be used to implement other atomic primitives.
	public func flatMap<B>(rest : T -> STM<B>) -> STM<B> {
		return STM<B> { trans in
			return try rest(try! self.unSTM(trans)).unSTM(trans)
		}
	}

	/// Atomically execute the first action then execute the second action
	/// immediately after.
	public func then<B>(then : STM<B>) -> STM<B> {
		return self.flatMap { _ in
			return then
		}
	}
}

internal final class Entry<T> {
	let oldValue : TVarType<T>
	var location : TVar<T>
	var _newValue : TVarType<T>
	let hasOldValue : Bool
	
	var isValid : Bool {
		return !hasOldValue || location.value == self.oldValue
	}

	convenience init(_ location : TVar<T>) {
		self.init(location, location.value, false)
	}

	convenience init(_ location : TVar<T>, _ value : TVarType<T>) {
		self.init(location, value, true)
	}

	init(_ location : TVar<T>, _ value : TVarType<T>, _ valid : Bool) {
		self.location = location
		self.oldValue = location.value
		self._newValue = value
		self.hasOldValue = valid
	}
	
	private init(_ oldValue : TVarType<T>, _ location : TVar<T>, _ value : TVarType<T>, _ valid : Bool) {
		self.location = location
		self.oldValue = oldValue
		self._newValue = value
		self.hasOldValue = valid
	}

	func mergeNested(e : Entry<T>) {
		e._newValue = self._newValue
	}

	func commit() {
		self.location.value = self._newValue
	}
	
	// HACK: bridge-all-the-things-to-Any makes this a legal transformation.
	var upCast : Entry<Any> {
		return Entry<Any>(self.oldValue.upCast, self.location.upCast, self._newValue.upCast, self.hasOldValue)
	}
}

private enum STMError : ErrorType {
	case RetryException
	case CommitFailedException
	case InvalidOperationException
}

private var _current : Any? = nil

/// A transactional memory log
internal final class TLog {
	lazy var locker = UnsafeMutablePointer<pthread_mutex_t>.alloc(sizeof(pthread_mutex_t))
	lazy var cond = UnsafeMutablePointer<pthread_cond_t>.alloc(sizeof(pthread_mutex_t))

	let outer : TLog?
	var log : Dictionary<TVar<Any>, Entry<Any>> = [:]
	
	var isValid : Bool {
		return self.log.values.reduce(true, combine: { $0 && $1.isValid }) && (outer == nil || outer!.isValid)
	}

	convenience init() {
		self.init(outer: nil)
	}

	init(outer : TLog?) {
		self.outer = outer
		pthread_mutex_init(self.locker, nil)
		pthread_cond_init(self.cond, nil)
	}

	static func newTVar<T>(value : T) -> TVar<T> {
		return TVar(value)
	}

	func readTVar<T>(location : TVar<T>) -> T {
		if let entry = self.log[location.upCast] {
			return entry._newValue.retrieve as! T
		} else if let out = outer {
			return out.readTVar(location)
		} else {
			let entry = Entry(location)
			log[location.upCast] = entry.upCast
			return entry.oldValue.retrieve
		}
	}

	// FIXME: Replace with with an MVar.
	func lock() {
		pthread_mutex_lock(self.locker)
	}

	func block() {
		guard pthread_mutex_trylock(self.locker) != 0 else {
			fatalError("thread must be locked in order to wait")
		}
		pthread_mutex_unlock(self.locker)
		pthread_cond_wait(self.cond, self.locker)
	}

	func signal() {
		pthread_cond_broadcast(self.cond)
	}

	func unlock() {
		pthread_mutex_unlock(self.locker)
	}

	func writeTVar<T>(location : TVar<T>, value : TVarType<T>) {
		if let entry = self.log[location.upCast] {
			entry._newValue = value.upCast
		} else {
			let entry = Entry(location)
			log[location.upCast] = entry.upCast
		}
	}

	func mergeNested() {
		if let out = self.outer {
			for innerEntry in log.values {
				if let outerE = out.log[innerEntry.location] {
					innerEntry.mergeNested(outerE)
				} else {
					out.log[innerEntry.location] = innerEntry
				}
			}
		}
	}

	func commit() throws {
		if let _ = self.outer {
			throw STMError.InvalidOperationException
		} else {
			log.values.forEach {
				$0.commit()
			}
		}
	}

	static func atomically<T>(p : TLog throws -> T) throws -> T {
		let trans = TLog()
		guard _current == nil else {
			fatalError("Transaction already running on current thread")
		}
		_current = trans
		defer {
			_current = nil
		}
		while true {
			do {
				let result = try p(trans)
				trans.lock()
				let isValid = trans.isValid
				if isValid {
					try trans.commit()
					trans.signal()
				}
				trans.unlock()
				if isValid {
					return result
				} else {
					trans.log.removeAll()
					continue
				}
			} catch STMError.RetryException {
				trans.lock()
				let isValid = trans.isValid
				if isValid {
					while trans.isValid {
						trans.block()
					}
					trans.unlock()
				} else {
					trans.unlock()
				}
				continue
			} catch STMError.CommitFailedException {
				throw STMError.CommitFailedException
			} catch let l {
				trans.lock()
				let isValid = trans.isValid
				trans.unlock()
				if isValid {
					throw l
				} else {
					continue
				}
			}
		}
	}

	func retry<T>() throws -> T {
		throw STMError.RetryException
	}

	func orElse<T>(p : TLog throws -> T, q : TLog throws -> T) throws -> T {
		let first = TLog(outer: self)
		do {
			let result = try p(first)
			first.lock()
			let isValid = first.isValid
			first.unlock()
			if isValid {
				first.mergeNested()
				return result
			} else {
				throw STMError.CommitFailedException
			}
		} catch STMError.RetryException {
			let second = TLog(outer: self)
			do {
				let result = try q(second)
				first.lock()
				let isValid = second.isValid
				first.unlock()
				if isValid {
					second.mergeNested()
					return result
				} else {
					throw STMError.CommitFailedException
				}
			} catch STMError.RetryException {
				self.lock()
				let isValid = first.isValid && second.isValid && self.isValid
				self.unlock()
				if isValid {
					first.mergeNested()
					second.mergeNested()
					throw STMError.RetryException
				} else {
					throw STMError.CommitFailedException
				}
			} catch STMError.CommitFailedException {
				throw STMError.CommitFailedException
			} catch let l {
				second.lock()
				let isValid = second.isValid
				second.unlock()
				if isValid {
					second.mergeNested()
					throw l
				} else {
					throw STMError.CommitFailedException
				}
			}
		} catch STMError.CommitFailedException {
			throw STMError.CommitFailedException
		} catch let l {
			first.lock()
			let isValid = first.isValid
			first.unlock()
			if isValid {
				first.mergeNested()
				throw l
			} else {
				throw STMError.CommitFailedException
			}
		}

	}
}

