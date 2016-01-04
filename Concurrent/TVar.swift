//
//  TVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

/// A transactional variable
public struct TVar<T> : Comparable, Hashable {
	internal var value : TVarType<T>
	let _id : Int

	public var hashValue : Int {
		return _id
	}
}

extension TVar where T : Equatable {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = Equity(t: value)
		nextId++
		self._id = nextId
	}
}

extension TVar where T : AnyObject {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = UnderlyingRef(t: value)
		nextId++
		self._id = nextId
	}
}

extension TVar where T : Any {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = Ref(t: value)
		nextId++
		self._id = nextId
	}
}

internal class TVarType<T> : Equatable {
	var retrieve : T { fatalError() }
}

internal func == <T>(l : TVarType<T>, r : TVarType<T>) -> Bool {
	print(unsafeAddressOf(l))
	print(unsafeAddressOf(r))
	if let ll = l as? Ref<T>, rr = r as? Ref<T> {
		return ll === rr
	} else if let ll = l as? UnderlyingRef<AnyObject>, rr = r as? UnderlyingRef<AnyObject> {
		return ll == rr
	}
	fatalError()
}

internal class Equity<T : Equatable> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }

	init(t : () -> T) { self.t = t }
}

internal func == <T : Equatable>(l : Equity<T>, r : Equity<T>) -> Bool {
	return l.retrieve == r.retrieve
}

internal class Ref<T> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }

	init(t : () -> T) { self.t = t }
}

internal func == <T>(l : Ref<T>, r : Ref<T>) -> Bool {
	return l === r
}

internal class UnderlyingRef<T : AnyObject> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }

	init(t : () -> T) { self.t = t }
}

public func == <T>(l : TVar<T>, r : TVar<T>) -> Bool {
	return l._id == r._id
}

public func < <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
	return lhs._id < rhs._id
}

public func <= <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
	return lhs._id <= rhs._id
}

public func >= <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
	return lhs._id >= rhs._id
}

public func > <T>(lhs : TVar<T>, rhs : TVar<T>) -> Bool {
	return lhs._id > rhs._id
}

private var nextId : Int = Int.min
