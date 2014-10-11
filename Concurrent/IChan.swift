//
//  IChan.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

/// Multicast unbounded FIFO streams.  IChans differ from regular chans because you are only given
/// access to a write-once head.  Any attempts to write multiple times to an IChan head will fail
/// catastrophically.  However, every write operation to an IChan spawns a new write head that you
/// can use to continue writing values into the stream.
///
/// IChans are multicast channels, meaning there is no such thing as "taking a value out of the
/// stream" like there is with regular channels.  Multiple readers of the channel will all see the
/// same values.
public class IChan<A> : K1<A> {
	let ivar : IVar<(A, IChan<A>)>

	init(_ ivar : IVar<(A, IChan<A>)>) {
		self.ivar = ivar
	}
}

/// Creates a new channel.
public func newIChan<A>() -> IO<IChan<A>> {
	return do_ { () -> IChan<A> in
		let v : IVar<(A, IChan<A>)> = !newEmptyIVar()
		return IChan(v)
	}
}

/// Reads all the values from a channel into a list.
///
/// This computation may block on empty IVars.
public func readIChan<A>(c : IChan<A>) -> [A] {
	let (a, ic) = readIVar(c.ivar)
	return [a] + readIChan(c)
}

/// Writes a single value to the head of the channel and returns a new write head.
///
/// If the same head has been written to more than once, this function will throw an exception.
public func writeIChan<A>(c : IChan<A>) -> A -> IO<IChan<A>> {
	return { x in
		do_ { () -> IChan<A> in
			let ic : IChan<A> = !newIChan()
			putIVar(c.ivar)(x: (x, ic))
			return ic
		}
	}
}

/// Attempts to write a value to the head of the channel.  If the channel head has already been 
/// written to, the result is an IO computation returning None.  If the channel head is empty, the
/// value is written, and a new write head wrapped in an IO computation is returned.
public func tryWriteIChan<A>(c : IChan<A>) -> A -> IO<Optional<IChan<A>>> {
	return { x in
		do_ { () -> Optional<IChan<A>> in
			let ic : IChan<A> = !newIChan()
			let succ = !tryPutIVar(c.ivar)(x: (x, ic))
			return succ ? Optional.Some(ic) : Optional.None
		}
	}
}
