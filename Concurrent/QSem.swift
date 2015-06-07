//
//  QSem.swift
//  Basis
//
//  Created by Robert Widmann on 9/13/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

/// QSem is a simple quanitity semaphore (read: counting semaphore) that aquires and releases
/// resources in increments of 1.  The semaphore keeps track of blocked threads with MVar<()>'s.
/// When a thread becomes unblocked, the semaphore simply fills the MVar with a ().  Threads can
/// also unblock themselves by putting () into their MVar.
public struct QSem {
	let contents : MVar<(UInt, [MVar<()>], [MVar<()>])>
	
	private init(_ c : MVar<(UInt, [MVar<()>], [MVar<()>])>){
		self.contents = c
	}
	
	/// Creates a new quantity semaphore.
	public init(initial : UInt) {
		let t : (UInt, [MVar<()>], [MVar<()>]) = (initial, [], [])
		let sem = MVar(initial: t)
		self.init(sem)
	}
	
	/// Decrements the value of the semaphore by 1 and waits for a unit to become available.
	public func wait() {
		let t : (UInt, [MVar<()>], [MVar<()>]) = self.contents.take()
		if t.0 == 0 {
			let b = MVar<()>()
			let u = (t.0, t.1, [b] + t.2)
			self.contents.put(u)
			b.take()
		} else {
			let u = (t.0 - 1, t.1, t.2)
			self.contents.put(u)
		}
	}
	
	/// Increments the value of the semaphore by 1 and signals that a unit has become available.
	public func signal() {
		let t = self.contents.take()
		let r = self.signal(t)
		self.contents.put(r)
	}
	
	private func signal(t : (UInt, [MVar<()>], [MVar<()>])) -> (UInt, [MVar<()>], [MVar<()>]) {
		switch t {
		case (let i, let a1, let a2):
			if i == 0 {
				return self.loop(a1, b2: a2)
			}
			let t : (UInt, [MVar<()>], [MVar<()>]) = (i + 1, a1, a2)
			return t
		}
	}
	
	private func loop(l : [MVar<()>], b2 : [MVar<()>]) -> (UInt, [MVar<()>], [MVar<()>]) {
		if l.count == 0 && b2.count == 0 {
			let t : (UInt, [MVar<()>], [MVar<()>]) = (1, [], [])
			return t
		} else if b2.count != 0 {
			return self.loop(b2.reverse(), b2: [])
		}
		
		let b = l[0]
		let bs = Array<MVar<()>>(l[1 ..< l.count])
		if b.tryPut(()) {
			let t : (UInt, [MVar<()>], [MVar<()>]) = (0, bs, b2)
			return t
		}
		return self.loop(bs, b2: b2)
	}
}
