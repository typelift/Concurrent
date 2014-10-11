//
//  Weak.swift
//  Basis
//
//  Created by Robert Widmann on 9/13/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Basis

/// Channels are unbounded FIFO streams of values with a read and write terminals comprised of
/// MVars.
public final class Chan<A> : K1<A> {
	let readEnd : MVar<MVar<ChItem<A>>>
	let writeEnd : MVar<MVar<ChItem<A>>>
	
	init(read : MVar<MVar<ChItem<A>>>, write: MVar<MVar<ChItem<A>>>) {
		self.readEnd = read
		self.writeEnd = write
		super.init()
	}
}

/// Creates and returns a new empty channel.
public func newChan<A>() -> IO<Chan<A>> {
	return do_ { () -> Chan<A> in
		let hole : MVar<ChItem<A>> = !newEmptyMVar()
		let readVar = !newMVar(hole)
		let writeVar : MVar<MVar<ChItem<A>>> = !newMVar(hole)

		return Chan(read: readVar, write: writeVar)
	}
}

/// Writes a value to a channel.
public func writeChan<A>(c : Chan<A>)(x : A) -> IO<()> {
	return modifyMVar_(c.writeEnd)({ (let old_hole) in
		return do_ { () -> MVar<ChItem<A>> in
			let new_hole : MVar<ChItem<A>> = !newEmptyMVar()
			!putMVar(old_hole)(ChItem(x, new_hole))
			return new_hole
		}
	})
}

/// Reads a value from the channel.
public func readChan<A>(c : Chan<A>) -> IO<A> {
	return do_ { () -> IO<A> in
		return modifyMVar(c.readEnd)({ (let readEnd) in
			return do_ { () -> (MVar<ChItem<A>>, A) in
				let item : ChItem<A> = !readMVar(readEnd)
				return (item.stream, item.val)
			}
		})
	}
}

public func isEmptyChan<A>(c : Chan<A>) -> IO<Bool> {
	return do_ {
		return withMVar(c.readEnd)({ r in
			do_ { () -> Bool in
				let w = !tryReadMVar(r)
				return w == nil
			}
		})
	}
}

/// Duplicates a channel.
///
/// The duplicate channel begins empty, but data written to either channel from then on will be 
/// available from both. Because both channels share the same write end, data inserted into one
/// channel may be read by both channels.
public func dupChan<A>(c : Chan<A>) -> IO<Chan<A>> {
	return do_({ () -> Chan<A> in
		let hole = !readMVar(c.writeEnd)
		let newReadVar = !newMVar(hole)
		return Chan(read: newReadVar, write: c.writeEnd)
	})
}

public func getChanContents<A>(c : Chan<A>) -> IO<[A]> {
	return do_ { () -> [A] in
		if !isEmptyChan(c) {
			return []
		}
		let x = !readChan(c)
		let xs = !getChanContents(c)
		return [x] + xs
	}
}

public func writeListToChan<A>(c : Chan<A>) -> [A] -> IO<()> {
	return { xs in sequence_(xs.map(writeChan(c))) }
}

internal class ChItem<A> : K1<A> {
	let val : A
	let stream : MVar<ChItem<A>>

	init(_ val : A, _ stream : MVar<ChItem<A>>) {
		self.val = val
		self.stream = stream
	}
}

