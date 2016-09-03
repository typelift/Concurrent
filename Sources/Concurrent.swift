//
//  Concurrent.swift
//  Basis
//
//  Created by Robert Widmann on 9/15/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

public typealias ThreadID = pthread_t

public func myTheadID() -> ThreadID {
	return pthread_self()
}

/// Forks a computation onto a new thread and returns its thread ID.
public func forkIO(_ io :  @autoclosure @escaping () -> ()) -> ThreadID {
	return CONCRealWorld.fork(start: {
		return io()
	})
}

/// Forks a computation onto a new thread and returns its thread ID.
public func forkIO(_ io :  @escaping () -> ()) -> ThreadID {
	return CONCRealWorld.fork(start: {
		return io()
	})
}

/// Kills a given thread.
///
/// This function invokes pthread_kill, so all necessary cleanup handlers will fire.  Threads may
/// not immediately terminate if they are setup improperly or by the user.
public func killThread(_ tid : ThreadID) {
	return CONCRealWorld.killThread(tid)
}

/// Indicates that a thread wishes to yield time to other waiting threads.
public func yield() {
	return CONCRealWorld.yieldThread()
}

/// Labels the current thread.
public func labelThread(_ name : String) {
	return name.withCString({ (str) -> Void in
		return CONCRealWorld.labelThread(withName: str)
	})
}
