//
//  Weak.swift
//  Basis
//
//  Created by Robert Widmann on 9/13/14.
//  Copyright © 2014-2016 TypeLift. All rights reserved.
//

/// Channels are unbounded FIFO streams of values with a read and write
/// terminals comprised of `MVar`s.
public struct Chan<A> {
	fileprivate let readEnd : MVar<MVar<ChItem<A>>>
	fileprivate let writeEnd : MVar<MVar<ChItem<A>>>

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
		do {
			return try self.readEnd.modify { readEnd in
				let item : ChItem<A> = readEnd.read()
				return (item.stream(), item.val())
			}
		} catch _ {
			fatalError("Fatal: Could not modify read head.")
		}
	}

	/// Writes a value to a channel.
	public func write(_ x : A) {
		self.writeEnd.modify_ { old_hole in
			let new_hole : MVar<ChItem<A>> = MVar()
			old_hole.put(ChItem(x, new_hole))
			return new_hole
		}
	}

	/// Writes a list of values to a channel.
	public func writeList(_ xs : [A]) {
		xs.forEach(self.write)
	}

	/// Returns whether the channel is empty.
	///
	/// This function is just a snapshot of the state of the Chan at that point in
	/// time.  In heavily concurrent computations, this may change out from under
	/// you without warning, or even by the time it can be acted on.  It is better
	/// to use one of the direct actions above.
	public var isEmpty : Bool {
		do {
			return try self.readEnd.withMVar { r in
				let w = r.tryRead()
				return w == nil
			}
		} catch _ {
			fatalError("Fatal: Could not determine emptiness; read of underlying MVar failed.")
		}
	}

	/// Duplicates a channel.
	///
	/// The duplicate channel begins empty, but data written to either channel
	/// from then on will be available from both. Because both channels share the
	/// same write end, data inserted into one channel may be read by both
	/// channels.
	public func duplicate() -> Chan<A> {
		let hole = self.writeEnd.read()
		let newReadVar = MVar(initial: hole)
		return Chan(read: newReadVar, write: self.writeEnd)
	}

	/// Reads the entirety of the channel into an array.
	public func contents() -> [A] {
		if self.isEmpty {
			return []
		}
		let x = self.read()
		let xs = self.contents()
		return [x] + xs
	}
}

private struct ChItem<A> {
	let val : () -> A
	let stream : () -> MVar<ChItem<A>>

	init(_ val : @autoclosure @escaping () -> A, _ stream :  @autoclosure @escaping () -> MVar<ChItem<A>>) {
		self.val = val
		self.stream = stream
	}
}

