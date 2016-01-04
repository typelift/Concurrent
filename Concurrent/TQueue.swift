//
//  TQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}
}

public func newTQueue<A>() -> STM<TQueue<A>> {
	let read = TVar([] as [A])
	let write = TVar([] as [A])
	return STM<TQueue<A>>.pure(TQueue(read, write))
}

public func writeTQueue<A>(q : TQueue<A>, _ val : A) -> STM<()> {
	return readTVar(q.writeEnd).flatMap { list in
		return writeTVar(q.writeEnd, value: [val] + list)
	}
}
