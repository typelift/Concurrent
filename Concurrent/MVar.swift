//
//  MVar.swift
//  Basis
//
//  Created by Robert Widmann on 9/12/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

/// MVars (literally "Mutable Variables") are mutable references that are either empty or contain a
/// value of type A.  An MVar is often compared to a box, or to a diner in that if there is no value
/// in the box (no food in the restaurant), you have to wait, possibly in line, before you can get
/// what you want.  In this way, they are "Synchronization Primitives" that can be used to make
/// multiple threads wait on the appropriate value before proceeding with a computation.
public final class MVar<A> : K1<A> {
	private var val : A?
	private let lock: UnsafeMutablePointer<pthread_mutex_t>
	private let takeCond: UnsafeMutablePointer<pthread_cond_t>
	private let putCond: UnsafeMutablePointer<pthread_cond_t>
	
	override init() {
		self.val = .None
		self.lock = UnsafeMutablePointer.alloc(sizeof(pthread_mutex_t))
		self.takeCond = UnsafeMutablePointer.alloc(sizeof(pthread_cond_t))
		self.putCond = UnsafeMutablePointer.alloc(sizeof(pthread_cond_t))
		
		pthread_mutex_init(self.lock, nil)
		pthread_cond_init(self.takeCond, nil)
		pthread_cond_init(self.putCond, nil)
		super.init()
	}
	
	deinit {
		self.lock.destroy()
		self.takeCond.destroy()
		self.putCond.destroy()
	}
}

/// Creates a new empty MVar.
public func newEmptyMVar<A>() -> IO<MVar<A>> {
	return do_ { () -> MVar<A> in
		return MVar()
	}
}

/// Creates a new MVar containing the supplied value.
public func newMVar<A>(x : A) -> IO<MVar<A>> {
	return newEmptyMVar() >>- { (let m : MVar<A>) in
		!putMVar(m)(x)
		return IO.pure(m)
	}
}

/// Returns the contents of the MVar.
///
/// If the MVar is empty, this will block until a value is put into the MVar.  If the MVar is full,
/// the value is wrapped up in an IO computation and the MVar is emptied.
public func takeMVar<A>(m : MVar<A>) -> IO<A> {
	return do_ { () -> A in
		pthread_mutex_lock(m.lock)
		while m.val == nil {
			pthread_cond_wait(m.takeCond, m.lock)
		}
		let value = m.val!
		m.val = .None
		pthread_cond_signal(m.putCond)
		pthread_mutex_unlock(m.lock)
		return value
	}
}

/// Atomically reads the contents of an MVar.
///
/// If the MVar is currently empty, this will block until a value is put into it.  If the MVar is
/// full, the value is wrapped up in an IO computation, but the MVar remains full.
public func readMVar<A>(m : MVar<A>) -> IO<A> {
	return do_ { () -> A in
		pthread_mutex_lock(m.lock)
		while m.val == nil {
			pthread_cond_wait(m.takeCond, m.lock)
		}
		let value = m.val!
		pthread_cond_signal(m.putCond)
		pthread_mutex_unlock(m.lock)
		return value
	}
}

/// Puts a value into an MVar.
///
/// If the MVar is currently full, the function will block until it becomes empty again.
public func putMVar<A>(m : MVar<A>) -> A -> IO<()> {
	return { x in
		return do_ { () -> () in
			pthread_mutex_lock(m.lock)
			while m.val != nil {
				pthread_cond_wait(m.putCond, m.lock)
			}
			m.val = x
			pthread_cond_signal(m.takeCond)
			pthread_mutex_unlock(m.lock)
			return ()
		}
	}
}

/// Attempts to return the contents of the MVar without blocking.
///
/// If the MVar is empty, this will immediately returns a None wrapped in an IO computation.  If the
/// MVar is full, the value is wrapped up in an IO computation and the MVar is emptied.
public func tryTakeMVar<A>(m : MVar<A>) -> IO<Optional<A>> {
	return do_ { () -> Optional<A> in
		pthread_mutex_lock(m.lock)
		if m.val == nil {
			return .None
		}
		let value = m.val!
		m.val = .None
		pthread_cond_signal(m.putCond)
		pthread_mutex_unlock(m.lock)
		return value
	}
}

/// Attempts to put a value into an MVar without blocking.
///
/// If the MVar is empty, this will immediately returns a true wrapped in an IO computation.  If the
/// MVar is full, nothing occurs and a false is returned in an IO computation.
public func tryPutMVar<A>(m : MVar<A>) -> A -> IO<Bool> {
	return { x in
		return do_ { () -> Bool in
			pthread_mutex_lock(m.lock)
			if m.val != nil {
				return false
			}
			m.val = x
			pthread_cond_signal(m.takeCond)
			pthread_mutex_unlock(m.lock)
			return true
		}
	}
}

/// Attempts to read the contents of an MVar without blocking.
///
/// If the MVar is empty, this function returns a None in an IO computation.  If the MVar is full,
/// this function wraps the value in a Some and an IO computation and returns immediately.
public func tryReadMVar<A>(m : MVar<A>) -> IO<Optional<A>> {
	return do_ { () -> Optional<A> in
		pthread_mutex_lock(m.lock)
		if m.val == nil {
			return .None
		}
		let value = m.val!
		pthread_cond_signal(m.putCond)
		pthread_mutex_unlock(m.lock)
		return value
	}
}

/// Checks whether a given MVar is empty.
///
/// This function is just a snapshot of the state of the MVar at that point in time.  In heavily 
/// concurrent computations, this may change out from under you without warning, or even by the time
/// it can be acted on.  It is better to use one of the direct actions above.
public func isEmptyMVar<A>(m : MVar<A>) -> IO<Bool> {
	return do_ { () -> Bool in
		return (m.val == nil)
	}
}

/// Atomically, take a value from the MVar, put a new value in the MVar, then return the old value 
/// in an IO computation.
public func swapMVar<A>(m : MVar<A>) -> A -> IO<A> {
	return { x in
		return do_ { () -> A in
			let old = !takeMVar(m)
			!putMVar(m)(x)
			return old
		}
	}
}

/// An exception-safe way of using the value in an MVar in a computation.
public func withMVar<A, B>(m : MVar<A>)(f : A -> IO<B>) -> IO<B> {
	return mask({ (let restore : (IO<B> -> IO<B>)) -> IO<B> in
		return do_ { () -> B in
			let a = !takeMVar(m)
			let b = !catchException(restore(f(a)))({ (let e) in
				return do_ { () -> IO<B> in
					return putMVar(m)(a) >> throwIO(e)
				}
			})
			!putMVar(m)(a)
			return b
		}	
	})
}

/// An exception-safe way to modify the contents of an MVar.
///
/// On exception, the value previously stored in the MVar is put back into it, and the exception is
/// rethrown.
public func modifyMVar_<A>(m : MVar<A>)(f : A -> IO<A>) -> IO<()> {
	return mask({ (let restore : IO<A> -> IO<A>) -> IO<()> in
		return do_ { () -> () in
			let a = !takeMVar(m)
//			let a1 = !catchException(restore(f(a)))({ (let e) in
//				return do_ { () -> IO<A> in
//					return putMVar(m)(a) >> throwIO(e)
//				}
//			})
			let a1 = !f(a)
			!putMVar(m)(a1)
		}
	})
}

/// An exception-safe way to modify the contents of an MVar.  On successful modification, the new
/// value of the MVar is returned in an IO computation.
///
/// On exception, the value previously stored in the MVar is put back into it, and the exception is
/// rethrown.
public func modifyMVar<A, B>(m : MVar<A>)(f : A -> IO<(A, B)>) -> IO<B> {
	return mask({ (let restore : IO<(A, B)> -> IO<(A, B)>) -> IO<B> in
		return do_ { () -> B in
			let a = !takeMVar(m)
//			let t = !catchException(restore(f(a)))({ (let e) in
//				return do_ { () -> IO<(A, B)> in
//					return putMVar(m)(a) >> throwIO(e)
//				}
//			})
			let t = !f(a)
			!putMVar(m)(fst(t))
			return snd(t)
		}
	})
}

public func ==<A : Equatable>(lhs : MVar<A>, rhs : MVar<A>) -> Bool {
	if !isEmptyMVar(lhs) && !isEmptyMVar(rhs) {
		return true
	}
	if !isEmptyMVar(lhs) ^ !isEmptyMVar(rhs) {
		return false
	}
	return !readMVar(lhs) == !readMVar(rhs)
}
