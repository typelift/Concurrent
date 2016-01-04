//
//  TBQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TBQueue<A> {
	let readNum : TVar<Int>
	let readHead : TVar<[A]>
	let writeNum : TVar<Int>
	let writeHead : TVar<[A]>

	private init(_ readNum : TVar<Int>, _ readHead : TVar<[A]>, _ writeNum : TVar<Int>, _ writeHead : TVar<[A]>) {
		self.readNum = readNum
		self.readHead = readHead
		self.writeNum = writeNum
		self.writeHead = writeHead
	}

	public init(n : Int) {
		let read = TVar([A]())
		let write = TVar([A]())
		let rsize = TVar(0)
		let wsize = TVar(n)
		self.init(rsize, read, wsize, write)
	}
}

public func newTBQueue<A>(n : Int) -> STM<TBQueue<A>> {
	let read = TVar([] as [A])
	let write = TVar([] as [A])
	let rsize = TVar(0)
	let wsize = TVar(n)
	return STM<TBQueue<A>>.pure(TBQueue(rsize, read, wsize, write))
}

public func writeTBQueue<A>(q : TBQueue<A>, _ x : A) -> STM<()> {
	return readTVar(q.writeNum).flatMap { w in
		let act : STM<()>
		if w != 0 {
			act = writeTVar(q.writeNum, value: w - 1)
		} else {
			act = readTVar(q.readNum).flatMap { r in
				if r != 0 {
					return writeTVar(q.readNum, value: 0).then(writeTVar(q.writeNum, value: r - 1))
				} else {
					do {
						return try retry()
					} catch _ {
						fatalError()
					}
				}
			}
		}

		return act.then(readTVar(q.writeHead).flatMap { listend in
			return writeTVar(q.writeHead, value: [x] + listend)
		})
	}
}