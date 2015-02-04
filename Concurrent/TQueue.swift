//
//  TQueue.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/28/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftx

public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}
}

public func newTQueue<A>() -> STM<TQueue<A>> {
	return do_ { () -> TQueue<A> in
		let read = !newTVar([] as [A])
		let write = !newTVar([] as [A])
		return TQueue(read, write)
	}
}

public func writeTQueue<A>(q : TQueue<A>) -> A -> STM<()> {
	return { x in
		do_ { () -> () in
			let list : [A] = !readTVar(q.writeEnd)
			writeTVar(q.writeEnd)(x: [x] + list)
		}
	}
}
