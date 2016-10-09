//
//  TVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015-2016 TypeLift. All rights reserved.
//

/// A `TVar` (read: Transactional Variable) is a shared memory location that
/// supports atomic memory transactions.
public final class TVar<T> : Comparable, Hashable {
	/// Uses an STM transaction to return the current value stored in the `TVar`.
	public func read() -> STM<T>  {
		return STM { trans in
			return trans.readTVar(self)
		}
	}

	/// Determines whether another `TVar` is exactly this `TVar` without
	/// comparing their contents.
	public static func == <T>(l : TVar<T>, r : TVar<T>) -> Bool {
		return l._id == r._id
	}

	/// Determines whether another `TVar` was created after this `TVar` without
	/// comparing their contents.
	public static func < <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
		return lhs._id < rhs._id
	}

	/// The hash value uniquely identifying this `TVar`.
	public var hashValue : Int {
		return _id
	}

	internal var value : TVarType<T>
	private let _id : Int

	/// Essentially a copy constructor.
	fileprivate init(_ value : TVarType<T>, _ id : Int) {
		self.value = value
		self._id = id
	}
}

extension TVar where T : Hashable {
	public convenience init(_ value : T) {
		self.init(TVarType<T>(hash: value ), nextId.read())
		nextId.modify_ { $0 + 1 }
	}

	/// Uses an STM transaction to write the supplied value into the `TVar`.
	public func write(_ value : T) -> STM<()>  {
		return STM<T>({ (trans : TLog) in
			trans.writeTVar(self, value: TVarType(hash: value))
			return value
		}).then(STM<()>.pure(()))
	}
}

extension TVar {
	public convenience init(_ value : T) {
		self.init(TVarType<T>(def: value), nextId.read())
		nextId.modify_ { $0 + 1 }
	}

	/// Uses an STM transaction to write the supplied value into the `TVar`.
	public func write(_ value : T) -> STM<()>  {
		return STM<T>({ (trans : TLog) in
			trans.writeTVar(self, value: TVarType<T>(def: value))
			return value
		}).then(STM<()>.pure(()))
	}
}

// MARK: Implementation details follow.

/// A `TVarType` is an existential container for the contents of a TVar.  It is
/// not actually generic, but the type it is parametrized by is used to check
/// the type of values during writes and reads to make sure it is being used
/// in a safe manner.
internal final class TVarType<T> : Hashable {
	var _fingerprint : Int
	var _val : Any

	var hashValue : Int { return _fingerprint }

	init(_ v : T, _ fingerprint : Int) {
		self._fingerprint = fingerprint
		self._val = v
	}

	static func == (l : TVarType<T>, r : TVarType<T>) -> Bool {
		return l.hashValue == r.hashValue
	}
}

extension TVarType where T : Hashable {
	convenience init(hash t : T) {
		self.init(t, t.hashValue)
	}
}

extension TVarType {
	convenience init(def t : T) {
		self.init(t, 0)
		self._fingerprint = ObjectIdentifier(self).hashValue
	}
}

private var nextId = MVar<Int>(initial: Int.min)
