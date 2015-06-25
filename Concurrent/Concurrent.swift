//
//  Concurrent.swift
//  Basis
//
//  Created by Robert Widmann on 9/15/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

public typealias ThreadID = pthread_t

public func myTheadID() -> ThreadID {
	return pthread_self()
}

/// Forks a computation onto a new thread and returns its thread ID.
public func forkIO(@autoclosure(escaping) io :  () -> ()) -> ThreadID {
	return CONCRealWorld.forkWithStart({
		return io()
	})
}

/// Forks a computation onto a new thread and returns its thread ID.
public func forkIO(io :  () -> ()) -> ThreadID {
    return CONCRealWorld.forkWithStart({
        return io()
    })
}

/// Forks a thread and calls the given function when the thread is about to terminate with either
/// a value or an exception.
public func forkFinally<A>(@autoclosure(escaping) io :  () throws -> A, finally : Either<ErrorType, A> -> ()) -> ThreadID {
    return forkIO {
        do {
            let r = try io()
            finally(Either.Right(r))
        } catch let excn {
            finally(Either.Left(excn))
        }
    }
}

/// Returns the number of processor the host has.
public func getNumProcessors() -> UInt {
	return CONCRealWorld.CPUCount()
}

/// Kills a given thread.
///
/// This function invokes pthread_kill, so all necessary cleanup handlers will fire.  Threads may
/// not immediately terminate if they are setup improperly or by the user.
public func killThread(tid : ThreadID) {
	return CONCRealWorld.killThread(tid)
}

/// Indicates that a thread wishes to yield time to other waiting threads.
public func yield() {
	return CONCRealWorld.yieldThread()
}

/// Labels the current thread.
public func labelThread(name : String) {
	return name.withCString({ (let str) -> Void in
		return CONCRealWorld.labelThreadWithName(str)
	})
}
