//
//  Concurrent.swift
//  Basis
//
//  Created by Robert Widmann on 9/15/14.
//  Copyright (c) 2014 Robert Widmann. All rights reserved.
//

import Basis

public typealias ThreadID = pthread_t

public func myTheadID() -> IO<ThreadID> {
	return IO.pure(pthread_self())
}

/// Forks a computation onto a new thread and returns its thread ID.
public func forkIO(io : IO<()>) -> IO<ThreadID> {
	return do_ { () -> ThreadID in
		return PARRealWorld.forkWithStart({
			return io.unsafePerformIO()
		})
	}
}

/// Returns the number of processor the host has.
public func getNumProcessors() -> IO<UInt> {
	return do_ { () -> UInt in
		return PARRealWorld.CPUCount()
	}
}

/// Kills a given thread.
///
/// This function invokes pthread_kill, so all necessary cleanup handlers will fire.  Threads may
/// not immediately terminate if they are setup improperly or by the user.
public func killThread(tid : ThreadID) -> IO<()> {
	return do_ { () -> () in
		return PARRealWorld.killThread(tid)
	}
}

/// Indicates that a thread wishes to yeild time to other waiting threads.
public func yield() -> IO<()> {
	return do_ { () -> () in
		return PARRealWorld.yieldThread()
	}
}

/// Labels the current thread.
public func labelThread(name : String) -> IO<()> {
	return do_ { () -> () in
		return name.withCString({ (let str) -> Void in
			return PARRealWorld.labelThreadWithName(str)
		})
	}
}
