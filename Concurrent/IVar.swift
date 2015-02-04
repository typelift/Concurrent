//
//  IVar.swift
//  Basis
//
//  Created by Robert Widmann on 9/14/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

/// IVars are write-once mutable references.  Attempting to write into an already full IVar throws
/// an exception because the thread will be blocked indefinitely.
public struct IVar<A> {
	private let lock : MVar<()>
	private let trans : MVar<A>
	private let val : () -> A
	
	private init(_ lock : MVar<()>, _ trans : MVar<A>, _ val : @autoclosure () -> A) {
		self.lock = lock
		self.trans = trans
		self.val = val
	}
	
	public init() {
		let lock = MVar(initial: ())
		let trans : MVar<A> = MVar()
		self.init(lock, trans, trans.read())
	}
	
	/// Creates a new IVar containing the supplied value.
	public init(initial : @autoclosure () -> A) {
		let lock = MVar<()>()
		self.init(lock, MVar(initial: initial()), initial)
	}
	
	/// Returns the contents of the IVar.
	///
	/// If the IVar is empty, this will block until a value is put into the IVar.  If the IVar is full,
	/// the function returns the value immediately.
	public func read() -> A {
		return self.val()
	}

	/// Writes a value into an IVar.
	///
	/// If the IVar is currently full, the calling thread will seize up, and this function will throw an
	/// exception.
	public func put(x : A) {
		return self.tryPut(x) ? () : throw(BlockedIndefinitelyOnIVar())
	}
	
	/// Attempts to read the contents of an IVar
	///
	/// If the MVar is empty, this function returns a None in an IO computation.  If the MVar is full,
	/// this function wraps the value in a Some and an IO computation and returns immediately.
	public func tryRead() -> Optional<A> {
		if self.lock.isEmpty {
			return .Some(self.val())
		}
		return .None
	}
	
	/// Attempts to write a value into an IVar.
	///
	/// If the IVar is empty, this will immediately return true wrapped in an IO computation.  If the
	/// IVar is full, nothing happens and it will return false wrapped in an IO computation.
	public func tryPut(x : A) -> Bool {
		if let _ = self.lock.tryTake() {
			self.trans.put(x)
			let val = self.val()
			return true
		}
		return false
	}
}

public struct BlockedIndefinitelyOnIVar : Exception {
	public var description: String { 
		get {
			return "Cannot write to an already full IVar.  Thread blocked indefinitely."
		}
	}
}

