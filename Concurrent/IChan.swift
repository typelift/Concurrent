//
//  IChan.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

/// Multicast unbounded FIFO streams.  IChans differ from regular chans because you are only given
/// access to a write-once head.  Any attempts to write multiple times to an IChan head will fail
/// catastrophically.  However, every write operation to an IChan spawns a new write head that you
/// can use to continue writing values into the stream.
///
/// IChans are multicast channels, meaning there is no such thing as "taking a value out of the
/// stream" like there is with regular channels.  Multiple readers of the channel will all see the
/// same values.
public struct IChan<A> {
	let ivar : IVar<(A, IChan<A>)>

	private init(_ ivar : IVar<(A, IChan<A>)>) {
		self.ivar = ivar
	}
	
	/// Creates a new channel.
	public init() {
		let v : IVar<(A, IChan<A>)> = IVar()
		self.init(v)
	}
	
	/// Reads all the values from a channel into a list.
	///
	/// This computation may block on empty IVars.
	public func read() -> [A] {
		let (a, ic) = self.ivar.read()
		return [a] + ic.read()
	}
	
	
	/// Writes a single value to the head of the channel and returns a new write head.
	///
	/// If the same head has been written to more than once, this function will throw an exception.
	public func write(x : A) -> IChan<A> {
		let ic = IChan()
		do {
			try self.ivar.put((x, ic))
		} catch _ {
			fatalError("Fatal: Accidentally wrote to the same IChan head twice.")
		}
		return ic
	}

	/// Attempts to write a value to the head of the channel.  If the channel head has already been 
	/// written to, the result is .None.  If the channel head is empty, the value is written, and a 
	/// new write head is returned.
	public func tryWrite(x : A) -> Optional<IChan<A>> {
		let ic = IChan()
		return self.ivar.tryPut((x, ic)) ? .Some(ic) : .None
	}
}
