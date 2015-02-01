//
//  Weak.swift
//  Basis
//
//  Created by Robert Widmann on 9/13/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftx

/// Channels are unbounded FIFO streams of values with a read and write terminals comprised of
/// MVars.
public struct Chan<A> {
	let readEnd : MVar<MVar<ChItem<A>>>
	let writeEnd : MVar<MVar<ChItem<A>>>
	
	private init(read : MVar<MVar<ChItem<A>>>, write: MVar<MVar<ChItem<A>>>) {
		self.readEnd = read
		self.writeEnd = write
	}
	
	/// Creates and returns a new empty channel.
	public init() {
		let hole : MVar<ChItem<A>> = MVar()
		let readVar = MVar(initial: hole)
		let writeVar : MVar<MVar<ChItem<A>>> = MVar(initial: hole)
		
		self.init(read: readVar, write: writeVar)
	}
	
	
	/// Reads a value from the channel.
	public func read() -> A {
		return self.readEnd.modify { readEnd in
			let item : ChItem<A> = readEnd.read()
			return (item.stream(), item.val())
		}
	}
	
	/// Writes a value to a channel.
	public func write(x : A) {
		self.writeEnd.modify_ { old_hole in
			let new_hole : MVar<ChItem<A>> = MVar()
			old_hole.put(ChItem(x, new_hole))
			return new_hole
		}
	}
	
	/// Writes a list of values to a channel.
	public func writeList(xs : [A]) {
		xs.map({ self.write($0) })
	}
	
	public var isEmpty : Bool {
		return self.readEnd.withMVar { r in
			let w = r.tryRead()
			return w == nil
		}
	}
	
	/// Duplicates a channel.
	///
	/// The duplicate channel begins empty, but data written to either channel from then on will be 
	/// available from both. Because both channels share the same write end, data inserted into one
	/// channel may be read by both channels.
	public func duplicate() -> Chan<A> {
		let hole = self.writeEnd.read()
		let newReadVar = MVar(initial: hole)
		return Chan(read: newReadVar, write: self.writeEnd)
	}
	
	public func contents() -> [A] {
		if self.isEmpty {
			return []
		}
		let x = self.read()
		let xs = self.contents()
		return [x] + xs
	}
}

internal struct ChItem<A> {
	let val : () -> A
	let stream : () -> MVar<ChItem<A>>

	init(_ val : @autoclosure () -> A, _ stream : @autoclosure () -> MVar<ChItem<A>>) {
		self.val = val
		self.stream = stream
	}
}

