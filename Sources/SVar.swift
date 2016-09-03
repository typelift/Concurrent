//
//  SVar.swift
//  Concurrent
//
//  Created by Robert Widmann on 2/3/15.
//  Copyright (c) 2015 TypeLift. All rights reserved.
//

/// An SVar ("Sample Variable") is an MVar that allows for overwriting its contents without blocking.
///
/// - Reading an empty 'SVar' causes the reader to block.
///   (same as 'take()' on an empty 'MVar')
///
/// - Reading a filled 'SVar' empties it and returns its value.
///   (same as 'take() on a full MVar')
///
/// - Writing to an empty 'SVar' fills it with a value and potentially wakes up a blocked reader.
///   (same as for 'put()' on an empty 'MVar').
///
/// - Writing to a filled 'SVar' overwrites the current value.
///   (different from 'put()' on a full 'MVar'.)
public struct SVar<A> {
	let svar : MVar<(Int, MVar<A>)>
	
	fileprivate init(_ svar : MVar<(Int, MVar<A>)>) {
		self.svar = svar
	}
	
	/// Creates a new empty SVar.
	public init() {
		let v = MVar<A>()
		self.init(MVar(initial: (0, v)))
	}
	
	/// Creates a new SVar containing the supplied value.
	public init(initial : A){
		let v = MVar<A>(initial: initial)
		self.init(MVar(initial: (1, v)))
	}
	
	/// Empties the reciever.
	///
	/// If the reciever is currently empty, this function does nothing.
	public func empty() {
		let s = self.svar.take()
		let (readers, val) = s
		if readers > 0 {
			let _ = val.take()
			self.svar.put((Int.allZeros, val))
		} else {
			self.svar.put(s)
		}
	}
	
	/// Reads a value from the receiver, then empties it.
	public func read() -> A {
		let (readers, val) = self.svar.take()
		self.svar.put(((readers - 1), val))
		return val.take()
	}
	
	/// Writes a value into the receiver, overwriting any previous value that may currently exist.
	public func write(_ v : A) {
		let s = self.svar.take()
		let (readers, val) = s
		
		switch readers {
		case 1:
			_ = val.swap(v)
			self.svar.put(s)
		default:
			val.put(v)
			self.svar.put((min(1, (readers + 1)), val))
		}
	}
	
	/// Returns whether the receiver is empty.
	///
	/// This function is just a snapshot of the state of the SVar at that point in time.  In heavily 
	/// concurrent computations, this may change out from under you without warning, or even by the time
	/// it can be acted on.  It is better to use one of the direct actions above.
	public var isEmpty : Bool {
		let (readers, _) = self.svar.read()
		return readers == 0
	}
}

/// Equality over SVars.
///
/// Two SVars are equal if they both contain no value or if the values they contain are equal.  This
/// particular definition of equality is time-dependent and fundamentally unstable.  By the time 
/// two SVars can be read and compared for equality, one may have already lost its value, or may
/// have had its value swapped out from under you.  It is better to `read()` the values yourself
/// if you need a stricter equality.
public func ==<A : Equatable>(lhs : SVar<A>, rhs : SVar<A>) -> Bool {
	if lhs.isEmpty && rhs.isEmpty {
		return true
	}
	if lhs.isEmpty != rhs.isEmpty {
		return false
	}
	return lhs.read() == rhs.read()
}
