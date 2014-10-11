//
//  QSem.swift
//  Basis
//
//  Created by Robert Widmann on 9/13/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

/// QSem is a simple quanitity semaphore (read: counting semaphore) that aquires and releases
/// resources in increments of 1.  The semaphore keeps track of blocked threads with MVar<()>'s.
/// When a thread becomes unblocked, the semaphore simply fills the MVar with a ().  Threads can
/// also unblock themselves by putting () into their MVar.
public final class QSem : K0 {
	let contents : MVar<(UInt, [MVar<()>], [MVar<()>])>
	
	init(_ c : MVar<(UInt, [MVar<()>], [MVar<()>])>){
		self.contents = c
		super.init()
	}
}

/// Creates a new quantity semaphore.
public func newQSem(initial : UInt) -> IO<QSem> {
	return do_({ () -> QSem in
		let sem : MVar<(UInt, [MVar<()>], [MVar<()>])> = !newMVar((initial, [], []))
		return QSem(sem)
	})
}

/// Decrements the value of the semaphore by 1 and waits for a unit to become available.
public func waitQSem(q : QSem) -> IO<()> {
	return do_({ () -> () in
		let t : (UInt, [MVar<()>], [MVar<()>]) = !takeMVar(q.contents)
		if t.0 == 0 {
			let b : MVar<()> = !newEmptyMVar()
			let u = (t.0, t.1, [b] + t.2)
			!putMVar(q.contents)(u)
			!takeMVar(b)
		} else {
			let u = (t.0 - 1, t.1, t.2)
			!putMVar(q.contents)(u)
		}
	})
}

/// Increments the value of the semaphore by 1 and signals that a unit has become available.
public func signalQSem(q : QSem) -> IO<()> {
	return do_({ () -> () in
		let t = !takeMVar(q.contents)
		let r = !signal(t)
		putMVar(q.contents)(r)
	})
}

private func signal(t : (UInt, [MVar<()>], [MVar<()>])) -> IO<(UInt, [MVar<()>], [MVar<()>])> {
	switch t {
		case (let i, let a1, let a2):
			if i == 0 {
				return loop(a1, a2)
			}
			let t : (UInt, [MVar<()>], [MVar<()>]) = (i + 1, a1, a2)
			return IO.pure(t)
	}
}

private func loop(l : [MVar<()>], b2 : [MVar<()>]) -> IO<(UInt, [MVar<()>], [MVar<()>])> {
	if l.count == 0 && b2.count == 0 {
		let t : (UInt, [MVar<()>], [MVar<()>]) = (1, [], [])
		return IO.pure(t)
	} else if b2.count != 0 {
		return loop(b2.reverse(), [])
	}
	return do_({ () -> IO<(UInt, [MVar<()>], [MVar<()>])> in
		let b = l[0]
		let bs = Array<MVar<()>>(l[1 ..< l.count])
		let r : Bool = !tryPutMVar(b)(())
		if r {
			let t : (UInt, [MVar<()>], [MVar<()>]) = (0, bs, b2)
			return IO.pure(t)
		}
		return loop(bs, b2)
	})
}
