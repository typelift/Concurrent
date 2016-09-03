//
//  STM.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//
// This file is a fairly clean port of FSharpX's implementation 
// ~(https://github.com/fsprojects/FSharpx.Extras/)


public struct STM<T> {
	public func atomically() -> T {
		do {
			return try TLog.atomically { try self.unSTM($0) }
		} catch _ {
			fatalError()
		}
	}

	private let unSTM : TLog throws -> T
}

extension STM /*: Functor*/ {
	public func fmap<B>(f : T -> B) -> STM<B> {
		return self.flatMap { x in STM<B>.pure(f(x)) }
	}
}

extension STM /*: Pointed*/ {
	public static func pure<T>(x : T) -> STM<T> {
		return STM<T> { _ in
			return x
		}
	}
}

extension STM /*: Applicative*/ {
	public func ap<B>(fab : STM<T -> B>) -> STM<B> {
		return fab.flatMap(self.fmap)
	}
}

extension STM /*: Monad*/ {
	public func flatMap<B>(rest : T -> STM<B>) -> STM<B> {
		return STM<B> { trans in
			return try rest(try! self.unSTM(trans)).unSTM(trans)
		}
	}

	public func then<B>(then : STM<B>) -> STM<B> {
		return self.flatMap { _ in
			return then
		}
	}
}

public func readTVar<T>(ref : TVar<T>) -> STM<T>  {
	return STM { trans in
		return trans.readTVar(ref)
	}
}

public func writeTVar<T : Equatable>(ref : TVar<T>, value : T) -> STM<()>  {
	return STM<T> { (trans : TLog) in
		trans.writeTVar(ref, value: PreEquatable(t: { value }))
		return value
	}.then(STM<()>.pure(()))
}

public func writeTVar<T : AnyObject>(ref : TVar<T>, value : T) -> STM<()>  {
	return STM<T> { (trans : TLog) in
		trans.writeTVar(ref, value: UnderlyingRef(t: { value }))
		return value
	}.then(STM<()>.pure(()))
}

public func writeTVar<T : Any>(ref : TVar<T>, value : T) -> STM<()>  {
	return STM<T> { (trans : TLog) in
		trans.writeTVar(ref, value: Ref(t: { value }))
		return value
	}.then(STM<()>.pure(()))
}

public func retry<T>() throws -> STM<T>  {
	return STM { trans in
		return try trans.retry()
	}
}

public func orElse<T>(a : STM<T>, b : STM<T>) -> STM<T>  {
	return STM { trans in
		do {
			return try trans.orElse(a.unSTM, q: b.unSTM)
		} catch _ {
			fatalError()
		}
	}
}

private final class Entry<T> {
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
private final class TLog {
	lazy var locker = UnsafeMutablePointer<pthread_mutex_t>.alloc(sizeof(pthread_mutex_t))
	lazy var cond = UnsafeMutablePointer<pthread_cond_t>.alloc(sizeof(pthread_mutex_t))

	let outer : TLog?
	var log : Dictionary<TVar<Any>, Entry<Any>> = Dictionary()
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

	func lock() {
		pthread_mutex_lock(self.locker)
	}

	func block() {
		print("Block!")
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

