//
//  TBQueue.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/29/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

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
	return do_ { () -> TBQueue<A> in
		let read = !newTVar([] as [A])
		let write = !newTVar([] as [A])
		let rsize = !newTVar(0)
		let wsize = !newTVar(n)
		return TBQueue(rsize, read, wsize, write)
	}
}

public func writeTBQueue<A>(q : TBQueue<A>) -> A -> STM<()> {
	return { x in
		do_ { () -> () in
			let w : Int = !q.writeNum.read()
			if w != 0 {
				!q.writeNum.write(w - 1)
			} else {
				let r : Int = !q.readNum.read()
				if r != 0 {
					!q.readNum.write(0)
					!q.writeNum.write(r - 1)
				} else {
					let _ : () = !retry()
				}
			}
			let listend : [A] = !q.writeHead.read()
			q.writeHead.write([x] + listend)
		}
	}
}
