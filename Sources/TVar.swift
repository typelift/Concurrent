//
//  TVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

/// A `TVar` (read: Transactional Variable) is a shared memory location that 
/// supports atomic memory transactions.
public final class TVar<T> : Comparable, Hashable {
	internal var value : TVarType<T>
	let _id : Int

	public var hashValue : Int {
		return _id
	}
	
	/// Uses an STM transaction to return the current value stored in the receiver.
	public func read() -> STM<T>  {
		return STM { trans in
			return trans.readTVar(self)
		}
	}
	
	fileprivate init(_ value : TVarType<T>, _ id : Int) {
		self.value = value
		self._id = id
	}

	public static func == <T>(l : TVar<T>, r : TVar<T>) -> Bool {
		return l._id == r._id
	}

	public static func < <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
		return lhs._id < rhs._id
	}

	var upCast : TVar<Any> {
		return unsafeBitCast(self, to: TVar<Any>.self)
	}
}

extension TVar where T : Hashable {
	public convenience init(_ value : @autoclosure @escaping () -> T) {
		self.init(TVarType<T>(hash: value ), nextId)
		nextId += 1
	}
	
	/// Uses an STM transaction to write the supplied value into the receiver.
	public func write(_ value : T) -> STM<()>  {
		return STM<T>({ (trans : TLog) in
			trans.writeTVar(self, value: TVarType(hash: { value }))
			return value
		}).then(STM<()>.pure(()))
	}
}

extension TVar {
	public convenience init(_ value : @autoclosure @escaping () -> T) {
		self.init(TVarType<T>(def: value), nextId)
		nextId += 1
	}
	
	/// Uses an STM transaction to write the supplied value into the receiver.
	public func write(_ value : T) -> STM<()>  {
		return STM<T>({ (trans : TLog) in
			trans.writeTVar(self, value: TVarType<T>(def: { value }))
			return value
		}).then(STM<()>.pure(()))
	}
}

internal final class TVarType<T> : Hashable {
	var _fingerprint : Int
	var _val : () -> Any

	var hashValue : Int { return _fingerprint }
	// HACK: bridge-all-the-things-to-Any makes this a legal transformation.
	var upCast : TVarType<Any>{
		return unsafeBitCast(self, to: TVarType<Any>.self)
	}

	init(_ v : @escaping () -> T, _ fingerprint : Int) {
		self._fingerprint = fingerprint
		self._val = v
	}

	static func == (l : TVarType<T>, r : TVarType<T>) -> Bool {
		return l.hashValue == r.hashValue
	}
}

extension TVarType where T : Hashable {
	convenience init(hash t : @escaping () -> T) {
		self.init(t, t().hashValue)
	}
}

extension TVarType {
	convenience init(def t : @escaping () -> T) {
		self.init(t, 0)
		self._fingerprint = ObjectIdentifier(self).hashValue
	}
}

private var nextId : Int = Int.min
