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
	
	private init(_ value : TVarType<T>, _ id : Int) {
		self.value = value
		self._id = id
	}
	
	internal var upCast : TVar<Any> {
		return TVar<Any>(self.value.upCast, self._id)
	}
}

extension TVar where T : Equatable {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = PreEquatable(t: value)
		nextId += 1
		self._id = nextId
	}
}

extension TVar where T : AnyObject {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = UnderlyingRef(t: value)
		nextId += 1
		self._id = nextId
	}
}

extension TVar where T : Any {
	public init(@autoclosure(escaping) _ value : () -> T) {
		self.value = Ref(t: value)
		nextId += 1
		self._id = nextId
	}
}

internal class TVarType<T> : Equatable {
	var retrieve : T { fatalError() }
	var upCast : TVarType<Any> { fatalError() }
}

internal func == <T>(l : TVarType<T>, r : TVarType<T>) -> Bool {
	if let ll = l as? Ref<T>, let rr = r as? Ref<T> {
		return ll === rr
	}
	fatalError()
}

internal func == <T : AnyObject>(l : TVarType<T>, r : TVarType<T>) -> Bool {
	if let ll = l as? Ref<T>, let rr = r as? Ref<T> {
		return ll === rr
	} else if let ll = l as? UnderlyingRef<T>, let rr = r as? UnderlyingRef<T> {
		return ll == rr
	}
	fatalError()
}

internal class PreEquatable<T : Equatable> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }
	override var upCast : TVarType<Any> { return Ref<Any>(t: { (self.retrieve as Any) }) }

	init(t : () -> T) { self.t = t }
}

internal func == <T : Equatable>(l : PreEquatable<T>, r : PreEquatable<T>) -> Bool {
	return l.retrieve == r.retrieve
}

internal class Ref<T> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }
	override var upCast : TVarType<Any> { return Ref<Any>(t: { (self.retrieve as Any) }) }

	init(t : () -> T) { self.t = t }
}

internal func == <T>(l : Ref<T>, r : Ref<T>) -> Bool {
	return l === r
}

internal class UnderlyingRef<T : AnyObject> : TVarType<T> {
	let t : () -> T

	override var retrieve : T { return self.t() }
	override var upCast : TVarType<Any> { return Ref<Any>(t: { (self.retrieve as Any) }) }

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
