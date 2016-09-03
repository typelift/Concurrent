//
//  Transactions.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/25/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

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
	
	fileprivate init(_ oldValue : TVarType<T>, _ location : TVar<T>, _ value : TVarType<T>, _ valid : Bool) {
		self.location = location
		self.oldValue = oldValue
		self._newValue = value
		self.hasOldValue = valid
	}
	
	func mergeNested(_ e : Entry<T>) {
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

private enum STMError : Error {
	case retryException
	case commitFailedException
	case invalidOperationException
}

private var _current : Any? = nil

/// A transactional memory log
internal final class TLog {
	lazy var locker = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: MemoryLayout<pthread_mutex_t>.size)
	lazy var cond = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: MemoryLayout<pthread_mutex_t>.size)
	
	let outer : TLog?
	var log : Dictionary<TVar<Any>, Entry<Any>> = [:]
	
	var isValid : Bool {
		return self.log.values.reduce(true, { $0 && $1.isValid }) && (outer == nil || outer!.isValid)
	}
	
	convenience init() {
		self.init(outer: nil)
	}
	
	init(outer : TLog?) {
		self.outer = outer
		pthread_mutex_init(self.locker, nil)
		pthread_cond_init(self.cond, nil)
	}
	
	static func newTVar<T>(_ value : T) -> TVar<T> {
		return TVar(value)
	}
	
	func readTVar<T>(_ location : TVar<T>) -> T {
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
	
	func writeTVar<T>(_ location : TVar<T>, value : TVarType<T>) {
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
			throw STMError.invalidOperationException
		} else {
			log.values.forEach {
				$0.commit()
			}
		}
	}
	
	static func atomically<T>(_ p : (TLog) throws -> T) throws -> T {
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
			} catch STMError.retryException {
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
			} catch STMError.commitFailedException {
				throw STMError.commitFailedException
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
		throw STMError.retryException
	}
	
	func orElse<T>(_ p : (TLog) throws -> T, q : (TLog) throws -> T) throws -> T {
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
				throw STMError.commitFailedException
			}
		} catch STMError.retryException {
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
					throw STMError.commitFailedException
				}
			} catch STMError.retryException {
				self.lock()
				let isValid = first.isValid && second.isValid && self.isValid
				self.unlock()
				if isValid {
					first.mergeNested()
					second.mergeNested()
					throw STMError.retryException
				} else {
					throw STMError.commitFailedException
				}
			} catch STMError.commitFailedException {
				throw STMError.commitFailedException
			} catch let l {
				second.lock()
				let isValid = second.isValid
				second.unlock()
				if isValid {
					second.mergeNested()
					throw l
				} else {
					throw STMError.commitFailedException
				}
			}
		} catch STMError.commitFailedException {
			throw STMError.commitFailedException
		} catch let l {
			first.lock()
			let isValid = first.isValid
			first.unlock()
			if isValid {
				first.mergeNested()
				throw l
			} else {
				throw STMError.commitFailedException
			}
		}
	}
}
