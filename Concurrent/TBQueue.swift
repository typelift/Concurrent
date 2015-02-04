//
//  TBQueue.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/29/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftx

public struct TBQueue<A> {
	let readNum : TVar<Int>
	let readHead : TVar<[A]>
	let writeNum : TVar<Int>
	let writeHead : TVar<[A]>

	init(_ readNum : TVar<Int>, _ readHead : TVar<[A]>, _ writeNum : TVar<Int>, _ writeHead : TVar<[A]>) {
		self.readNum = readNum
		self.readHead = readHead
		self.writeNum = writeNum
		self.writeHead = writeHead
	}
}

public func newTBQueue<A>(n : Int) -> STM<TBQueue<A>> {
	return do_ { () -> TBQueue<A> in
		let read = !newTVar([] as [A])
		let write = !newTVar([] as [A])
		let rsize = !newTVar(0)
		let wsize = !newTVar(n)
		return TBQueue(rsize, read, wsize, write)
	}
}

public func newTBQueueIO<A>(n : Int) -> IO<TBQueue<A>> {
	return do_ { () -> TBQueue<A> in
		let read = !newTVarIO([] as [A])
		let write = !newTVarIO([] as [A])
		let rsize = !newTVarIO(0)
		let wsize = !newTVarIO(n)
		return TBQueue(rsize, read, wsize, write)
	}
}

public func writeTBQueue<A>(q : TBQueue<A>) -> A -> STM<()> {
	return { x in
		do_ { () -> () in
			let w : Int = !readTVar(q.writeNum)
			if w != 0 {
				writeTVar(q.writeNum)(x: w - 1)
			} else {
				let r : Int = !readTVar(q.readNum)
				if r != 0 {
					writeTVar(q.readNum)(x: 0)
					writeTVar(q.writeNum)(x: r - 1)
				} else {
					retry() as STM<()>
				}
			}
			let listend : [A] = !readTVar(q.writeHead)
			writeTVar(q.writeHead)(x: [x] + listend)
		}
	}
}
