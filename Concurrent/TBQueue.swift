//
//  TBQueue.swift
//  Parallel-iOS
//
//  Created by Robert Widmann on 9/29/14.
//  Copyright (c) 2014 TypeLift. All rights reserved.
//

import Swiftz

/// `TBQueue` is a bounded version of TQueue. The queue has a maximum capacity set when it is 
/// created. If the queue already contains the maximum number of elements, then `write(_:)` blocks
/// until an element is removed from the queue.
///
/// The implementation is based on the traditional purely-functional queue representation that uses 
/// two lists to obtain amortised O(1) enqueue and dequeue operations.
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

	public func write(x : A) -> STM<()> {
		return do_ { () -> () in
			let w : Int = !self.writeNum.read()
			if w != 0 {
				!self.writeNum.write(w - 1)
			} else {
				let r : Int = !self.readNum.read()
				if r != 0 {
					!self.readNum.write(0)
					!self.writeNum.write(r - 1)
				} else {
					let _ : () = !retry()
				}
			}
			let listend : [A] = !self.writeHead.read()
			self.writeHead.write([x] + listend)
		}
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
